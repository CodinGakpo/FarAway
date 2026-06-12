from fastapi import APIRouter, Depends, HTTPException, status
from app.api_models import *
from app.services.route_service import RouteService
from app.services.capacity_service import CapacityService
from app.services.pricing_service import PricingService
from app.dependencies import get_route_service, get_capacity_service, get_pricing_service, get_db

router = APIRouter(prefix="/agent/tools", tags=["agent-tools"])

@router.post("/analyze-route", response_model=AnalyzeRouteResponse)
async def analyze_route(
    req: AnalyzeRouteRequest,
    svc: RouteService = Depends(get_route_service),
):
    result = await svc.analyze(
        trip_id=req.trip_id,
        pickup_lat=req.pickup.lat, pickup_lng=req.pickup.lng,
        dropoff_lat=req.dropoff.lat, dropoff_lng=req.dropoff.lng,
    )
    return AnalyzeRouteResponse(**result.__dict__)

@router.post("/check-capacity", response_model=CheckCapacityResponse)
async def check_capacity(
    req: CheckCapacityRequest,
    svc: CapacityService = Depends(get_capacity_service),
):
    result = await svc.check(req.trip_id, req.weight_kg, req.volume_m3)
    return CheckCapacityResponse(**result.__dict__)

@router.post("/calculate-price", response_model=CalculatePriceResponse)
async def calculate_price(
    req: CalculatePriceRequest,
    svc: PricingService = Depends(get_pricing_service),
):
    params = await svc.load_params(city=req.city)
    result = svc.calculate(
        params=params,
        shipment_distance_km=req.shipment_distance_km,
        weight_kg=req.weight_kg,
        volume_m3=req.volume_m3,
        goods_type=req.goods_type,
        declared_value=req.declared_value,
        detour_km=req.detour_distance_km,
        utilization_pct=req.utilization_pct,
    )
    return CalculatePriceResponse(
        final_price=result.final_price,
        breakdown=PriceBreakdownResponse(**result.breakdown.__dict__),
        is_profitable=result.is_profitable,
    )

@router.post("/hold-capacity", response_model=HoldCapacityResponse)
async def hold_capacity(
    req: HoldCapacityRequest,
    svc: CapacityService = Depends(get_capacity_service),
):
    result = await svc.hold(
        trip_id=req.trip_id,
        shipment_id=req.shipment_id,
        weight_kg=req.weight_kg,
        volume_m3=req.volume_m3,
        price_amount=req.price_amount,
        price_breakdown=req.price_breakdown,
        detour_km=req.detour_distance_km,
        detour_min=req.detour_duration_min,
    )
    return HoldCapacityResponse(**result.__dict__)

@router.post("/confirm-booking", response_model=ConfirmBookingResponse)
async def confirm_booking(
    req: ConfirmBookingRequest,
    svc: CapacityService = Depends(get_capacity_service),
):
    success = await svc.confirm(req.booking_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "Booking hold expired or not found", "code": "HOLD_EXPIRED"}
        )
    return ConfirmBookingResponse(success=True, message="Booking confirmed")

@router.post("/find-trips", response_model=FindTripsResponse)
async def find_candidate_trips(
    req: FindTripsRequest,
    db=Depends(get_db),
):
    from app.db.repositories.trip_repo import TripRepository
    async with db.acquire() as conn:
        repo = TripRepository(conn)
        trips = await repo.find_candidate_trips(
            pickup_lng=req.pickup.lng, pickup_lat=req.pickup.lat,
            dropoff_lng=req.dropoff.lng, dropoff_lat=req.dropoff.lat,
            search_radius_km=req.search_radius_km,
            limit=req.limit,
        )
    return FindTripsResponse(
        trips=[TripSummary(
            trip_id=t.id, departure_at=t.departure_at,
            base_distance_km=t.base_distance_km,
            max_detour_km=t.max_detour_km,
            dist_pickup_km=t.dist_pickup_km,
            dist_dropoff_km=t.dist_dropoff_km,
        ) for t in trips],
        total_found=len(trips),
    )
