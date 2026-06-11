import logging
import math
import re
from typing import List, Dict, Any, Tuple, Set, Optional
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.database import is_sqlite
from app.models import Trip, Load, Match
from app.services.geo_service import GeoService

logger = logging.getLogger(__name__)

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Computes the Haversine distance in kilometers between two GPS points.
    """
    R = 6371.0  # Earth radius in kilometers
    
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    
    a = (math.sin(dlat / 2) ** 2 + 
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * 
         math.sin(dlon / 2) ** 2)
    
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def parse_point_wkt(wkt_str: str) -> Tuple[float, float]:
    """
    Parses a POINT WKT string, e.g. "SRID=4326;POINT(lng lat)" or "POINT(lng lat)".
    Returns (latitude, longitude) as floats.
    """
    if not wkt_str:
        return 0.0, 0.0
    wkt_str = str(wkt_str)
    match = re.search(r'POINT\s*\(\s*([-\d.]+)\s+([-\d.]+)\s*\)', wkt_str, re.IGNORECASE)
    if match:
        lng = float(match.group(1))
        lat = float(match.group(2))
        return lat, lng
    return 0.0, 0.0

def parse_linestring_wkt(wkt_str: str) -> List[List[float]]:
    """
    Parses a LINESTRING WKT string, e.g. "SRID=4326;LINESTRING(lng1 lat1, lng2 lat2, ...)".
    Returns a list of [lng, lat] coordinate pairs.
    """
    if not wkt_str:
        return []
    wkt_str = str(wkt_str)
    match = re.search(r'LINESTRING\s*\(([^)]+)\)', wkt_str, re.IGNORECASE)
    if match:
        points_str = match.group(1)
        coords = []
        for pt in points_str.split(','):
            parts = pt.strip().split()
            if len(parts) >= 2:
                coords.append([float(parts[0]), float(parts[1])])
        return coords
    return []


class OptimizationService:
    @staticmethod
    def get_load_coords(load: Load, db: Session) -> Tuple[float, float, float, float]:
        """
        Retrieves the (pickup_lat, pickup_lng, dropoff_lat, dropoff_lng) for a Load,
        supporting both PostGIS on Postgres and WKT strings on SQLite.
        """
        if is_sqlite:
            p_lat, p_lng = parse_point_wkt(load.pickup_geometry)
            d_lat, d_lng = parse_point_wkt(load.dropoff_geometry)
            if p_lat == 0.0 and p_lng == 0.0:
                p_lat, p_lng = 12.9165, 79.1325
            if d_lat == 0.0 and d_lng == 0.0:
                d_lat, d_lng = 12.9716, 77.5946
            return p_lat, p_lng, d_lat, d_lng
        else:
            query = text("""
                SELECT ST_Y(pickup_geometry) as p_lat, 
                       ST_X(pickup_geometry) as p_lng, 
                       ST_Y(dropoff_geometry) as d_lat, 
                       ST_X(dropoff_geometry) as d_lng 
                FROM loads WHERE id = :id
            """)
            res = db.execute(query, {"id": load.id}).fetchone()
            if res:
                return res[0], res[1], res[2], res[3]
            return 0.0, 0.0, 0.0, 0.0

    @staticmethod
    def get_trip_coords(trip: Trip, db: Session) -> List[List[float]]:
        """
        Retrieves route coordinates as a list of [lng, lat] for a Trip.
        """
        if is_sqlite:
            if trip.route_geometry:
                coords = parse_linestring_wkt(trip.route_geometry)
                if coords:
                    return coords
            # Fallback to GeoService polyline helper
            coords, _ = GeoService.get_route_polyline(trip.origin_name, trip.destination_name)
            return coords
        else:
            query = text("SELECT ST_AsGeoJSON(route_geometry) FROM trips WHERE id = :id")
            geom_json = db.execute(query, {"id": trip.id}).scalar()
            if geom_json:
                try:
                    import json
                    geom = json.loads(geom_json)
                    coords = geom.get("coordinates")
                    if coords:
                        return coords
                except Exception:
                    pass
            # Fallback
            coords, _ = GeoService.get_route_polyline(trip.origin_name, trip.destination_name)
            return coords

    @classmethod
    def optimize_trip(cls, trip_id: int, db: Session, cost_per_km: float = 15.0) -> Dict[str, Any]:
        """
        AI Agent Trip & Delivery Path Optimizer.
        Finds the most profitable combination of proposed packages for a trip,
        solves the optimal delivery sequence under weight & volume constraints,
        and generates a detailed reasoning trace.
        """
        trace_steps = []
        trace_steps.append("🏁 Starting AI Agent Trip Optimization Process...")
        trace_steps.append(f"🚚 Target Trip ID: {trip_id} (Cost Parameter: ₹{cost_per_km:.2f}/km)")

        # 1. Fetch Trip details
        trip = db.query(Trip).filter(Trip.id == trip_id).first()
        if not trip:
            raise ValueError(f"Trip with ID {trip_id} not found")

        # Get trip coordinates
        route_coords = cls.get_trip_coords(trip, db)
        if not route_coords or len(route_coords) < 2:
            # Fallback direct line origin/dest
            orig_lat, orig_lng = GeoService.get_city_coords(trip.origin_name)
            dest_lat, dest_lng = GeoService.get_city_coords(trip.destination_name)
            route_coords = [[orig_lng, orig_lat], [dest_lng, dest_lat]]

        # Calculate base distance along the truck's planned route
        base_distance = 0.0
        for i in range(len(route_coords) - 1):
            base_distance += haversine_distance(
                route_coords[i][1], route_coords[i][0],
                route_coords[i+1][1], route_coords[i+1][0]
            )

        start_lat, start_lng = route_coords[0][1], route_coords[0][0]
        end_lat, end_lng = route_coords[-1][1], route_coords[-1][0]

        trace_steps.append(f"📍 Trip Route: {trip.origin_name} ➡️ {trip.destination_name}")
        trace_steps.append(f"🛣️ Base Route Distance: {base_distance:.2f} km")
        trace_steps.append(f"📦 Trip Baseline Capacities: Remaining Weight={trip.remaining_weight_capacity}kg, Remaining Volume={trip.remaining_volume_capacity} cu ft")

        # 2. Query Candidate Loads (proposed matches for this trip)
        matches = db.query(Match).filter(Match.trip_id == trip.id, Match.status == "PROPOSED").all()
        candidate_loads = []
        rejected_loads_details = []

        for m in matches:
            load = m.load
            if not load:
                continue
            
            p_lat, p_lng, d_lat, d_lng = cls.get_load_coords(load, db)
            
            # Simple capacity preprocessing
            if load.weight > trip.remaining_weight_capacity:
                rejected_loads_details.append({
                    "load_id": load.id,
                    "pickup_name": load.pickup_name,
                    "dropoff_name": load.dropoff_name,
                    "weight": load.weight,
                    "volume": load.volume,
                    "price": m.score * 2000.0, # Estimate price if missing, or use DB price
                    "reason": f"Exceeds remaining weight capacity (Requires: {load.weight}kg, Available: {trip.remaining_weight_capacity}kg)"
                })
                trace_steps.append(f"⚠️ Pre-rejected Load ID {load.id} ({load.pickup_name} -> {load.dropoff_name}) because it exceeds remaining weight capacity.")
                continue
                
            if load.volume > trip.remaining_volume_capacity:
                rejected_loads_details.append({
                    "load_id": load.id,
                    "pickup_name": load.pickup_name,
                    "dropoff_name": load.dropoff_name,
                    "weight": load.weight,
                    "volume": load.volume,
                    "price": m.score * 2000.0,
                    "reason": f"Exceeds remaining volume capacity (Requires: {load.volume} cu ft, Available: {trip.remaining_volume_capacity} cu ft)"
                })
                trace_steps.append(f"⚠️ Pre-rejected Load ID {load.id} ({load.pickup_name} -> {load.dropoff_name}) because it exceeds remaining volume capacity.")
                continue

            # Determine price. If there's an agent price or match score, let's extract it
            # We can query matches table or calculate using agent calculation
            # To be robust, calculate price using agent's standard algorithm
            from app.services.agent_service import FreightShareAgentService
            price, _ = FreightShareAgentService.calculate_price(
                load.weight, load.volume, "general", load.pickup_name, load.dropoff_name
            )

            candidate_loads.append({
                "id": load.id,
                "pickup_name": load.pickup_name,
                "dropoff_name": load.dropoff_name,
                "pickup_lat": p_lat,
                "pickup_lng": p_lng,
                "dropoff_lat": d_lat,
                "dropoff_lng": d_lng,
                "weight": load.weight,
                "volume": load.volume,
                "price": price
            })

        trace_steps.append(f"🔍 Found {len(candidate_loads)} candidate packages for cost-optimization evaluation.")

        # 3. Solver: Backtracking search to evaluate subsets of candidate loads
        best_profit = 0.0
        best_path_distance = base_distance
        # list of tuples: (stop_name, lat, lng, action_type, load_id_or_none)
        best_stops_sequence = [
            (trip.origin_name, start_lat, start_lng, "start", None),
            (trip.destination_name, end_lat, end_lng, "destination", None)
        ]
        best_subset_ids = []

        # Iterate through all subsets of candidate loads
        # Using binary representation for subsets: 0 to 2^n - 1
        n_candidates = len(candidate_loads)
        total_subsets = 1 << n_candidates
        
        trace_steps.append(f"⚡ Running combinatorial path optimization across {total_subsets} load combinations...")

        for s_idx in range(total_subsets):
            subset = []
            subset_revenue = 0.0
            for i in range(n_candidates):
                if (s_idx >> i) & 1:
                    subset.append(candidate_loads[i])
                    subset_revenue += candidate_loads[i]["price"]

            if not subset:
                continue

            # Find the optimal route sequence for this subset
            opt_dist, opt_path = cls._solve_tsp_constrained(
                start_lat, start_lng, trip.origin_name,
                end_lat, end_lng, trip.destination_name,
                subset,
                trip.remaining_weight_capacity,
                trip.remaining_volume_capacity
            )

            if opt_dist is not None:
                # Profit = Revenue - (deviation_distance * cost_per_km)
                deviation = opt_dist - base_distance
                extra_cost = max(0.0, deviation) * cost_per_km
                profit = subset_revenue - extra_cost
                
                if profit > best_profit:
                    best_profit = profit
                    best_path_distance = opt_dist
                    best_stops_sequence = opt_path
                    best_subset_ids = [load["id"] for load in subset]

        # 4. Generate rejected load list based on the chosen optimal subset
        selected_set = set(best_subset_ids)
        for load in candidate_loads:
            if load["id"] not in selected_set:
                rejected_loads_details.append({
                    "load_id": load["id"],
                    "pickup_name": load["pickup_name"],
                    "dropoff_name": load["dropoff_name"],
                    "weight": load["weight"],
                    "volume": load["volume"],
                    "price": load["price"],
                    "reason": "Unprofitable route deviation (deviation costs exceed pickup revenue contribution)"
                })
                trace_steps.append(f"❌ Rejected Load ID {load['id']} ({load['pickup_name']} -> {load['dropoff_name']}) as unprofitable (deviation penalty too high).")

        # 5. Format optimized path with capacity tracker
        optimized_stops = []
        rem_weight = trip.remaining_weight_capacity
        rem_volume = trip.remaining_volume_capacity

        for stop_type, lat, lng, name, load_dict in best_stops_sequence:
            if stop_type == "pickup":
                rem_weight -= load_dict["weight"]
                rem_volume -= load_dict["volume"]
                optimized_stops.append({
                    "name": name,
                    "lat": lat,
                    "lng": lng,
                    "action": "pickup",
                    "load_id": load_dict["id"],
                    "remaining_weight": round(rem_weight, 2),
                    "remaining_volume": round(rem_volume, 2)
                })
            elif stop_type == "dropoff":
                rem_weight += load_dict["weight"]
                rem_volume += load_dict["volume"]
                optimized_stops.append({
                    "name": name,
                    "lat": lat,
                    "lng": lng,
                    "action": "dropoff",
                    "load_id": load_dict["id"],
                    "remaining_weight": round(rem_weight, 2),
                    "remaining_volume": round(rem_volume, 2)
                })
            elif stop_type == "start":
                optimized_stops.append({
                    "name": name,
                    "lat": lat,
                    "lng": lng,
                    "action": "start",
                    "load_id": None,
                    "remaining_weight": round(rem_weight, 2),
                    "remaining_volume": round(rem_volume, 2)
                })
            elif stop_type == "destination":
                optimized_stops.append({
                    "name": name,
                    "lat": lat,
                    "lng": lng,
                    "action": "destination",
                    "load_id": None,
                    "remaining_weight": round(rem_weight, 2),
                    "remaining_volume": round(rem_volume, 2)
                })

        # Calculations
        deviation_distance = max(0.0, best_path_distance - base_distance)
        extra_fuel_cost = deviation_distance * cost_per_km
        gross_revenue = sum([l["price"] for l in candidate_loads if l["id"] in selected_set])
        net_profit = gross_revenue - extra_fuel_cost

        # 6. Build the Natural Language Trace summary
        trace_steps.append("\n✅ Optimization Completed.")
        trace_steps.append(f"📊 Financial Summary:")
        trace_steps.append(f"  - Base Distance: {base_distance:.2f} km")
        trace_steps.append(f"  - Optimized Distance: {best_path_distance:.2f} km")
        trace_steps.append(f"  - Route Deviation: +{deviation_distance:.2f} km")
        trace_steps.append(f"  - Extra Cost: ₹{extra_fuel_cost:.2f}")
        trace_steps.append(f"  - Gross Revenue: ₹{gross_revenue:.2f}")
        trace_steps.append(f"  - Net Profit: ₹{net_profit:.2f}")

        if best_subset_ids:
            trace_steps.append(f"\n🤖 [Agent Decision]: Pick up loads: {best_subset_ids}. This minimizes total cost and maximizes payout profit.")
            trace_steps.append(f"Logical Path Sequence: " + " ➡️ ".join([s["name"] + f" ({s['action'].upper()})" for s in optimized_stops]))
        else:
            trace_steps.append("\n🤖 [Agent Decision]: No candidate loads are worth picking up. The deviation costs exceed potential payouts. Driver should proceed direct to destination.")

        full_trace = "\n".join(trace_steps)

        return {
            "recommended_loads": best_subset_ids,
            "rejected_loads": rejected_loads_details,
            "optimized_path": optimized_stops,
            "base_distance_km": round(base_distance, 2),
            "optimized_distance_km": round(best_path_distance, 2),
            "deviation_distance_km": round(deviation_distance, 2),
            "extra_fuel_cost": round(extra_fuel_cost, 2),
            "gross_revenue": round(gross_revenue, 2),
            "net_profit": round(net_profit, 2),
            "trace": full_trace
        }

    @classmethod
    def _solve_tsp_constrained(
        cls,
        start_lat: float, start_lng: float, start_name: str,
        end_lat: float, end_lng: float, end_name: str,
        subset_loads: List[Dict[str, Any]],
        max_weight: float,
        max_volume: float
    ) -> Tuple[Optional[float], Optional[List[Tuple[str, float, float, str, Any]]]]:
        """
        Finds the minimum distance sequence of pickups and dropoffs for a subset of loads.
        Enforces precedence (pickup before dropoff) and truck capacity limits.
        """
        best_dist = float('inf')
        best_seq = None

        # DFS Backtracking
        # path is list of (type, lat, lng, name, load_dict)
        def backtrack(
            curr_lat: float, curr_lng: float,
            curr_path: List[Tuple[str, float, float, str, Any]],
            curr_wt: float, curr_vol: float,
            picked_indices: Set[int],
            dropped_indices: Set[int],
            curr_dist: float
        ):
            nonlocal best_dist, best_seq
            
            # Pruning
            if curr_dist >= best_dist:
                return

            # Base case: all loads picked up and dropped off
            if len(dropped_indices) == len(subset_loads):
                # Distance to final destination
                d = haversine_distance(curr_lat, curr_lng, end_lat, end_lng)
                total_d = curr_dist + d
                if total_d < best_dist:
                    best_dist = total_d
                    # Build complete path including destination
                    best_seq = list(curr_path) + [("destination", end_lat, end_lng, end_name, None)]
                return

            # Branch: Pickups & Dropoffs
            for idx, load in enumerate(subset_loads):
                # Try Pickup
                if idx not in picked_indices:
                    if curr_wt + load["weight"] <= max_weight and curr_vol + load["volume"] <= max_volume:
                        p_dist = haversine_distance(curr_lat, curr_lng, load["pickup_lat"], load["pickup_lng"])
                        picked_indices.add(idx)
                        curr_path.append(("pickup", load["pickup_lat"], load["pickup_lng"], load["pickup_name"], load))
                        
                        backtrack(
                            load["pickup_lat"], load["pickup_lng"],
                            curr_path,
                            curr_wt + load["weight"], curr_vol + load["volume"],
                            picked_indices, dropped_indices,
                            curr_dist + p_dist
                        )
                        
                        curr_path.pop()
                        picked_indices.remove(idx)

                # Try Dropoff
                if idx in picked_indices and idx not in dropped_indices:
                    d_dist = haversine_distance(curr_lat, curr_lng, load["dropoff_lat"], load["dropoff_lng"])
                    dropped_indices.add(idx)
                    curr_path.append(("dropoff", load["dropoff_lat"], load["dropoff_lng"], load["dropoff_name"], load))
                    
                    backtrack(
                        load["dropoff_lat"], load["dropoff_lng"],
                        curr_path,
                        curr_wt - load["weight"], curr_vol - load["volume"],
                        picked_indices, dropped_indices,
                        curr_dist + d_dist
                    )
                    
                    curr_path.pop()
                    dropped_indices.remove(idx)

        # Start recursion
        initial_path = [("start", start_lat, start_lng, start_name, None)]
        backtrack(
            start_lat, start_lng,
            initial_path,
            0.0, 0.0,
            set(), set(),
            0.0
        )

        if best_seq is not None:
            return best_dist, best_seq
        return None, None
