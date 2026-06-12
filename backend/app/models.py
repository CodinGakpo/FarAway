from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Text, func, Boolean
from sqlalchemy.orm import relationship
from geoalchemy2 import Geometry
from app.database import Base, is_sqlite

class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, index=True) # Firebase Auth UID (String)
    email = Column(String, unique=True, index=True, nullable=False)
    role = Column(String, nullable=False)  # "driver" or "shipper" (which is customer)
    name = Column(String, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    trips = relationship("Trip", back_populates="driver", cascade="all, delete-orphan")
    loads = relationship("Load", back_populates="shipper", cascade="all, delete-orphan")
    shipments = relationship("Shipment", back_populates="customer", cascade="all, delete-orphan")


class Trip(Base):
    __tablename__ = "trips"

    id = Column(Integer, primary_key=True, index=True)
    driver_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    origin_name = Column(String, nullable=False)
    destination_name = Column(String, nullable=False)
    departure_time = Column(DateTime, nullable=False)
    max_weight_capacity = Column(Float, nullable=False)
    max_volume_capacity = Column(Float, nullable=False)
    remaining_weight_capacity = Column(Float, nullable=False)
    remaining_volume_capacity = Column(Float, nullable=False)
    status = Column(String, default="ACTIVE")  # "ACTIVE", "COMPLETED"
    
    # PostGIS route geometry line
    route_geometry = Column(Geometry(geometry_type='LINESTRING', srid=4326) if not is_sqlite else Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    driver = relationship("User", back_populates="trips")
    matches = relationship("Match", back_populates="trip", cascade="all, delete-orphan")
    shipments = relationship("Shipment", back_populates="trip", cascade="all, delete-orphan")


class Load(Base):
    __tablename__ = "loads"

    id = Column(Integer, primary_key=True, index=True)
    shipper_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    pickup_name = Column(String, nullable=False)
    dropoff_name = Column(String, nullable=False)
    weight = Column(Float, nullable=False)
    volume = Column(Float, nullable=False)
    status = Column(String, default="PENDING")  # "PENDING", "MATCHED", "PICKED_UP", "DELIVERED"

    # PostGIS Point geometries
    pickup_geometry = Column(Geometry(geometry_type='POINT', srid=4326) if not is_sqlite else Text, nullable=False)
    dropoff_geometry = Column(Geometry(geometry_type='POINT', srid=4326) if not is_sqlite else Text, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    shipper = relationship("User", back_populates="loads")
    matches = relationship("Match", back_populates="load", cascade="all, delete-orphan")


class TrainSchedule(Base):
    __tablename__ = "train_schedules"

    id = Column(Integer, primary_key=True, index=True)
    train_number = Column(String, unique=True, index=True, nullable=False)
    train_name = Column(String, nullable=False)
    origin = Column(String, nullable=False)
    destination = Column(String, nullable=False)
    departure_time = Column(String, nullable=False)  # Seeded depart time, e.g. "20:00" daily

    # PostGIS geometry for railway route line
    route_geometry = Column(Geometry(geometry_type='LINESTRING', srid=4326) if not is_sqlite else Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    matches = relationship("Match", back_populates="train_schedule", cascade="all, delete-orphan")


class Match(Base):
    __tablename__ = "matches"

    id = Column(Integer, primary_key=True, index=True)
    load_id = Column(Integer, ForeignKey("loads.id", ondelete="CASCADE"), nullable=False)
    
    # Matches can be either truck (trip) OR train!
    trip_id = Column(Integer, ForeignKey("trips.id", ondelete="CASCADE"), nullable=True)
    train_schedule_id = Column(Integer, ForeignKey("train_schedules.id", ondelete="CASCADE"), nullable=True)
    
    score = Column(Float, default=1.0)  # Overlap rating/score
    status = Column(String, default="PROPOSED")  # "PROPOSED", "ACCEPTED", "REJECTED"
    explanation = Column(Text, nullable=True)  # Claude match explanations
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    load = relationship("Load", back_populates="matches")
    trip = relationship("Trip", back_populates="matches")
    train_schedule = relationship("TrainSchedule", back_populates="matches")
    ratings = relationship("Rating", back_populates="match", cascade="all, delete-orphan")


class Rating(Base):
    __tablename__ = "ratings"

    id = Column(Integer, primary_key=True, index=True)
    match_id = Column(Integer, ForeignKey("matches.id", ondelete="CASCADE"), nullable=False)
    score = Column(Integer, nullable=False)  # 1 to 5 stars
    comment = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    match = relationship("Match", back_populates="ratings")


class Shipment(Base):
    __tablename__ = "shipments"

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    trip_id = Column(Integer, ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    pickup_location = Column(String, nullable=False)
    dropoff_location = Column(String, nullable=False)
    weight = Column(Float, nullable=False)
    volume = Column(Float, nullable=False)
    cargo_category = Column(String, nullable=False)
    price = Column(Float, nullable=False, default=0.0)
    status = Column(String, default="DRAFT")  # "DRAFT", "PENDING", "ACCEPTED", "PICKED_UP", "DELIVERED", "REJECTED"
    feasibility_status = Column(Boolean, default=True)
    feasibility_trace = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    customer = relationship("User", back_populates="shipments")
    trip = relationship("Trip", back_populates="shipments")
