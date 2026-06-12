from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.database import engine, Base, is_sqlite
from app.routers import auth, trips, agent, shipments
from app.dependencies import get_db

# Auto-enable PostGIS extension on PostgreSQL and create tables
try:
    if not is_sqlite:
        with engine.connect() as conn:
            conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis;"))
            conn.commit()
    Base.metadata.create_all(bind=engine)
except Exception as e:
    print(f"Database setup warning: {str(e)}")

app = FastAPI(
    title="FreightShare Production Backend API",
    description="FastAPI Production Backend for FreightShare Hackathon. Supports Firebase Auth, PostGIS Spatial Matching, Celery/Redis.",
    version="2.0.0"
)

# CORS configuration for Flutter mobile app and React web dashboard
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API Routers
app.include_router(auth.router)
app.include_router(trips.router)
app.include_router(agent.router)
app.include_router(shipments.router)

@app.on_event("startup")
async def startup_event():
    await get_db().connect()

@app.on_event("shutdown")
async def shutdown_event():
    await get_db().disconnect()

@app.get("/health", tags=["Health"])
def health_check():
    """
    Service health validation endpoint
    """
    return {"status": "ok", "database": "sqlite" if is_sqlite else "postgresql+postgis"}

@app.get("/", tags=["Root"])
def root():
    return {
        "message": "Welcome to FreightShare Production API!",
        "docs_url": "/docs",
        "redoc_url": "/redoc"
    }
