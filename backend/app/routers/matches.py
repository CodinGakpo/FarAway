from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import List, Optional

from app.database import get_db, is_sqlite
from app.models import Match, Load, Trip, TrainSchedule, User
from app.schemas import MatchResponse, MatchStatusUpdate, OpsStatsResponse, TripResponse, TrainScheduleResponse
from app.auth import get_current_user
from app.routers.trips import get_trip_coordinates
from app.routers.loads import get_load_coordinates, make_load_response

router = APIRouter(
    prefix="/matches",
    tags=["Match Engine"]
)

def get_train_coordinates(train_id: int, db: Session) -> Optional[List[List[float]]]:
    """
    Helper to extract coordinates from Train LineString geometry as [lng, lat] list.
    """
    if is_sqlite:
        return [[80.2707, 13.0827], [79.1388, 12.9691], [77.5696, 12.9780]] # mock corridor coordinates
        
    query = text("SELECT ST_AsGeoJSON(route_geometry) FROM train_schedules WHERE id = :id")
    geom_json = db.execute(query, {"id": train_id}).scalar()
    if geom_json:
        try:
            import json
            geom = json.loads(geom_json)
            return geom.get("coordinates")
        except Exception:
            pass
    return None

def make_match_response(match: Match, db: Session) -> MatchResponse:
    """
    Manually map database Match row into MatchResponse model, avoiding standard from_orm
    cascade failures on missing nested coordinate values.
    """
    load_res = make_load_response(match.load, db) if match.load else None
    
    trip_res = None
    if match.trip:
        trip_res = TripResponse.from_orm(match.trip)
        trip_res.route_coordinates = get_trip_coordinates(match.trip_id, db)
        
    train_res = None
    if match.train_schedule:
        train_res = TrainScheduleResponse.from_orm(match.train_schedule)
        train_res.route_coordinates = get_train_coordinates(match.train_schedule_id, db)
        
    return MatchResponse(
        id=match.id,
        load_id=match.load_id,
        trip_id=match.trip_id,
        train_schedule_id=match.train_schedule_id,
        score=match.score,
        status=match.status,
        explanation=match.explanation,
        created_at=match.created_at,
        load=load_res,
        trip=trip_res,
        train_schedule=train_res
    )

@router.get("/", response_model=List[MatchResponse])
def list_matches(
    load_id: Optional[int] = None,
    status: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    query = db.query(Match)
    
    # Shipper context: filter matches for their loads
    if current_user.role == "shipper":
        query = query.join(Load).filter(Load.shipper_id == current_user.id)
    # Driver context: filter matches for their trips
    elif current_user.role == "driver":
        query = query.join(Trip).filter(Trip.driver_id == current_user.id)

    if load_id is not None:
        query = query.filter(Match.load_id == load_id)
    if status:
        query = query.filter(Match.status == status.upper())

    db_matches = query.all()
    return [make_match_response(match, db) for match in db_matches]


@router.get("/stats", response_model=OpsStatsResponse)
def get_ops_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Stats for Shipper Web Portal Ops Dashboard (Loads matched, CO2 saved, active corridors)
    """
    # 1. Total loads matched (ACCEPTED)
    matched_count = db.query(Match).filter(Match.status == "ACCEPTED").count()
    
    # 2. Total active corridors
    active_corridors_count = db.query(Load).filter(Load.status == "PENDING").count()

    # 3. Calculate CO2 savings (Mock calculation based on loads weight and transit type)
    # Train: 0.15kg CO2 saved per kg weight
    # Truck share: 0.04kg CO2 saved per kg weight
    total_co2 = 0.0
    accepted_matches = db.query(Match).filter(Match.status == "ACCEPTED").all()
    for m in accepted_matches:
        weight = m.load.weight
        if m.train_schedule_id:
            total_co2 += weight * 0.15  # high eco savings on rail
        else:
            total_co2 += weight * 0.04  # shared capacity empty backhaul reduction

    # 4. Corridor statistics
    # Fetch distinct corridors and summarize
    corridors = []
    # Hardcoded/seeded summaries for the demo dashboard charts
    corridors.append({
        "name": "Chennai ➡️ Bangalore",
        "active_loads": 5,
        "matched_count": matched_count,
        "co2_saved": round(total_co2, 2)
    })
    corridors.append({
        "name": "Bangalore ➡️ Chennai",
        "active_loads": 2,
        "matched_count": max(0, matched_count - 1),
        "co2_saved": round(total_co2 * 0.4, 2)
    })

    return OpsStatsResponse(
        total_loads_matched=matched_count,
        total_co2_saved_kg=round(total_co2, 2),
        active_corridors_count=active_corridors_count + matched_count,
        corridor_statistics=corridors
    )


@router.patch("/{match_id}/status", response_model=MatchResponse)
def update_match_status(
    match_id: int,
    status_update: MatchStatusUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    match = db.query(Match).filter(Match.id == match_id).first()
    if not match:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Match not found"
        )

    # Shippers accept/reject proposed matches
    if current_user.role != "shipper" or match.load.shipper_id != current_user.id:
         raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the shipper who created this load can accept or reject this match"
        )

    new_status = status_update.status.upper()
    if new_status not in ["ACCEPTED", "REJECTED"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Status must be either ACCEPTED or REJECTED"
        )

    if match.status != "PROPOSED":
         raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Match is already {match.status}"
        )

    if new_status == "ACCEPTED":
        # 1. Update Load Status to MATCHED
        match.load.status = "MATCHED"

        # 2. If matched to a truck (trip), decrement remaining capacity
        if match.trip_id:
            trip = match.trip
            if match.load.weight > trip.remaining_weight_capacity or match.load.volume > trip.remaining_volume_capacity:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cannot accept match. Truck remaining capacity has changed and is now insufficient."
                )
            trip.remaining_weight_capacity -= match.load.weight
            trip.remaining_volume_capacity -= match.load.volume

        # 3. Reject other matches for the same load
        other_matches = db.query(Match).filter(
            Match.load_id == match.load_id,
            Match.id != match.id,
            Match.status == "PROPOSED"
        ).all()
        for om in other_matches:
            om.status = "REJECTED"

    # Set Match Status
    match.status = new_status
    db.commit()
    db.refresh(match)
    
    return make_match_response(match, db)
