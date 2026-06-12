from pydantic import BaseModel, EmailStr, Field
from datetime import datetime
from typing import Optional, List, Any, Dict

# --- User / Auth Schemas ---

class UserBase(BaseModel):
    email: EmailStr
    role: str = Field(..., description="Must be either 'driver' or 'shipper'")
    name: Optional[str] = None

class UserCreate(UserBase):
    id: str = Field(..., description="Firebase Auth UID")

class UserResponse(UserBase):
    id: str
    created_at: datetime

    class Config:
        from_attributes = True
        orm_mode = True

class TokenData(BaseModel):
    email: Optional[str] = None
    role: Optional[str] = None
    user_id: Optional[str] = None


# --- Trip Schemas ---

class TripCreate(BaseModel):
    origin_name: str = Field(..., alias="origin")
    destination_name: str = Field(..., alias="destination")
    departure_time: datetime = Field(..., alias="date")
    max_weight_capacity: float = Field(..., gt=0, alias="maxWeight")
    max_volume_capacity: float = Field(..., gt=0, alias="maxVolume")
    # List of [lng, lat] coordinate pairs defining the route path
    route_coordinates: Optional[List[List[float]]] = None

    class Config:
        populate_by_name = True
        allow_population_by_field_name = True

class TripResponse(BaseModel):
    id: int
    driver_id: str = Field(..., alias="driverId")
    origin_name: str = Field(..., alias="origin")
    destination_name: str = Field(..., alias="destination")
    departure_time: datetime = Field(..., alias="date")
    max_weight_capacity: float = Field(..., alias="maxWeight")
    max_volume_capacity: float = Field(..., alias="maxVolume")
    remaining_weight_capacity: float = Field(..., alias="remainingWeight")
    remaining_volume_capacity: float = Field(..., alias="remainingVolume")
    status: str
    route_coordinates: Optional[List[List[float]]] = Field(None, alias="routeCoordinates")
    created_at: datetime = Field(..., alias="createdAt")

    class Config:
        from_attributes = True
        orm_mode = True
        populate_by_name = True
        allow_population_by_field_name = True





# --- Ops Dashboard Stats ---

class OpsStatsResponse(BaseModel):
    total_loads_matched: int
    total_co2_saved_kg: float
    active_corridors_count: int
    corridor_statistics: List[Dict[str, Any]] = []


# --- Trip Optimization Schemas ---

class TripOptimizationRequest(BaseModel):
    trip_id: int
    cost_per_km: Optional[float] = Field(15.0, description="Driver's variable cost per kilometer (fuel, wear and tear)")

class PathStop(BaseModel):
    name: str
    lat: float
    lng: float
    action: str = Field(..., description="Action to perform: 'start', 'pickup', 'dropoff', or 'destination'")
    load_id: Optional[int] = None
    remaining_weight: float
    remaining_volume: float

class TripOptimizationResponse(BaseModel):
    recommended_loads: List[int] = Field(..., description="IDs of loads that are profitable to pick up")
    rejected_loads: List[Dict[str, Any]] = Field(..., description="Details of loads that were rejected (with reasons)")
    optimized_path: List[PathStop] = Field(..., description="Ordered stops for the optimal delivery path")
    base_distance_km: float
    optimized_distance_km: float
    deviation_distance_km: float
    extra_fuel_cost: float
    gross_revenue: float
    net_profit: float
    trace: str = Field(..., description="Natural language reasoning trace of the optimizer")


# --- Shipment Schemas ---

class ShipmentCreate(BaseModel):
    trip_id: Optional[int] = Field(None, alias="tripId")
    pickup_location: str = Field(..., alias="pickupLocation")
    dropoff_location: str = Field(..., alias="dropoffLocation")
    weight: float = Field(..., gt=0)
    volume: float = Field(..., gt=0)
    cargo_category: str = Field(..., alias="cargoCategory")

    class Config:
        populate_by_name = True
        allow_population_by_field_name = True

class ShipmentResponse(BaseModel):
    id: int
    customer_id: str
    trip_id: int
    pickup_location: str
    dropoff_location: str
    weight: float
    volume: float
    cargo_category: str
    price: float
    status: str
    feasibility_status: bool
    feasibility_trace: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
        orm_mode = True
        populate_by_name = True
        allow_population_by_field_name = True

class ShipmentStatusUpdate(BaseModel):
    status: str

