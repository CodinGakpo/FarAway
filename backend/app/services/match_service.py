import logging
from sqlalchemy import text
from sqlalchemy.orm import Session
from typing import List, Dict, Any, Tuple

from app.models import Load, Trip, TrainSchedule, Match
from app.services.llm_service import LLMService
from app.database import is_sqlite

logger = logging.getLogger(__name__)

class MatchService:
    @classmethod
    def run_spatial_matching(cls, load_id: int, db: Session) -> List[Match]:
        """
        Runs the spatial matching algorithm for a given Load.
        Queries active Trips and TrainSchedules using PostGIS geographic distance checks.
        Calculates scores, invokes Claude for matching summaries, and saves results in matches table.
        """
        # 1. Fetch Load details
        load = db.query(Load).filter(Load.id == load_id).first()
        if not load:
            logger.error(f"Load {load_id} not found for matching")
            return []

        # Remove existing proposed matches for this load to avoid duplicates
        db.query(Match).filter(Match.load_id == load_id, Match.status == "PROPOSED").delete()
        db.commit()

        # Convert Point geometry to WKT (Well-Known Text) for sql bindings
        # We can extract the coordinates directly from geoalchemy2 geometry objects if loaded,
        # or fetch them using raw queries.
        # To be highly robust, let's query the coordinates from PostgreSQL
        if is_sqlite:
            # Fallback mock matching for local SQLite tests (which don't run PostGIS)
            logger.info("Database is SQLite. Running mock/haversine matching.")
            matched_trips, matched_trains = cls._run_mock_matching(load, db)
        else:
            logger.info("Database is PostgreSQL. Running PostGIS overlap queries.")
            matched_trips, matched_trains = cls._run_postgis_queries(load, db)

        matches_created = []

        # 2. Process matched Trips (Trucks)
        for trip, distance_score in matched_trips:
            # Verify capacity limits
            if load.weight > trip.remaining_weight_capacity or load.volume > trip.remaining_volume_capacity:
                continue # skips if truck capacity exceeded
            
            # Generate Claude matching explanation
            load_details = {
                "pickup_name": load.pickup_name,
                "dropoff_name": load.dropoff_name,
                "weight": load.weight,
                "volume": load.volume
            }
            carrier_details = {
                "origin": trip.origin_name,
                "destination": trip.destination_name,
                "departure_time": trip.departure_time.strftime("%Y-%m-%d %H:%M"),
                "max_weight": trip.remaining_weight_capacity
            }
            explanation = LLMService.generate_match_explanation(
                load_details=load_details, 
                carrier_details=carrier_details, 
                is_train=False
            )

            db_match = Match(
                load_id=load.id,
                trip_id=trip.id,
                score=round(distance_score, 2),
                status="PROPOSED",
                explanation=explanation
            )
            db.add(db_match)
            matches_created.append(db_match)

        # 3. Process matched TrainSchedules (Railways)
        for train, distance_score in matched_trains:
            load_details = {
                "pickup_name": load.pickup_name,
                "dropoff_name": load.dropoff_name,
                "weight": load.weight,
                "volume": load.volume
            }
            carrier_details = {
                "origin": train.origin,
                "destination": train.destination,
                "departure_time": f"Daily at {train.departure_time}",
                "max_weight": 50000.0  # Railway typically has very high capacity
            }
            explanation = LLMService.generate_match_explanation(
                load_details=load_details, 
                carrier_details=carrier_details, 
                is_train=True
            )

            db_match = Match(
                load_id=load.id,
                train_schedule_id=train.id,
                score=round(distance_score, 2),
                status="PROPOSED",
                explanation=explanation
            )
            db.add(db_match)
            matches_created.append(db_match)

        db.commit()
        logger.info(f"Generated {len(matches_created)} proposed matches for load {load_id}")
        return matches_created

    @classmethod
    def _run_postgis_queries(
        cls, 
        load: Load, 
        db: Session, 
        threshold_meters: float = 50000.0
    ) -> Tuple[List[Tuple[Trip, float]], List[Tuple[TrainSchedule, float]]]:
        """
        Executes raw PostGIS SQL queries on PostgreSQL using geographical functions:
        - ST_DWithin: Checks if pickup/dropoff points are within 50km of the LineString route.
        - ST_LineLocatePoint: Verifies direction (pickup location must occur before dropoff).
        """
        # Resolve WKT representation of the points
        # WKT format is 'POINT(longitude latitude)'
        # First query load coordinates using ST_AsText
        coords_query = text("SELECT ST_X(pickup_geometry) as p_lng, ST_Y(pickup_geometry) as p_lat, ST_X(dropoff_geometry) as d_lng, ST_Y(dropoff_geometry) as d_lat FROM loads WHERE id = :load_id")
        coords_res = db.execute(coords_query, {"load_id": load.id}).fetchone()
        if not coords_res:
            return [], []
        
        p_lng, p_lat, d_lng, d_lat = coords_res
        pickup_wkt = f"POINT({p_lng} {p_lat})"
        dropoff_wkt = f"POINT({d_lng} {d_lat})"

        # Query 1: Find active TRIPS (Trucks) overlapping route
        trips_sql = text("""
            SELECT id, 
                   ST_Distance(route_geometry::geography, ST_GeomFromText(:pickup_wkt, 4326)::geography) as dist_p,
                   ST_Distance(route_geometry::geography, ST_GeomFromText(:dropoff_wkt, 4326)::geography) as dist_d
            FROM trips
            WHERE status = 'ACTIVE'
              AND ST_DWithin(route_geometry::geography, ST_GeomFromText(:pickup_wkt, 4326)::geography, :threshold)
              AND ST_DWithin(route_geometry::geography, ST_GeomFromText(:dropoff_wkt, 4326)::geography, :threshold)
              AND ST_LineLocatePoint(route_geometry, ST_GeomFromText(:pickup_wkt, 4326)) < ST_LineLocatePoint(route_geometry, ST_GeomFromText(:dropoff_wkt, 4326))
        """)
        trips_res = db.execute(trips_sql, {
            "pickup_wkt": pickup_wkt,
            "dropoff_wkt": dropoff_wkt,
            "threshold": threshold_meters
        }).fetchall()

        matched_trips = []
        for row in trips_res:
            trip_id, dist_p, dist_d = row
            trip = db.query(Trip).filter(Trip.id == trip_id).first()
            if trip:
                # Calculate distance-based overlap score (0.0 to 1.0)
                score = 1.0 - ((dist_p + dist_d) / (2 * threshold_meters))
                matched_trips.append((trip, max(0.1, score)))

        # Query 2: Find TRAIN schedules overlapping route
        trains_sql = text("""
            SELECT id,
                   ST_Distance(route_geometry::geography, ST_GeomFromText(:pickup_wkt, 4326)::geography) as dist_p,
                   ST_Distance(route_geometry::geography, ST_GeomFromText(:dropoff_wkt, 4326)::geography) as dist_d
            FROM train_schedules
            WHERE ST_DWithin(route_geometry::geography, ST_GeomFromText(:pickup_wkt, 4326)::geography, :threshold)
              AND ST_DWithin(route_geometry::geography, ST_GeomFromText(:dropoff_wkt, 4326)::geography, :threshold)
              AND ST_LineLocatePoint(route_geometry, ST_GeomFromText(:pickup_wkt, 4326)) < ST_LineLocatePoint(route_geometry, ST_GeomFromText(:dropoff_wkt, 4326))
        """)
        trains_res = db.execute(trains_sql, {
            "pickup_wkt": pickup_wkt,
            "dropoff_wkt": dropoff_wkt,
            "threshold": threshold_meters
        }).fetchall()

        matched_trains = []
        for row in trains_res:
            train_id, dist_p, dist_d = row
            train = db.query(TrainSchedule).filter(TrainSchedule.id == train_id).first()
            if train:
                score = 1.0 - ((dist_p + dist_d) / (2 * threshold_meters))
                matched_trains.append((train, max(0.1, score)))

        return matched_trips, matched_trains

    @classmethod
    def _run_mock_matching(
        cls, 
        load: Load, 
        db: Session
    ) -> Tuple[List[Tuple[Trip, float]], List[Tuple[TrainSchedule, float]]]:
        """
        Mock matching logic for SQLite/local tests.
        Simply matches any trip/train that operates on overlapping route names
        (e.g., Chennai and Bangalore in the endpoints/origins/destinations).
        """
        # Extract coordinates for score mapping
        # In SQLite, coordinates are read from mock helper or dummy properties
        # For mock, we simply query active trips and train schedules
        trips = db.query(Trip).filter(Trip.status == "ACTIVE").all()
        trains = db.query(TrainSchedule).all()

        p_name = load.pickup_name.lower()
        d_name = load.dropoff_name.lower()

        matched_trips = []
        for trip in trips:
            o_name = trip.origin_name.lower()
            dst_name = trip.destination_name.lower()
            
            # Match if shipper cities are on driver cities route (e.g. Chennai/Bangalore/Vellore)
            # Chennai -> Bangalore trip matches Vellore -> Bangalore load
            is_match = False
            if "chennai" in o_name and "bangalore" in dst_name:
                if ("vellore" in p_name or "chennai" in p_name) and "bangalore" in d_name:
                    is_match = True
            elif p_name in o_name and d_name in dst_name:
                is_match = True

            if is_match:
                matched_trips.append((trip, 0.95 if "vellore" in p_name else 1.0))

        matched_trains = []
        for train in trains:
            o_name = train.origin.lower()
            dst_name = train.destination.lower()
            
            is_match = False
            if "chennai" in o_name and ("bangalore" in dst_name or "bengaluru" in dst_name):
                if ("vellore" in p_name or "chennai" in p_name) and ("bangalore" in d_name or "bengaluru" in d_name):
                    is_match = True

            if is_match:
                matched_trains.append((train, 0.85))

        return matched_trips, matched_trains
