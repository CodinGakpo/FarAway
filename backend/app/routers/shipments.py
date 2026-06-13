from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional

from app.database import get_db
from app.models import Shipment, Trip, User
from app.schemas import ShipmentCreate, ShipmentResponse, ShipmentStatusUpdate
from app.auth import get_current_user, RoleChecker
from app.services.agent_service import FreightShareAgentService

router = APIRouter(
    prefix="/shipments",
    tags=["Shipments"]
)

customer_only = RoleChecker(["customer", "shipper"])
driver_only = RoleChecker(["driver"])

@router.post("", response_model=ShipmentResponse, status_code=status.HTTP_201_CREATED)
def create_shipment_request(
    shipment_in: ShipmentCreate, 
    db: Session = Depends(get_db), 
    current_user: User = Depends(customer_only)
):
    # 1. Verify trip exists
    trip = db.query(Trip).filter(Trip.id == shipment_in.trip_id).first()
    if not trip:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Target trip with ID {shipment_in.trip_id} not found"
        )
    
    # 2. Check if trip is active
    if trip.status.upper() != "ACTIVE":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot book shipment on an inactive or completed trip"
        )

    # 3. Invoke AI Agent to evaluate feasibility and calculate pricing
    agent_result = FreightShareAgentService.evaluate_shipment(
        pickup=shipment_in.pickup_location,
        dropoff=shipment_in.dropoff_location,
        weight=shipment_in.weight,
        volume=shipment_in.volume,
        cargo_category=shipment_in.cargo_category,
        trip_origin=trip.origin_name,
        trip_destination=trip.destination_name,
        rem_weight=trip.remaining_weight_capacity,
        rem_volume=trip.remaining_volume_capacity
    )

    # 4. Create the draft shipment entry in the database
    db_shipment = Shipment(
        customer_id=current_user.id,
        trip_id=shipment_in.trip_id,
        pickup_location=shipment_in.pickup_location,
        dropoff_location=shipment_in.dropoff_location,
        weight=shipment_in.weight,
        volume=shipment_in.volume,
        cargo_category=shipment_in.cargo_category,
        price=agent_result["price"] if agent_result["feasible"] else 0.0,
        status="DRAFT",  # Saved in draft; customer must confirm booking
        feasibility_status=agent_result["feasible"],
        feasibility_trace=agent_result["trace"]
    )
    
    db.add(db_shipment)
    db.commit()
    db.refresh(db_shipment)
    return db_shipment


@router.post("/{shipment_id}/confirm", response_model=ShipmentResponse)
def confirm_shipment_booking(
    shipment_id: int, 
    db: Session = Depends(get_db), 
    current_user: User = Depends(customer_only)
):
    shipment = db.query(Shipment).filter(Shipment.id == shipment_id).first()
    if not shipment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Shipment request not found"
        )

    # Verify ownership
    if shipment.customer_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only confirm shipment bookings that you created"
        )

    if shipment.status != "DRAFT":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Shipment booking cannot be confirmed. Current status: {shipment.status}"
        )

    # Confirm the feasibility check succeeded
    if not shipment.feasibility_status:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot confirm an infeasible shipment. Review the AI agent trace."
        )

    # Change status to PENDING (submitted for driver approval)
    shipment.status = "PENDING"
    db.commit()
    db.refresh(shipment)
    return shipment


@router.patch("/{shipment_id}/status", response_model=ShipmentResponse)
def update_shipment_status(
    shipment_id: int,
    status_update: ShipmentStatusUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    shipment = db.query(Shipment).filter(Shipment.id == shipment_id).first()
    if not shipment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Shipment not found"
        )

    new_status = status_update.status.upper()
    trip = shipment.trip

    # Authenticate and Authorize state changes:
    # 1. Driver actions: ACCEPTED, REJECTED, PICKED_UP, DELIVERED
    if new_status in ["ACCEPTED", "REJECTED", "PICKED_UP", "DELIVERED"]:
        if current_user.role != "driver" or trip.driver_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the driver assigned to this trip can update this shipment status"
            )

        if new_status == "ACCEPTED":
            if shipment.status != "PENDING":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Cannot accept shipment. Shipment is currently in '{shipment.status}' status."
                )
            
            # Double check capacity check again to avoid double-booking errors
            if shipment.weight > trip.remaining_weight_capacity or shipment.volume > trip.remaining_volume_capacity:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cannot accept shipment. Truck capacity limits exceeded."
                )
            
            # Deduct truck capacity
            trip.remaining_weight_capacity -= shipment.weight
            trip.remaining_volume_capacity -= shipment.volume

        elif new_status == "REJECTED":
            if shipment.status != "PENDING":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Cannot reject shipment. Current status: '{shipment.status}'."
                )

        elif new_status == "PICKED_UP":
            if shipment.status != "ACCEPTED":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cannot pick up shipment. It must be ACCEPTED first."
                )

        elif new_status == "DELIVERED":
            if shipment.status != "PICKED_UP":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cannot deliver shipment. It must be PICKED_UP first."
                )

    # 2. Customer cancel actions (e.g. if they cancel a pending request)
    # Note: We can expand this, but let's stick to driver updates for the MVP.
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid status change sequence requested."
        )

    # Update state
    shipment.status = new_status
    db.commit()
    db.refresh(shipment)
    return shipment


@router.get("", response_model=List[ShipmentResponse])
def list_shipments(
    customer_id: Optional[int] = None,
    trip_id: Optional[int] = None,
    driver_id: Optional[int] = None,
    status: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    query = db.query(Shipment)

    # Filter restrictions:
    # A customer/shipper should only see their own shipments.
    if current_user.role in ["customer", "shipper"]:
        query = query.filter(Shipment.customer_id == current_user.id)
    elif current_user.role == "driver":
        # A driver should only see shipments for trips they own
        query = query.join(Trip).filter(Trip.driver_id == current_user.id)

    # Apply optional queries
    if customer_id is not None and current_user.role != "customer":
        # Only allow filtering other customer IDs if driver
        query = query.filter(Shipment.customer_id == customer_id)
    if trip_id is not None:
        query = query.filter(Shipment.trip_id == trip_id)
    if status is not None:
        query = query.filter(Shipment.status == status.upper())

    return query.all()


@router.get("/{shipment_id}", response_model=ShipmentResponse)
def get_shipment(
    shipment_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    shipment = db.query(Shipment).filter(Shipment.id == shipment_id).first()
    if not shipment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Shipment not found"
        )
    
    # Ownership authorization check
    if current_user.role == "customer" and shipment.customer_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied to this shipment record"
        )
    elif current_user.role == "driver" and shipment.trip.driver_id != current_user.id:
         raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied. You are not the driver for the assigned trip."
        )

    return shipment
