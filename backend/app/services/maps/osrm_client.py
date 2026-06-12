import httpx

class OSRMClient:
    """Fallback router using public OSRM (or self-hosted)."""
    BASE_URL = "http://router.project-osrm.org/route/v1/driving"

    async def get_route_with_stops(
        self, origin: tuple, stops: list[tuple], destination: tuple
    ) -> tuple[float, float]:
        coords = [origin] + stops + [destination]
        coord_str = ";".join(f"{lng},{lat}" for lat, lng in coords)
        async with httpx.AsyncClient(timeout=15.0) as client:
            r = await client.get(f"{self.BASE_URL}/{coord_str}?overview=false")
            r.raise_for_status()
            data = r.json()
        route = data["routes"][0]
        return route["distance"] / 1000.0, route["duration"] / 60.0
