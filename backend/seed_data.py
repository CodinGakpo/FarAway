import json
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from sqlalchemy import text

from app.database import SessionLocal, engine, is_sqlite
from app.models import User, Trip, Load, TrainSchedule, Match, Rating
from app.routers.railway import TRAIN_SEEDS

def seed_database():
    print("🚀 Starting Database Seeding...")
    db = SessionLocal()
    
    # 0. Enable PostGIS if Postgres
    if not is_sqlite:
        try:
            with engine.connect() as conn:
                conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis;"))
                conn.commit()
            print("  - PostGIS Extension verified/enabled.")
        except Exception as e:
            print(f"  - PostGIS Extension enable warning: {e}")

    # Create tables
    from app.database import Base
    Base.metadata.create_all(bind=engine)

    try:
        # 1. Seed Users
        users = [
            {"id": "driver_arjun", "email": "arjun@freightshare.com", "role": "driver", "name": "Arjun Kumar"},
            {"id": "driver_vijay", "email": "vijay@freightshare.com", "role": "driver", "name": "Vijay Singh"},
            {"id": "shipper_niranjan", "email": "niranjan@freightshare.com", "role": "shipper", "name": "Niranjan Shippers Ltd"},
            {"id": "shipper_ops", "email": "ops@freightshare.com", "role": "shipper", "name": "Global Logis Ops"}
        ]
        for u in users:
            existing = db.query(User).filter(User.id == u["id"]).first()
            if not existing:
                db_user = User(id=u["id"], email=u["email"], role=u["role"], name=u["name"])
                db.add(db_user)
        db.commit()
        print("  - Users seeded.")

        # 2. Seed Train Schedules (Railways)
        train_count = 0
        for seed in TRAIN_SEEDS:
            existing = db.query(TrainSchedule).filter(TrainSchedule.train_number == seed["train_number"]).first()
            if not existing:
                # PostGIS LineString geometry string
                line_pts = ", ".join([f"{pt[0]} {pt[1]}" for pt in seed["route"]])
                route_wkt = f"SRID=4326;LINESTRING({line_pts})"
                
                train = TrainSchedule(
                    train_number=seed["train_number"],
                    train_name=seed["train_name"],
                    origin=seed["origin"],
                    destination=seed["destination"],
                    departure_time=seed["departure_time"],
                    route_geometry=route_wkt
                )
                db.add(train)
                train_count += 1
        db.commit()
        print(f"  - {train_count} Train Schedules seeded.")

        # 3. Seed Trips
        trips = [
            {
                "driver_id": "driver_arjun",
                "origin_name": "Chennai",
                "destination_name": "Bangalore",
                "departure_time": datetime.utcnow() + timedelta(days=2),
                "max_weight_capacity": 5000.0,
                "max_volume_capacity": 200.0,
                "route": [
                    [80.2707, 13.0827], # Chennai
                    [79.1325, 12.9165], # Vellore
                    [77.5946, 12.9716]  # Bangalore
                ]
            },
            {
                "driver_id": "driver_vijay",
                "origin_name": "Madurai",
                "destination_name": "Chennai",
                "departure_time": datetime.utcnow() + timedelta(days=1),
                "max_weight_capacity": 8000.0,
                "max_volume_capacity": 300.0,
                "route": [
                    [78.1198, 9.9252],  # Madurai
                    [78.7047, 10.7905], # Trichy
                    [80.2707, 13.0827]  # Chennai
                ]
            }
        ]
        
        trip_ids = []
        for t in trips:
            # Check if active trip already exists
            existing = db.query(Trip).filter(Trip.driver_id == t["driver_id"], Trip.origin_name == t["origin_name"]).first()
            if not existing:
                # PostGIS LineString geometry string
                line_pts = ", ".join([f"{pt[0]} {pt[1]}" for pt in t["route"]])
                route_wkt = f"SRID=4326;LINESTRING({line_pts})"
                
                trip = Trip(
                    driver_id=t["driver_id"],
                    origin_name=t["origin_name"],
                    destination_name=t["destination_name"],
                    departure_time=t["departure_time"],
                    max_weight_capacity=t["max_weight_capacity"],
                    max_volume_capacity=t["max_volume_capacity"],
                    remaining_weight_capacity=t["max_weight_capacity"],
                    remaining_volume_capacity=t["max_volume_capacity"],
                    route_geometry=route_wkt,
                    status="ACTIVE"
                )
                db.add(trip)
                db.commit()
                db.refresh(trip)
                trip_ids.append(trip.id)
            else:
                trip_ids.append(existing.id)
        print("  - Driver Trips seeded.")

        # 4. Seed Loads
        loads = [
            {
                "shipper_id": "shipper_niranjan",
                "pickup_name": "Vellore",
                "dropoff_name": "Bangalore",
                "pickup_lat": 12.9165, "pickup_lng": 79.1325,
                "dropoff_lat": 12.9716, "dropoff_lng": 77.5946,
                "weight": 800.0,
                "volume": 35.0,
                "status": "PENDING"
            },
            {
                "shipper_id": "shipper_niranjan",
                "pickup_name": "Trichy",
                "dropoff_name": "Chennai",
                "pickup_lat": 10.7905, "pickup_lng": 78.7047,
                "dropoff_lat": 13.0827, "dropoff_lng": 80.2707,
                "weight": 1200.0,
                "volume": 50.0,
                "status": "MATCHED"
            }
        ]

        load_ids = []
        for l in loads:
            existing = db.query(Load).filter(Load.shipper_id == l["shipper_id"], Load.pickup_name == l["pickup_name"]).first()
            if not existing:
                # PostGIS Point geometry string
                p_wkt = f"SRID=4326;POINT({l['pickup_lng']} {l['pickup_lat']})"
                d_wkt = f"SRID=4326;POINT({l['dropoff_lng']} {l['dropoff_lat']})"
                
                load = Load(
                    shipper_id=l["shipper_id"],
                    pickup_name=l["pickup_name"],
                    dropoff_name=l["dropoff_name"],
                    weight=l["weight"],
                    volume=l["volume"],
                    pickup_geometry=p_wkt,
                    dropoff_geometry=d_wkt,
                    status=l["status"]
                )
                db.add(load)
                db.commit()
                db.refresh(load)
                load_ids.append(load.id)
            else:
                load_ids.append(existing.id)
        print("  - Shipper Loads seeded.")

        # 5. Seed Matches & Ratings
        if len(load_ids) >= 2 and len(trip_ids) >= 2:
            # Let's check if matches already exist
            existing_match = db.query(Match).filter(Match.load_id == load_ids[1]).first()
            if not existing_match:
                # Seed an accepted match to drive Trichy -> Chennai load
                match = Match(
                    load_id=load_ids[1],
                    trip_id=trip_ids[1], # Madurai -> Chennai trip
                    score=0.98,
                    status="ACCEPTED",
                    explanation="Recommended shared backhaul. Truck route directly intersects Trichy pickup location and Chennai dropoff destination. Sufficient truck capacity available."
                )
                db.add(match)
                db.commit()
                db.refresh(match)
                
                # Decrement trip capacity
                trip = db.query(Trip).filter(Trip.id == trip_ids[1]).first()
                trip.remaining_weight_capacity -= 1200.0
                trip.remaining_volume_capacity -= 50.0

                # Seed Rating for accepted match
                rating = Rating(
                    match_id=match.id,
                    score=5,
                    comment="Excellent match! Truck driver accepted instantly and load delivered on time."
                )
                db.add(rating)
                db.commit()
                print("  - Matches and Ratings seeded.")

        print("🎉 Database Seeding Completed Successfully!")

    except Exception as e:
        db.rollback()
        print(f"❌ Seeding Error: {str(e)}")
    finally:
        db.close()

if __name__ == "__main__":
    seed_database()
