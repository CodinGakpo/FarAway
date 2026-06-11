import sys
import os

# Override Database URL to SQLite for test running without postgres container
db_file = "./test_freightshare.db"
if os.path.exists(db_file):
    try:
        os.remove(db_file)
        print("🧹 Existing test database file removed for clean state.")
    except Exception as e:
        print(f"⚠️ Could not delete database file: {e}")

os.environ["DATABASE_URL"] = f"sqlite:///{db_file}"

import json
from datetime import datetime, timedelta
from fastapi.testclient import TestClient

# Ensure app directory can be imported
sys.path.append(".")

from app.main import app
from seed_data import seed_database
from app.database import SessionLocal
from app.models import Match, Load

def test_trip_optimization_pipeline():
    # Seed database
    seed_database()

    client = TestClient(app)

    print("\n==============================================")
    print("🔑 Authenticating Users (Dev Mock Login)...")
    
    # Authenticate Driver
    driver_login = client.post("/auth/login", json={
        "id": "driver_arjun",
        "email": "arjun@freightshare.com",
        "role": "driver",
        "name": "Arjun Kumar"
    })
    assert driver_login.status_code == 200
    driver_token = driver_login.json()["access_token"]
    driver_headers = {"Authorization": f"Bearer {driver_token}"}
    print("  - Driver Authenticated successfully.")

    # Authenticate Shipper
    shipper_login = client.post("/auth/login", json={
        "id": "shipper_niranjan",
        "email": "niranjan@freightshare.com",
        "role": "shipper",
        "name": "Niranjan Shippers Ltd"
    })
    assert shipper_login.status_code == 200
    shipper_token = shipper_login.json()["access_token"]
    shipper_headers = {"Authorization": f"Bearer {shipper_token}"}
    print("  - Shipper Authenticated successfully.")

    print("\n==============================================")
    print("🚚 Checking Active Driver Trips...")
    trips_resp = client.get("/trips/?driver_id=driver_arjun", headers=shipper_headers)
    assert trips_resp.status_code == 200
    trips = trips_resp.json()
    assert len(trips) > 0
    trip_id = trips[0]["id"]
    print(f"  - Driver Trip found. ID: {trip_id} ({trips[0]['origin_name']} -> {trips[0]['destination_name']})")

    print("\n==============================================")
    print("📦 Creating Test Cargo Loads...")
    
    # Load 1: Profitable stop along the corridor (Vellore -> Bangalore)
    load1_resp = client.post("/loads/", json={
        "pickup_name": "Vellore",
        "dropoff_name": "Bangalore",
        "pickup_lat": 12.9165,
        "pickup_lng": 79.1325,
        "dropoff_lat": 12.9716,
        "dropoff_lng": 77.5946,
        "weight": 500.0,
        "volume": 12.0
    }, headers=shipper_headers)
    assert load1_resp.status_code == 201
    load1_id = load1_resp.json()["id"]
    print(f"  - Load 1 Created: ID {load1_id} (Vellore -> Bangalore)")

    # Load 2: Another profitable stop (Hosur -> Bangalore), but not matching the direct highway trigger (so unmatched)
    load2_resp = client.post("/loads/", json={
        "pickup_name": "Hosur",
        "dropoff_name": "Bangalore",
        "pickup_lat": 12.7409,
        "pickup_lng": 77.8253,
        "dropoff_lat": 12.9716,
        "dropoff_lng": 77.5946,
        "weight": 300.0,
        "volume": 8.0
    }, headers=shipper_headers)
    assert load2_resp.status_code == 201
    load2_id = load2_resp.json()["id"]
    print(f"  - Load 2 Created: ID {load2_id} (Hosur -> Bangalore)")

    # Load 3: Unprofitable load due to location/direction (Coimbatore -> Chennai)
    # This represents high deviation and is not worth picking up
    load3_resp = client.post("/loads/", json={
        "pickup_name": "Coimbatore",
        "dropoff_name": "Chennai",
        "pickup_lat": 11.0168,
        "pickup_lng": 76.9558,
        "dropoff_lat": 13.0827,
        "dropoff_lng": 80.2707,
        "weight": 1000.0,
        "volume": 25.0
    }, headers=shipper_headers)
    assert load3_resp.status_code == 201
    load3_id = load3_resp.json()["id"]
    print(f"  - Load 3 Created: ID {load3_id} (Coimbatore -> Chennai)")

    # Note: Wait! Spatial match runs automatically during create_load and saves proposed matches.
    # But wait, let's verify if Coimbatore -> Chennai load gets proposed to Chennai -> Bangalore trip.
    # In _run_mock_matching in match_service.py:
    # It only matches if "chennai" in origin and "bangalore" in destination, and pickup/dropoff matches.
    # So Load 3 will NOT be matched as proposed!
    # Let's manually add a mock Match record in the database for Load 3 so we can test that the optimizer
    # evaluates it, sees it as highly unprofitable, and rejects it!
    db = SessionLocal()
    try:
        m3 = Match(
            load_id=load3_id,
            trip_id=trip_id,
            score=0.2, # low score
            status="PROPOSED",
            explanation="Manual mock link to test rejection."
        )
        db.add(m3)
        db.commit()
        print(f"  - Manually linked Load 3 to Trip {trip_id} in MATCHES database for optimization testing.")
    finally:
        db.close()

    print("\n==============================================")
    print("⚡ Triggering AI Agent Trip Optimization...")
    opt_resp = client.post("/agent/optimize-trip", json={
        "trip_id": trip_id,
        "cost_per_km": 12.0
    }, headers=driver_headers)
    
    assert opt_resp.status_code == 200, f"Optimization failed: {opt_resp.text}"
    opt_data = opt_resp.json()

    print("\n📈 OPTIMIZER FINANCIAL ANALYSIS:")
    print(f"  - Base Distance: {opt_data['base_distance_km']} km")
    print(f"  - Optimized Distance: {opt_data['optimized_distance_km']} km")
    print(f"  - Deviation Distance: +{opt_data['deviation_distance_km']} km")
    print(f"  - Extra Fuel Cost: ₹{opt_data['extra_fuel_cost']}")
    print(f"  - Gross Revenue: ₹{opt_data['gross_revenue']}")
    print(f"  - Net Profit: ₹{opt_data['net_profit']}")

    print("\n📋 RECOMMENDATIONS:")
    print(f"  - Recommended Packages: {opt_data['recommended_loads']}")
    
    print("\n❌ REJECTED PACKAGES:")
    for r in opt_data['rejected_loads']:
        print(f"  * Load ID {r['load_id']} ({r['pickup_name']} -> {r['dropoff_name']}) - Reason: {r['reason']}")

    print("\n🗺️ OPTIMIZED ROUTE PATH:")
    for idx, stop in enumerate(opt_data['optimized_path']):
        print(f"  [{idx+1}] {stop['name']} ({stop['action'].upper()}) - Rem Weight Capacity: {stop['remaining_weight']}kg, Rem Volume: {stop['remaining_volume']} cu ft")

    print("\n🤖 === AGENT OPTIMIZATION TRACE ===")
    print(opt_data['trace'])
    print("=================================\n")

    # Assertions
    # Load 1 (ID 3) should be recommended
    assert load1_id in opt_data["recommended_loads"]
    
    # Load 2 (ID 4, Hosur) was never matched, so it shouldn't be recommended
    assert load2_id not in opt_data["recommended_loads"]
    
    # Load 3 (ID 5, Coimbatore) must be rejected because it goes the wrong way (unprofitable)
    assert load3_id not in opt_data["recommended_loads"]
    rejected_ids = [r["load_id"] for r in opt_data["rejected_loads"]]
    assert load3_id in rejected_ids
    
    # The reasons should be populated
    load3_rejection = next(r for r in opt_data["rejected_loads"] if r["load_id"] == load3_id)
    assert "Unprofitable" in load3_rejection["reason"]

    # Verify start and end of optimized path
    assert opt_data["optimized_path"][0]["action"] == "start"
    assert opt_data["optimized_path"][-1]["action"] == "destination"

    print("🎉 ALL TRIP OPTIMIZATION & DELIVERY PATH TESTS PASSED!")

if __name__ == "__main__":
    test_trip_optimization_pipeline()
