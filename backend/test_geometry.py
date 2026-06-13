import sys
import os
import requests

# Add current path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

BASE_URL = "http://localhost:8000"

def get_token(role="driver"):
    resp = requests.post(f"{BASE_URL}/auth/login", json={
        "id": "test_user_geo",
        "email": "geo@test.com",
        "name": "Geo Test",
        "role": role
    })
    return resp.json()["access_token"]

def create_trip(token, origin, dest):
    resp = requests.post(
        f"{BASE_URL}/trips",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "origin_name": origin,
            "destination_name": dest,
            "date": "2026-06-13",
            "max_weight_capacity": 5000,
            "max_volume_capacity": 200,
            "cost_per_km": 15.0
        }
    )
    return resp.json()["id"]

def eval_shipment(token, trip_id, pickup, dropoff):
    resp = requests.post(
        f"{BASE_URL}/agent/evaluate",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "trip_id": trip_id,
            "pickup_location": pickup,
            "dropoff_location": dropoff,
            "weight": 100,
            "volume": 10,
            "cargo_category": "general"
        }
    )
    if resp.status_code != 200:
        print(f"Error: {resp.text}")
        return False, resp.text
    
    data = resp.json()
    return data["feasible"], data["trace"]

def test_scenarios():
    token = get_token()
    print("Creating Trips...")
    
    # Pre-create trips for tests
    t_kb = create_trip(token, "Katpadi", "Bangalore")
    t_cb = create_trip(token, "Chennai", "Bangalore")
    t_hb = create_trip(token, "Hosur", "Bangalore")
    t_bc = create_trip(token, "Bangalore", "Chennai")

    print("\n--- SHOULD MATCH ---")
    
    print("\n1. Katpadi -> Bangalore | VIT -> ITPL")
    f, t = eval_shipment(token, t_kb, "VIT Vellore", "ITPL Bangalore")
    print(f"Feasible: {f}")
    
    print("\n2. Katpadi -> Bangalore | CMC Vellore -> Whitefield")
    f, t = eval_shipment(token, t_kb, "CMC Vellore", "Whitefield")
    print(f"Feasible: {f}")
    
    print("\n3. Chennai -> Bangalore | Sriperumbudur -> Electronic City")
    f, t = eval_shipment(token, t_cb, "Sriperumbudur", "Electronic City")
    print(f"Feasible: {f}")
    
    print("\n4. Hosur -> Bangalore | Attibele -> Marathahalli")
    f, t = eval_shipment(token, t_hb, "Attibele", "Marathahalli")
    print(f"Feasible: {f}")
    
    print("\n--- SHOULD NOT MATCH ---")
    
    print("\n5. Bangalore -> Chennai | Electronic City -> Vellore (Wrong direction)")
    f, t = eval_shipment(token, t_bc, "Electronic City", "Vellore")
    print(f"Feasible: {f}")
    
    print("\n6. Katpadi -> Bangalore | Mumbai -> Pune (Far outside)")
    f, t = eval_shipment(token, t_kb, "Mumbai", "Pune")
    print(f"Feasible: {f}")

if __name__ == "__main__":
    test_scenarios()
