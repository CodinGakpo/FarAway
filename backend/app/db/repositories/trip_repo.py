from dataclasses import dataclass
from uuid import UUID
from typing import Optional, List
import asyncpg
from datetime import datetime

@dataclass
class TripRow:
    id: UUID
    truck_id: UUID
    driver_id: UUID
    base_distance_km: float
    max_detour_km: float
    max_detour_min: float
    status: str
    departure_at: datetime
    base_duration_min: float
    origin_point: tuple
    destination_point: tuple
    dist_pickup_km: Optional[float] = None

    dist_dropoff_km: Optional[float] = None

class TripRepository:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def find_candidate_trips(
        self,
        pickup_lng: float, pickup_lat: float,
        dropoff_lng: float, dropoff_lat: float,
        search_radius_km: float = 50.0,
        limit: int = 20,
    ) -> List[TripRow]:
        sql = """
            SELECT t.id, t.truck_id, t.driver_id, t.base_distance_km,
                   t.max_detour_km, t.max_detour_min, t.status,
                   t.departure_at,
                   ST_Distance(t.route_polyline,
                       ST_MakePoint($1, $2)::geography) / 1000.0 AS dist_pickup_km,
                   ST_Distance(t.route_polyline,
                       ST_MakePoint($3, $4)::geography) / 1000.0 AS dist_dropoff_km
            FROM trips t
            JOIN trucks tr ON tr.id = t.truck_id
            WHERE t.status = 'scheduled'
              AND t.departure_at > NOW()
              AND ST_DWithin(t.route_polyline,
                    ST_MakePoint($1, $2)::geography, $5 * 1000)
              AND ST_DWithin(t.route_polyline,
                    ST_MakePoint($3, $4)::geography, $5 * 1000)
            ORDER BY t.departure_at ASC
            LIMIT $6
        """
        rows = await self.conn.fetch(
            sql, pickup_lng, pickup_lat, dropoff_lng, dropoff_lat,
            search_radius_km, limit
        )
        return [TripRow(**dict(r)) for r in rows]

    async def get_by_id(self, trip_id: UUID) -> Optional[TripRow]:
        row = await self.conn.fetchrow(
            "SELECT * FROM trips WHERE id = $1", trip_id
        )
        if row:
            kwargs = dict(row)
            valid_keys = {f for f in TripRow.__dataclass_fields__}
            filtered_kwargs = {k: v for k, v in kwargs.items() if k in valid_keys}
            return TripRow(**filtered_kwargs)
        return None
