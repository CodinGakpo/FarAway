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
    shipments = relationship("Shipment", back_populates="trip", cascade="all, delete-orphan")


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
