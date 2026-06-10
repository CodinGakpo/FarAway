from fastapi import FastAPI, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session
from app.db.client import engine, Base
from app.core.dependencies import get_db

# Create all database tables (for demo/initial setup purposes)
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="FarAway API",
    description="Backend for FarAway Flutter App connecting to Supabase PostgreSQL",
    version="1.0.0",
)

@app.get("/")
def read_root():
    return {"message": "Welcome to FarAway API. Connected to Supabase DB."}

@app.get("/health")
def health_check(db: Session = Depends(get_db)):
    try:
        # Check database connectivity
        db.execute(text("SELECT 1"))
        return {"status": "ok", "database": "connected"}
    except Exception as e:
        return {"status": "error", "database": str(e)}
