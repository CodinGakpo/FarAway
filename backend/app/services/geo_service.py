import httpx
import logging
from typing import List, Tuple, Dict, Any, Optional
from app.config import GOOGLE_MAPS_API_KEY

logger = logging.getLogger(__name__)

# Coordinates mapping for realistic mock routes
CITY_COORDINATES: Dict[str, Tuple[float, float]] = {
    "chennai": (13.0827, 80.2707),
    "vellore": (12.9165, 79.1325),
    "krishnagiri": (12.5186, 78.2138),
    "hosur": (12.7409, 77.8253),
    "bangalore": (12.9716, 77.5946),
    "coimbatore": (11.0168, 76.9558),
    "madurai": (9.9252, 78.1198),
    "trichy": (10.7905, 78.7047),
    "salem": (11.6643, 78.1460),
    "delhi": (28.6139, 77.2090),
    "dehradun": (30.3165, 78.0322),
}

class GeoService:
    @staticmethod
    def get_city_coords(city_name: str) -> Tuple[float, float]:
        """
        Helper to resolve coordinates from city names (fallback lookup).
        Returns (lat, lng).
        """
        name = city_name.lower().split(',')[0].strip()
        return CITY_COORDINATES.get(name, (12.9716, 77.5946)) # default to Bangalore

    @classmethod
    def get_route_polyline(cls, origin: str, destination: str) -> Tuple[List[List[float]], float]:
        """
        Computes route polyline (list of [lng, lat] for GeoJSON/PostGIS) and distance (in km).
        If Google Maps API key is configured, calls Google Maps Routes API.
        Otherwise, falls back to realistic OSRM / pre-coded corridor paths.
        """
        o_clean = origin.lower().strip()
        d_clean = destination.lower().strip()

        # Check if Google Maps API Key is available
        if GOOGLE_MAPS_API_KEY:
            try:
                url = "https://routes.googleapis.com/directions/v2:computeRoutes"
                headers = {
                    "Content-Type": "application/json",
                    "X-Goog-Api-Key": GOOGLE_MAPS_API_KEY,
                    "X-Goog-FieldMask": "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline"
                }
                body = {
                    "origin": {"address": origin},
                    "destination": {"address": destination},
                    "travelMode": "DRIVE",
                    "routingPreference": "TRAFFIC_AWARE"
                }
                response = httpx.post(url, json=body, headers=headers, timeout=5.0)
                if response.status_code == 200:
                    data = response.json()
                    if "routes" in data and len(data["routes"]) > 0:
                        route = data["routes"][0]
                        distance_km = float(route.get("distanceMeters", 150000)) / 1000.0
                        encoded_polyline = route["polyline"]["encodedPolyline"]
                        # Decode polyline into coords
                        coords = cls._decode_polyline(encoded_polyline)
                        return coords, distance_km
            except Exception as e:
                logger.error(f"Google Maps API failed: {str(e)}. Falling back to mock/OSRM.")

        # OSRM Fallback (OpenStreetMap public API)
        o_lat, o_lng = cls.get_city_coords(origin)
        d_lat, d_lng = cls.get_city_coords(destination)
        try:
            osrm_url = f"https://router.project-osrm.org/route/v1/driving/{o_lng},{o_lat};{d_lng},{d_lat}?overview=full&geometries=geojson"
            response = httpx.get(osrm_url, timeout=5.0)
            if response.status_code == 200:
                data = response.json()
                if "routes" in data and len(data["routes"]) > 0:
                    route = data["routes"][0]
                    distance_km = float(route.get("distance", 150000)) / 1000.0
                    # OSRM returns coordinates as [lng, lat]
                    coords = route["geometry"]["coordinates"]
                    return coords, distance_km
        except Exception as e:
            logger.error(f"OSRM API call failed: {str(e)}. Using internal corridor mock.")

        # Hardcoded realistic path mock (Chennai -> Bangalore corridor)
        # Returns [lng, lat] points
        if "chennai" in o_clean and "bangalore" in d_clean:
            route = [
                [80.2707, 13.0827], # Chennai
                [79.1325, 12.9165], # Vellore
                [78.2138, 12.5186], # Krishnagiri
                [77.8253, 12.7409], # Hosur
                [77.5946, 12.9716]  # Bangalore
            ]
            return route, 350.0

        if "bangalore" in o_clean and "chennai" in d_clean:
            route = [
                [77.5946, 12.9716], # Bangalore
                [77.8253, 12.7409], # Hosur
                [78.2138, 12.5186], # Krishnagiri
                [79.1325, 12.9165], # Vellore
                [80.2707, 13.0827]  # Chennai
            ]
            return route, 350.0

        # General straight line fallback
        route = [
            [o_lng, o_lat],
            [(o_lng + d_lng)/2.0, (o_lat + d_lat)/2.0],
            [d_lng, d_lat]
        ]
        # Haversine distance estimate
        import math
        rad = math.pi / 180.0
        dlat = (d_lat - o_lat) * rad
        dlng = (d_lng - o_lng) * rad
        a = math.sin(dlat/2)**2 + math.cos(o_lat*rad) * math.cos(d_lat*rad) * math.sin(dlng/2)**2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
        distance_km = 6371 * c
        return route, distance_km

    @staticmethod
    def _decode_polyline(polyline_str: str) -> List[List[float]]:
        """
        Decodes a Google Maps encoded polyline string into list of [lng, lat] points.
        """
        index, lat, lng = 0, 0, 0
        coordinates = []
        changes = {'latitude': 0, 'longitude': 0}

        while index < len(polyline_str):
            for unit in ['latitude', 'longitude']:
                shift, result = 0, 0
                while True:
                    byte = ord(polyline_str[index]) - 63
                    index += 1
                    result |= (byte & 0x1f) << shift
                    shift += 5
                    if not (byte & 0x20):
                        break
                if (result & 1):
                    changes[unit] = ~(result >> 1)
                else:
                    changes[unit] = (result >> 1)

            lat += changes['latitude']
            lng += changes['longitude']
            # Output coordinates as [lng, lat] for PostGIS LineString compliance
            coordinates.append([lng / 100000.0, lat / 100000.0])

        return coordinates
