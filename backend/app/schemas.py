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
    origin_name: str
    destination_name: str
    departure_time: datetime
    max_weight_capacity: float = Field(..., gt=0)
    max_volume_capacity: float = Field(..., gt=0)
    # List of [lng, lat] coordinate pairs defining the route path
    route_coordinates: Optional[List[List[float]]] = None

class TripResponse(BaseModel):
    id: int
    driver_id: str
    origin_name: str
    destination_name: str
    departure_time: datetime
    max_weight_capacity: float
    max_volume_capacity: float
    remaining_weight_capacity: float
    remaining_volume_capacity: float
    status: str
    route_coordinates: Optional[List[List[float]]] = None
    created_at: datetime

    class Config:
        from_attributes = True
        orm_mode = True


# --- Load Schemas ---

class LoadCreate(BaseModel):
    pickup_name: str
    dropoff_name: str
    pickup_lat: float = Field(..., ge=-90, le=90)
    pickup_lng: float = Field(..., ge=-180, le=180)
    dropoff_lat: float = Field(..., ge=-90, le=90)
    dropoff_lng: float = Field(..., ge=-180, le=180)
    weight: float = Field(..., gt=0)
    volume: float = Field(..., gt=0)

class LoadResponse(BaseModel):
    id: int
    shipper_id: str
    pickup_name: str
    dropoff_name: str
    pickup_lat: float
    pickup_lng: float
    dropoff_lat: float
    dropoff_lng: float
    weight: float
    volume: float
    status: str
    created_at: datetime

    class Config:
        from_attributes = True
        orm_mode = True


# --- TrainSchedule Schemas ---

class TrainScheduleResponse(BaseModel):
    id: int
    train_number: str
    train_name: str
    origin: str
    destination: str
    departure_time: str
    route_coordinates: Optional[List[List[float]]] = None

    class Config:
        from_attributes = True
        orm_mode = True


# --- Match Schemas ---

class MatchResponse(BaseModel):
    id: int
    load_id: int
    trip_id: Optional[int] = None
    train_schedule_id: Optional[int] = None
    score: float
    status: str
    explanation: Optional[str] = None
    created_at: datetime
    
    # Detailed nested information for matching UI
    load: Optional[LoadResponse] = None
    trip: Optional[TripResponse] = None
    train_schedule: Optional[TrainScheduleResponse] = None

    class Config:
        from_attributes = True
        orm_mode = True

class MatchStatusUpdate(BaseModel):
    status: str = Field(..., description="Must be 'ACCEPTED' or 'REJECTED'")


# --- Rating Schemas ---

class RatingCreate(BaseModel):
    match_id: int
    score: int = Field(..., ge=1, le=5)
    comment: Optional[str] = None

class RatingResponse(BaseModel):
    id: int
    match_id: int
    score: int
    comment: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
        orm_mode = True


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

