import json
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import text
from sqlalchemy.orm import Session
from typing import List, Optional

from app.database import get_db, is_sqlite
from app.models import Trip, User
from app.schemas import TripCreate, TripResponse, ShipmentResponse
from app.auth import get_current_user, RoleChecker
from app.services.geo_service import GeoService

router = APIRouter(
    prefix="/trips",
    tags=["Trips"]
)

driver_only = RoleChecker(["driver"])

def get_trip_coordinates(trip_id: int, db: Session) -> Optional[List[List[float]]]:
    """
    Helper to extract coordinates from PostGIS LineString geometry as [lng, lat] list.
    """
    if is_sqlite:
        return [[80.2707, 13.0827], [77.5946, 12.9716]] # mock Chennai->Bangalore coordinates
        
    query = text("SELECT ST_AsGeoJSON(route_geometry) FROM legacy_trips WHERE id = :id")
    geom_json = db.execute(query, {"id": trip_id}).scalar()
    if geom_json:
        try:
            geom = json.loads(geom_json)
            return geom.get("coordinates")
        except Exception:
            pass
    return None

@router.post("", response_model=TripResponse, status_code=status.HTTP_201_CREATED)
def create_trip(
    trip_in: TripCreate, 
    db: Session = Depends(get_db), 
    current_user: User = Depends(driver_only)
):
    # 1. Generate polyline coordinates and distance via GeoService
    coords, distance_km = GeoService.get_route_polyline(
        trip_in.origin_name, 
        trip_in.destination_name
    )

    # 2. Create PostGIS LineString WKT element (SRID 4326)
    # WKT Format: 'LINESTRING(lng1 lat1, lng2 lat2, ...)'
    line_pts = ", ".join([f"{pt[0]} {pt[1]}" for pt in coords])
    route_wkt = f"SRID=4326;LINESTRING({line_pts})"

    # 3. Create db entry
    db_trip = Trip(
        driver_id=current_user.id,
        origin_name=trip_in.origin_name,
        destination_name=trip_in.destination_name,
        departure_time=trip_in.departure_time,
        max_weight_capacity=trip_in.max_weight_capacity,
        max_volume_capacity=trip_in.max_volume_capacity,
        remaining_weight_capacity=trip_in.max_weight_capacity,
        remaining_volume_capacity=trip_in.max_volume_capacity,
        route_geometry=route_wkt,
        status="ACTIVE"
    )
    db.add(db_trip)
    db.commit()
    db.refresh(db_trip)
    
    response_data = TripResponse.from_orm(db_trip)
    response_data.route_coordinates = coords
    return response_data


@router.get("", response_model=List[TripResponse])
def list_trips(
    driver_id: Optional[str] = None,
    status: Optional[str] = "ACTIVE",
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    query = db.query(Trip)
    if driver_id:
        query = query.filter(Trip.driver_id == driver_id)
    if status:
        query = query.filter(Trip.status == status.upper())

    trips = query.all()
    results = []
    for trip in trips:
        res = TripResponse.from_orm(trip)
        res.route_coordinates = get_trip_coordinates(trip.id, db)
        results.append(res)
    return results

@router.get("/active", response_model=TripResponse)
def get_active_trip(
    db: Session = Depends(get_db),
    current_user: User = Depends(driver_only)
):
    trip = db.query(Trip).filter(Trip.driver_id == current_user.id, Trip.status == "ACTIVE").first()
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active trip found"
        )
    
    res = TripResponse.from_orm(trip)
    res.route_coordinates = get_trip_coordinates(trip.id, db)
    return res

@router.get("/active", response_model=TripResponse)
def get_active_trip(
    db: Session = Depends(get_db),
    current_user: User = Depends(driver_only)
):
    trip = db.query(Trip).filter(
        Trip.driver_id == current_user.id, 
        Trip.status == "ACTIVE"
    ).first()
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active trip found"
        )
    
    res = TripResponse.from_orm(trip)
    res.route_coordinates = get_trip_coordinates(trip.id, db)
    return res


@router.get("/history", response_model=List[TripResponse])
def get_trip_history(
    db: Session = Depends(get_db),
    current_user: User = Depends(driver_only)
):
    trips = db.query(Trip).filter(
        Trip.driver_id == current_user.id,
        Trip.status == "COMPLETED"
    ).all()
    
    results = []
    for trip in trips:
        res = TripResponse.from_orm(trip)
        res.route_coordinates = get_trip_coordinates(trip.id, db)
        results.append(res)
    return results


@router.get("/{trip_id}", response_model=TripResponse)
def get_trip(
    trip_id: int, 
    db: Session = Depends(get_db), 
    current_user: User = Depends(get_current_user)
):
    trip = db.query(Trip).filter(Trip.id == trip_id).first()
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Trip with ID {trip_id} not found"
        )
    
    res = TripResponse.from_orm(trip)
    res.route_coordinates = get_trip_coordinates(trip.id, db)
    return res


@router.delete("/{trip_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_trip(
    trip_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(driver_only)
):
    trip = db.query(Trip).filter(Trip.id == trip_id).first()
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Trip not found"
        )
    
    if trip.driver_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not the driver assigned to this trip"
        )

    db.delete(trip)
    db.commit()
    return None


@router.get("/{trip_id}/requests", response_model=List[ShipmentResponse])
def get_incoming_requests(
    trip_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(driver_only)
):
    from app.models import Shipment
    trip = db.query(Trip).filter(Trip.id == trip_id, Trip.driver_id == current_user.id).first()
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Trip not found"
        )
    return db.query(Shipment).filter(Shipment.trip_id == trip_id, Shipment.status == "PENDING").all()


@router.get("/{trip_id}/shipments", response_model=List[ShipmentResponse])
def get_trip_shipments(
    trip_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(driver_only)
):
    from app.models import Shipment
    trip = db.query(Trip).filter(Trip.id == trip_id, Trip.driver_id == current_user.id).first()
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Trip not found"
        )
    return db.query(Shipment).filter(
        Shipment.trip_id == trip_id, 
        Shipment.status.in_(["ACCEPTED", "PICKED_UP", "DELIVERED"])
    ).all()
