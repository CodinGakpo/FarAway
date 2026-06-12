import httpx

class GoogleMapsClient:
    BASE_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"

    def __init__(self, api_key: str):
        self.api_key = api_key

    async def get_route_with_stops(
        self, origin: tuple, stops: list[tuple], destination: tuple
    ) -> tuple[float, float]:  # (distance_km, duration_min)
        waypoints = [
            {"location": {"latLng": {"latitude": lat, "longitude": lng}}}
            for lat, lng in stops
        ]
        payload = {
            "origin": {"location": {"latLng": {"latitude": origin[0], "longitude": origin[1]}}},
            "destination": {"location": {"latLng": {"latitude": destination[0], "longitude": destination[1]}}},
            "intermediates": waypoints,
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
        }
        headers = {
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-FieldMask": "routes.distanceMeters,routes.duration",
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            r = await client.post(self.BASE_URL, json=payload, headers=headers)
            r.raise_for_status()
            data = r.json()
        route = data["routes"][0]
        distance_km = route["distanceMeters"] / 1000.0
        duration_min = int(route["duration"].rstrip("s")) / 60.0
        return distance_km, duration_min
