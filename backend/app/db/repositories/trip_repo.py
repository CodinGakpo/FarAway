from dataclasses import dataclass
from uuid import UUID
from typing import Optional, List
import asyncpg
from datetime import datetime

@dataclass
class TripRow:
    id: str
    truck_id: str = "truck_1"
    driver_id: str = "driver_1"
    base_distance_km: float = 1000.0
    max_detour_km: float = 100.0
    max_detour_min: float = 120.0
    status: str = "ACTIVE"
    departure_at: datetime = datetime.now()
    base_duration_min: float = 600.0
    origin_point: tuple = (0.0, 0.0)
    destination_point: tuple = (0.0, 0.0)
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
            SELECT t.id::text as id, 
                   'truck_dummy' as truck_id, 
                   t.driver_id, 
                   (ST_Length(t.route_geometry::geography) / 1000.0)::float as base_distance_km,
                   100.0::float as max_detour_km, 
                   120.0::float as max_detour_min, 
                   t.status,
                   t.departure_time as departure_at,
                   ST_Distance(t.route_geometry,
                       ST_MakePoint($1, $2)::geography) / 1000.0 AS dist_pickup_km,
                   ST_Distance(t.route_geometry,
                       ST_MakePoint($3, $4)::geography) / 1000.0 AS dist_dropoff_km,
                   ARRAY[ST_Y(ST_StartPoint(t.route_geometry)), ST_X(ST_StartPoint(t.route_geometry))] as origin_point,
                   ARRAY[ST_Y(ST_EndPoint(t.route_geometry)), ST_X(ST_EndPoint(t.route_geometry))] as destination_point
            FROM trips t
            WHERE t.status = 'ACTIVE'
              AND DATE(t.departure_time) >= CURRENT_DATE
              AND ST_DWithin(t.route_geometry,
                    ST_MakePoint($1, $2)::geography, $5 * 1000)
              AND ST_DWithin(t.route_geometry,
                    ST_MakePoint($3, $4)::geography, $5 * 1000)
            ORDER BY t.departure_time ASC
            LIMIT $6
        """
        rows = await self.conn.fetch(
            sql, pickup_lng, pickup_lat, dropoff_lng, dropoff_lat,
            search_radius_km, limit
        )
        return [TripRow(**dict(r)) for r in rows]

    async def get_by_id(self, trip_id: str) -> Optional[TripRow]:
        row = await self.conn.fetchrow(
            """
            SELECT t.id::text as id, 
                   'truck_dummy' as truck_id, 
                   t.driver_id, 
                   (ST_Length(t.route_geometry::geography) / 1000.0)::float as base_distance_km,
                   100.0::float as max_detour_km, 
                   120.0::float as max_detour_min, 
                   t.status,
                   t.departure_time as departure_at,
                   0.0 as dist_pickup_km,
                   0.0 as dist_dropoff_km,
                   ARRAY[ST_Y(ST_StartPoint(t.route_geometry)), ST_X(ST_StartPoint(t.route_geometry))] as origin_point,
                   ARRAY[ST_Y(ST_EndPoint(t.route_geometry)), ST_X(ST_EndPoint(t.route_geometry))] as destination_point
            FROM trips t WHERE t.id = $1::int
            """, int(trip_id)
        )
        if row:
            kwargs = dict(row)
            valid_keys = {f for f in TripRow.__dataclass_fields__}
            filtered_kwargs = {k: v for k, v in kwargs.items() if k in valid_keys}
            return TripRow(**filtered_kwargs)
        return None
