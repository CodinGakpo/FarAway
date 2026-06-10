from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from app.core.config import settings

# SQLAlchemy setup for Supabase PostgreSQL database
engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True, # Recommended for remote databases to prevent connection drops
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()
