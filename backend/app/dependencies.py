from functools import lru_cache
from app.db.client import Database
from app.services.route_service import RouteService
from app.services.capacity_service import CapacityService
from app.services.pricing_service import PricingService
from app.services.maps.gmaps_client import GoogleMapsClient
from app.services.maps.osrm_client import OSRMClient
from app.config import GOOGLE_MAPS_API_KEY

@lru_cache()
def get_db() -> Database:
    return Database()

def get_route_service() -> RouteService:
    db = get_db()
    maps = GoogleMapsClient(api_key=GOOGLE_MAPS_API_KEY)
    osrm = OSRMClient()
    return RouteService(db, maps, osrm)

def get_capacity_service() -> CapacityService:
    return CapacityService(get_db())

def get_pricing_service() -> PricingService:
    return PricingService(get_db())
