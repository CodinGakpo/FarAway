import sys
import json
from fastapi.testclient import TestClient

# Ensure app directory can be imported
sys.path.append(".")

from app.main import app

def test_freightshare_demo_flow():
    client = TestClient(app)

    print("\n==============================================")
    # 1. Root and Health checks
    print("📋 Checking API Health and Root...")
    health_resp = client.get("/health")
    assert health_resp.status_code == 200, f"Health check failed: {health_resp.text}"
    print(f"  - Health Status: {health_resp.json()}")

    root_resp = client.get("/")
    assert root_resp.status_code == 200
    print(f"  - Root response: {root_resp.json()}")

    print("\n==============================================")
    # 2. Driver Registration and Login
    print("👤 Registering Driver...")
    driver_reg_resp = client.post("/auth/register", json={
        "email": "driver@freightshare.com",
        "password": "driverpassword123",
        "role": "driver",
        "name": "Arjun Kumar"
    })
    if driver_reg_resp.status_code == 400 and "already registered" in driver_reg_resp.json().get("detail", ""):
        print("  - Driver already registered. Proceeding to login.")
    else:
        assert driver_reg_resp.status_code == 201, f"Driver reg failed: {driver_reg_resp.text}"
        print(f"  - Driver registered successfully: {driver_reg_resp.json()['email']}")

    print("🔑 Logging in Driver...")
    driver_login_resp = client.post("/auth/login", json={
        "email": "driver@freightshare.com",
        "password": "driverpassword123"
    })
    assert driver_login_resp.status_code == 200, f"Driver login failed: {driver_login_resp.text}"
    driver_token = driver_login_resp.json()["access_token"]
    driver_headers = {"Authorization": f"Bearer {driver_token}"}
    print(f"  - Driver logged in. Token: {driver_token[:15]}...")

    print("\n==============================================")
    # 3. Driver Creates a Trip (Chennai -> Bangalore)
    print("🚚 Creating Driver Trip (Chennai -> Bangalore, Cap: 1000kg, 50 cu ft)...")
    trip_resp = client.post("/trips/", json={
        "origin": "Chennai",
        "destination": "Bangalore",
        "date": "2026-06-25",
        "max_weight_capacity": 1000.0,
        "max_volume_capacity": 50.0
    }, headers=driver_headers)
    assert trip_resp.status_code == 201, f"Trip creation failed: {trip_resp.text}"
    trip_data = trip_resp.json()
    trip_id = trip_data["id"]
    print(f"  - Trip Created successfully! ID: {trip_id}")
    print(f"    Origin: {trip_data['origin']} -> Destination: {trip_data['destination']}")
    print(f"    Capacities: Max Weight={trip_data['max_weight_capacity']}kg, Max Volume={trip_data['max_volume_capacity']} cu ft")

    print("\n==============================================")
    # 4. Customer Registration and Login
    print("👤 Registering Customer...")
    customer_reg_resp = client.post("/auth/register", json={
        "email": "customer@freightshare.com",
        "password": "customerpassword123",
        "role": "customer",
        "name": "Niranjan Vijay"
    })
    if customer_reg_resp.status_code == 400 and "already registered" in customer_reg_resp.json().get("detail", ""):
        print("  - Customer already registered. Proceeding to login.")
    else:
        assert customer_reg_resp.status_code == 201, f"Customer reg failed: {customer_reg_resp.text}"
        print(f"  - Customer registered: {customer_reg_resp.json()['email']}")

    print("🔑 Logging in Customer...")
    customer_login_resp = client.post("/auth/login", json={
        "email": "customer@freightshare.com",
        "password": "customerpassword123"
    })
    assert customer_login_resp.status_code == 200, f"Customer login failed: {customer_login_resp.text}"
    customer_token = customer_login_resp.json()["access_token"]
    customer_headers = {"Authorization": f"Bearer {customer_token}"}
    print(f"  - Customer logged in. Token: {customer_token[:15]}...")

    print("\n==============================================")
    # 5. Customer Submits a Shipment Request (Vellore -> Bangalore, 200kg, 10 cu ft, fragile)
    # This automatically runs the AI Agent during creation and saves as DRAFT.
    print("📦 Creating Shipment Request (Vellore -> Bangalore, 200kg, fragile)...")
    shipment_resp = client.post("/shipments/", json={
        "trip_id": trip_id,
        "pickup_location": "Vellore",
        "dropoff_location": "Bangalore",
        "weight": 200.0,
        "volume": 10.0,
        "cargo_category": "fragile"
    }, headers=customer_headers)
    assert shipment_resp.status_code == 201, f"Shipment creation failed: {shipment_resp.text}"
    shipment_data = shipment_resp.json()
    shipment_id = shipment_data["id"]
    
    print(f"  - Shipment Created in DRAFT state! ID: {shipment_id}")
    print(f"  - Feasibility: {shipment_data['feasibility_status']}")
    print(f"  - AI Calculated Price: ₹{shipment_data['price']:.2f} (Expected: ₹2400.00)")
    
    # Print the AI Agent trace!
    print("\n🤖 === AGENT REASONING TRACE ===")
    print(shipment_data["feasibility_trace"])
    print("=================================\n")
    
    assert shipment_data["feasibility_status"] is True
    assert shipment_data["price"] == 2400.00
    assert shipment_data["status"] == "DRAFT"

    print("\n==============================================")
    # 6. Customer Confirms Booking
    print("💳 Customer Confirms Booking...")
    confirm_resp = client.post(f"/shipments/{shipment_id}/confirm", headers=customer_headers)
    assert confirm_resp.status_code == 200, f"Confirmation failed: {confirm_resp.text}"
    assert confirm_resp.json()["status"] == "PENDING"
    print(f"  - Shipment Status updated to: {confirm_resp.json()['status']}")

    print("\n==============================================")
    # 7. Driver Accepts Shipment and Truck Capacity Decrements
    print("🚚 Driver Accepts Shipment...")
    accept_resp = client.patch(f"/shipments/{shipment_id}/status", json={
        "status": "ACCEPTED"
    }, headers=driver_headers)
    assert accept_resp.status_code == 200, f"Driver accept failed: {accept_resp.text}"
    assert accept_resp.json()["status"] == "ACCEPTED"
    print(f"  - Shipment Status updated to: {accept_resp.json()['status']}")

    # Check remaining capacities on Trip
    print("🔍 Verifying Trip Remaining Capacities...")
    check_trip_resp = client.get(f"/trips/{trip_id}", headers=driver_headers)
    trip_check = check_trip_resp.json()
    print(f"  - Remaining Weight: {trip_check['remaining_weight_capacity']}kg (Expected: 800.0kg)")
    print(f"  - Remaining Volume: {trip_check['remaining_volume_capacity']} cu ft (Expected: 40.0 cu ft)")
    assert trip_check["remaining_weight_capacity"] == 800.0
    assert trip_check["remaining_volume_capacity"] == 40.0

    print("\n==============================================")
    # 8. Driver Progresses Shipment to PICKED_UP
    print("🚚 Driver Updates Shipment to PICKED_UP...")
    pickup_resp = client.patch(f"/shipments/{shipment_id}/status", json={
        "status": "PICKED_UP"
    }, headers=driver_headers)
    assert pickup_resp.status_code == 200, f"Driver pickup failed: {pickup_resp.text}"
    assert pickup_resp.json()["status"] == "PICKED_UP"
    print(f"  - Shipment Status: {pickup_resp.json()['status']}")

    print("\n==============================================")
    # 9. Driver Progresses Shipment to DELIVERED
    print("🏁 Driver Updates Shipment to DELIVERED...")
    delivery_resp = client.patch(f"/shipments/{shipment_id}/status", json={
        "status": "DELIVERED"
    }, headers=driver_headers)
    assert delivery_resp.status_code == 200, f"Driver delivery failed: {delivery_resp.text}"
    assert delivery_resp.json()["status"] == "DELIVERED"
    print(f"  - Shipment Status: {delivery_resp.json()['status']}")

    print("\n==============================================")
    print("🎉 ALL ENDPOINTS AND HACKATHON DEMO FLOW VERIFIED SUCCESSFULLY!")
    print("==============================================")

if __name__ == "__main__":
    test_freightshare_demo_flow()
