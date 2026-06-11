import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env file
env_path = Path(__file__).resolve().parent.parent / '.env'
load_dotenv(dotenv_path=env_path)

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/freightshare")
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# Firebase configurations
FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "freightshare-prod")
LOCAL_DEV_MODE = os.getenv("LOCAL_DEV_MODE", "true").lower() == "true"

# Fallback JWT Authentication
JWT_SECRET = os.getenv("JWT_SECRET", "428f5efd28e7bb7f9bdfa95c3453a2ef9b1fbf4148b3b64cfc418721c0ad5d45")
JWT_ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "1440"))

# Third-party API Integrations
GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "")
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
