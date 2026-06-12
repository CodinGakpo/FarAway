from dataclasses import dataclass
from uuid import UUID
from app.db.client import Database
from app.db.repositories.trip_repo import TripRepository
from app.services.maps.gmaps_client import GoogleMapsClient
from app.services.maps.osrm_client import OSRMClient

@dataclass
class RouteAnalysisResult:
    feasible: bool
    trip_id: UUID
    detour_distance_km: float = 0.0
    detour_duration_min: float = 0.0
    detour_percentage: float = 0.0
    route_fit_score: float = 0.0      # 1.0 = zero detour, 0.0 = at threshold
    rejection_reason: str | None = None

class RouteService:
    def __init__(self, db: Database, maps: GoogleMapsClient, osrm: OSRMClient):
        self.db = db
        self.maps = maps
        self.osrm = osrm

    async def analyze(
        self,
        trip_id: UUID,
        pickup_lat: float, pickup_lng: float,
        dropoff_lat: float, dropoff_lng: float,
    ) -> RouteAnalysisResult:
        async with self.db.acquire() as conn:
            repo = TripRepository(conn)
            trip = await repo.get_by_id(trip_id)

        if not trip or trip.status != 'scheduled':
            return RouteAnalysisResult(
                feasible=False, trip_id=trip_id,
                rejection_reason="Trip not found or not scheduled"
            )

        # PostGIS pre-filter (cheap, no external API call)
        pre_check = await self._postgis_precheck(trip, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng)
        if not pre_check['ok']:
            return RouteAnalysisResult(
                feasible=False, trip_id=trip_id,
                rejection_reason=pre_check['reason']
            )

        # External routing API (expensive, only if pre-check passes)
        try:
            new_dist_km, new_dur_min = await self.maps.get_route_with_stops(
                origin=trip.origin_point,
                stops=[(pickup_lat, pickup_lng), (dropoff_lat, dropoff_lng)],
                destination=trip.destination_point,
            )
        except Exception:
            # OSRM fallback
            new_dist_km, new_dur_min = await self.osrm.get_route_with_stops(
                origin=trip.origin_point,
                stops=[(pickup_lat, pickup_lng), (dropoff_lat, dropoff_lng)],
                destination=trip.destination_point,
            )

        detour_km = new_dist_km - trip.base_distance_km
        detour_min = new_dur_min - trip.base_duration_min

        if detour_km > trip.max_detour_km:
            return RouteAnalysisResult(
                feasible=False, trip_id=trip_id, detour_distance_km=detour_km,
                rejection_reason=f"Detour {detour_km:.1f}km exceeds limit {trip.max_detour_km}km"
            )
        if detour_min > trip.max_detour_min:
            return RouteAnalysisResult(
                feasible=False, trip_id=trip_id, detour_duration_min=detour_min,
                rejection_reason=f"Detour {detour_min:.0f}min exceeds limit {trip.max_detour_min}min"
            )

        # Score: how "good" is this route match (1.0 = perfect, 0.0 = at threshold)
        dist_score = 1.0 - (detour_km / max(trip.max_detour_km, 0.001))
        time_score = 1.0 - (detour_min / max(trip.max_detour_min, 0.001))
        fit_score = min(dist_score, time_score)

        return RouteAnalysisResult(
            feasible=True,
            trip_id=trip_id,
            detour_distance_km=round(detour_km, 2),
            detour_duration_min=round(detour_min, 2),
            detour_percentage=round(detour_km / trip.base_distance_km * 100, 1),
            route_fit_score=round(fit_score, 3),
        )

    async def _postgis_precheck(self, trip, pu_lat, pu_lng, do_lat, do_lng) -> dict:
        async with self.db.acquire() as conn:
            row = await conn.fetchrow("""
                SELECT
                    ST_DWithin(route_polyline,
                        ST_MakePoint($2, $1)::geography, $5 * 1000) AS pickup_near,
                    ST_DWithin(route_polyline,
                        ST_MakePoint($4, $3)::geography, $5 * 1000) AS dropoff_near,
                    ST_LineLocatePoint(
                        ST_Transform(route_polyline::geometry, 3857),
                        ST_Transform(ST_MakePoint($2, $1)::geometry, 3857)
                    ) AS pickup_pos,
                    ST_LineLocatePoint(
                        ST_Transform(route_polyline::geometry, 3857),
                        ST_Transform(ST_MakePoint($4, $3)::geometry, 3857)
                    ) AS dropoff_pos
                FROM trips WHERE id = $6
            """, pu_lat, pu_lng, do_lat, do_lng, trip.max_detour_km, trip.id)

        if not row['pickup_near']:
            return {'ok': False, 'reason': 'Pickup point too far from route'}
        if not row['dropoff_near']:
            return {'ok': False, 'reason': 'Dropoff point too far from route'}
        if row['pickup_pos'] >= row['dropoff_pos']:
            return {'ok': False, 'reason': 'Dropoff appears before pickup on route direction'}
        return {'ok': True}
