import json
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import text
from sqlalchemy.orm import Session
from typing import List, Optional

from app.database import get_db, is_sqlite
from app.models import TrainSchedule
from app.schemas import TrainScheduleResponse
from app.auth import get_current_user
from app.routers.matches import get_train_coordinates

router = APIRouter(
    prefix="/railway",
    tags=["Indian Railways"]
)

# Seed dataset of train routes and departure times
TRAIN_SEEDS = [
    {
        "train_number": "22625",
        "train_name": "SBC Double Decker Express",
        "origin": "Chennai Central (MAS)",
        "destination": "KSR Bengaluru (SBC)",
        "departure_time": "07:25",
        "route": [
            [80.2707, 13.0827],  # Chennai
            [79.1388, 12.9691],  # Katpadi Junction (Vellore)
            [78.5830, 12.5694],  # Jolarpettai
            [78.2045, 12.9754],  # Bangarapet
            [77.5696, 12.9780]   # Bengaluru
        ]
    },
    {
        "train_number": "12607",
        "train_name": "Lalbagh Express",
        "origin": "KSR Bengaluru (SBC)",
        "destination": "Chennai Central (MAS)",
        "departure_time": "06:30",
        "route": [
            [77.5696, 12.9780],  # Bengaluru
            [78.2045, 12.9754],  # Bangarapet
            [78.5830, 12.5694],  # Jolarpettai
            [79.1388, 12.9691],  # Katpadi Junction (Vellore)
            [80.2707, 13.0827]   # Chennai
        ]
    },
    {
        "train_number": "12657",
        "train_name": "Bengaluru Mail (Overnight)",
        "origin": "Chennai Central (MAS)",
        "destination": "KSR Bengaluru (SBC)",
        "departure_time": "22:50",
        "route": [
            [80.2707, 13.0827],  # Chennai
            [79.1388, 12.9691],  # Katpadi Junction (Vellore)
            [77.5696, 12.9780]   # Bengaluru
        ]
    }
]

@router.post("/seed", status_code=status.HTTP_201_CREATED)
def seed_train_schedules(db: Session = Depends(get_db)):
    """
    Seeds the Indian Railways schedules and PostGIS spatial corridors.
    """
    seeded_count = 0
    for seed in TRAIN_SEEDS:
        # Check if train exists
        existing = db.query(TrainSchedule).filter(TrainSchedule.train_number == seed["train_number"]).first()
        if existing:
            continue
            
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
        seeded_count += 1
        
    db.commit()
    return {"status": "success", "message": f"Seeded {seeded_count} train schedules successfully"}


@router.get("/", response_model=List[TrainScheduleResponse])
def list_train_schedules(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    """
    Lists all train schedules with route geometry polylines.
    """
    trains = db.query(TrainSchedule).all()
    results = []
    for train in trains:
        res = TrainScheduleResponse.from_orm(train)
        res.route_coordinates = get_train_coordinates(train.id, db)
        results.append(res)
    return results
