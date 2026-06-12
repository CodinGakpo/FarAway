from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

# ── Common ────────────────────────────────────────────────

class GeoPoint(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)

class ErrorResponse(BaseModel):
    error: str
    code: str          # e.g. "CAPACITY_UNAVAILABLE", "ROUTE_INFEASIBLE"
    details: dict = {}

# ── Tool 1: Analyze Route ─────────────────────────────────

class AnalyzeRouteRequest(BaseModel):
    trip_id: str
    pickup: GeoPoint
    dropoff: GeoPoint

class AnalyzeRouteResponse(BaseModel):
    feasible: bool
    trip_id: str
    detour_distance_km: float = 0.0
    detour_duration_min: float = 0.0
    detour_percentage: float = 0.0
    route_fit_score: float = 0.0       # 0.0–1.0, higher = better
    rejection_reason: Optional[str] = None

# ── Tool 2: Check Capacity ────────────────────────────────

class CheckCapacityRequest(BaseModel):
    trip_id: str
    weight_kg: float = Field(..., gt=0)
    volume_m3: float = Field(..., gt=0)

class CheckCapacityResponse(BaseModel):
    available: bool
    remaining_weight_kg: float
    remaining_volume_m3: float
    utilization_pct: float             # 0.0–1.0, for pricing surge logic
    rejection_reason: Optional[str] = None

# ── Tool 3: Calculate Price ───────────────────────────────

class CalculatePriceRequest(BaseModel):
    trip_id: str
    shipment_distance_km: float = Field(..., gt=0)
    weight_kg: float = Field(..., gt=0)
    volume_m3: float = Field(..., gt=0)
    goods_type: str = "general"
    declared_value: float = Field(default=0.0, ge=0)
    detour_distance_km: float = Field(default=0.0, ge=0)
    utilization_pct: float = Field(default=0.0, ge=0, le=1)
    city: Optional[str] = None

class PriceBreakdownResponse(BaseModel):
    base_fare: float
    weight_charge: float
    volume_charge: float
    detour_surcharge: float
    declared_value_insurance: float
    goods_type_multiplier: float
    utilization_surge: float
    platform_fee: float
    profitability_floor: float
    is_floor_applied: bool

class CalculatePriceResponse(BaseModel):
    final_price: float
    currency: str = "INR"
    breakdown: PriceBreakdownResponse
    is_profitable: bool

# ── Tool 4: Hold Capacity ─────────────────────────────────

class HoldCapacityRequest(BaseModel):
    trip_id: str
    shipment_id: str
    weight_kg: float = Field(..., gt=0)
    volume_m3: float = Field(..., gt=0)
    price_amount: float = Field(..., gt=0)
    price_breakdown: dict
    detour_distance_km: float = 0.0
    detour_duration_min: float = 0.0

class HoldCapacityResponse(BaseModel):
    success: bool
    booking_id: Optional[str] = None
    hold_expires_at: Optional[datetime] = None
    rejection_reason: Optional[str] = None

# ── Tool 5: Confirm Booking ───────────────────────────────

class ConfirmBookingRequest(BaseModel):
    booking_id: str

class ConfirmBookingResponse(BaseModel):
    success: bool
    message: str

# ── Tool 6: Find Candidate Trips ─────────────────────────

class FindTripsRequest(BaseModel):
    pickup: GeoPoint
    dropoff: GeoPoint
    search_radius_km: float = Field(default=50.0, gt=0, le=200)
    weight_kg: float = Field(..., gt=0)
    volume_m3: float = Field(..., gt=0)
    limit: int = Field(default=10, le=50)

class TripSummary(BaseModel):
    trip_id: str
    departure_at: datetime
    base_distance_km: float
    max_detour_km: float
    dist_pickup_km: float
    dist_dropoff_km: float

class FindTripsResponse(BaseModel):
    trips: list[TripSummary]
    total_found: int
