from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.config import DATABASE_URL

# Check if SQLite is being used as a fallback
is_sqlite = DATABASE_URL.startswith("sqlite")

# Create SQLAlchemy engine
if is_sqlite:
    engine = create_engine(
        DATABASE_URL, connect_args={"check_same_thread": False}
    )
else:
    # Postgres engine settings with pool tuning for production performance
    engine = create_engine(
        DATABASE_URL,
        pool_size=10,
        max_overflow=20,
        pool_recycle=3600
    )

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

# Dependency to get db session in endpoints
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
