from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from app.database import get_db
from app.models import Trip, User
from app.auth import get_current_user
from app.services.agent_service import FreightShareAgentService

router = APIRouter(
    prefix="/agent",
    tags=["AI Agent Interface"]
)

class AgentEvaluationRequest(BaseModel):
    trip_id: int
    pickup_location: str
    dropoff_location: str
    weight: float = Field(..., gt=0)
    volume: float = Field(..., gt=0)
    cargo_category: str = Field(..., description="Must be 'fragile', 'general', or 'perishable'")
class AgentEvaluationResponse(BaseModel):
    feasible: bool
    price: float
    trace: str

from app.schemas import TripOptimizationRequest, TripOptimizationResponse
from app.services.optimization_service import OptimizationService

@router.post("/evaluate", response_model=AgentEvaluationResponse)
def evaluate_shipment_feasibility(
    request: AgentEvaluationRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Directly query the AI Agent to check feasibility, capacity, and price
    for a proposed route, without creating a database shipment.
    """
    trip = db.query(Trip).filter(Trip.id == request.trip_id).first()
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Trip with ID {request.trip_id} not found"
        )

    agent_result = FreightShareAgentService.evaluate_shipment(
        pickup=request.pickup_location,
        dropoff=request.dropoff_location,
        weight=request.weight,
        volume=request.volume,
        cargo_category=request.cargo_category,
        trip_origin=trip.origin_name,
        trip_destination=trip.destination_name,
        rem_weight=trip.remaining_weight_capacity,
        rem_volume=trip.remaining_volume_capacity
    )

    return AgentEvaluationResponse(
        feasible=agent_result["feasible"],
        price=agent_result["price"] if agent_result["feasible"] else 0.0,
        trace=agent_result["trace"]
    )

@router.post("/optimize-trip", response_model=TripOptimizationResponse)
def optimize_driver_trip(
    request: TripOptimizationRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Runs the AI Agent combinatorial path and cost optimization to select the most
    profitable matching cargo packages and sequencing them for delivery.
    """
    try:
        opt_result = OptimizationService.optimize_trip(
            trip_id=request.trip_id,
            db=db,
            cost_per_km=request.cost_per_km
        )
        return opt_result
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Optimization failed: {str(e)}"
        )

