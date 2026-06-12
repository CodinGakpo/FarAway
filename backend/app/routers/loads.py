import logging
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import text
from sqlalchemy.orm import Session
from typing import List, Optional, Tuple

from app.database import get_db, is_sqlite
from app.models import Load, User
from app.schemas import LoadCreate, LoadResponse
from app.auth import get_current_user, RoleChecker
from app.services.match_service import MatchService

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/loads",
    tags=["Shipper Loads"]
)

shipper_only = RoleChecker(["shipper"])

def get_load_coordinates(load_id: int, db: Session) -> Tuple[float, float, float, float]:
    """
    Helper to extract coordinates from PostGIS POINT geometries as (p_lat, p_lng, d_lat, d_lng).
    """
    if is_sqlite:
        # Default mock coords: Vellore to Bangalore
        return 12.9165, 79.1325, 12.9716, 77.5946
        
    query = text("""
        SELECT ST_Y(pickup_geometry) as p_lat, 
               ST_X(pickup_geometry) as p_lng, 
               ST_Y(dropoff_geometry) as d_lat, 
               ST_X(dropoff_geometry) as d_lng 
        FROM loads WHERE id = :id
    """)
    res = db.execute(query, {"id": load_id}).fetchone()
    if res:
        return res[0], res[1], res[2], res[3]
    return 0.0, 0.0, 0.0, 0.0

def make_load_response(load: Load, db: Session) -> LoadResponse:
    p_lat, p_lng, d_lat, d_lng = get_load_coordinates(load.id, db)
    return LoadResponse(
        id=load.id,
        shipper_id=load.shipper_id,
        pickup_name=load.pickup_name,
        dropoff_name=load.dropoff_name,
        weight=load.weight,
        volume=load.volume,
        status=load.status,
        created_at=load.created_at,
        pickup_lat=p_lat,
        pickup_lng=p_lng,
        dropoff_lat=d_lat,
        dropoff_lng=d_lng
    )

@router.post("", response_model=LoadResponse, status_code=status.HTTP_201_CREATED)
def create_load(
    load_in: LoadCreate, 
    db: Session = Depends(get_db), 
    current_user: User = Depends(shipper_only)
):
    # Create PostGIS point geometry strings (SRID 4326)
    # WKT Format: POINT(longitude latitude)
    pickup_wkt = f"SRID=4326;POINT({load_in.pickup_lng} {load_in.pickup_lat})"
    dropoff_wkt = f"SRID=4326;POINT({load_in.dropoff_lng} {load_in.dropoff_lat})"

    # Save to Database
    db_load = Load(
        shipper_id=current_user.id,
        pickup_name=load_in.pickup_name,
        dropoff_name=load_in.dropoff_name,
        weight=load_in.weight,
        volume=load_in.volume,
        pickup_geometry=pickup_wkt,
        dropoff_geometry=dropoff_wkt,
        status="PENDING"
    )
    db.add(db_load)
    db.commit()
    db.refresh(db_load)

    # 4. Trigger Celery Matching Job
    try:
        from app.tasks import run_matching_job
        # Dispatch Celery background task
        run_matching_job.delay(db_load.id)
        logger.info(f"Dispatched Celery matching task for Load {db_load.id}")
    except Exception as e:
        logger.warning(f"Could not start Celery worker task: {str(e)}. Running matching synchronously.")
        # Fallback to local synchronous matching so dev tests work without Redis/Celery running
        MatchService.run_spatial_matching(db_load.id, db)

    return make_load_response(db_load, db)


@router.get("", response_model=List[LoadResponse])
def list_loads(
    shipper_id: Optional[str] = None,
    status: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    query = db.query(Load)
    
    # Restriction: shippers only see their own loads
    if current_user.role == "shipper":
        query = query.filter(Load.shipper_id == current_user.id)
    elif shipper_id:
        query = query.filter(Load.shipper_id == shipper_id)
        
    if status:
        query = query.filter(Load.status == status.upper())

    loads = query.all()
    return [make_load_response(load, db) for load in loads]


@router.get("/{load_id}", response_model=LoadResponse)
def get_load(
    load_id: int, 
    db: Session = Depends(get_db), 
    current_user: User = Depends(get_current_user)
):
    load = db.query(Load).filter(Load.id == load_id).first()
    if not load:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Load with ID {load_id} not found"
        )
    
    # Shipper ownership authorization
    if current_user.role == "shipper" and load.shipper_id != current_user.id:
         raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied"
        )

    return make_load_response(load, db)


@router.delete("/{load_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_load(
    load_id: int, 
    db: Session = Depends(get_db), 
    current_user: User = Depends(shipper_only)
):
    load = db.query(Load).filter(Load.id == load_id).first()
    if not load:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Load not found"
        )
    
    if load.shipper_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not authorized to delete this load"
        )

    db.delete(load)
    db.commit()
    return None
