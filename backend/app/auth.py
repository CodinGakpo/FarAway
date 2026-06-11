import httpx
from jose import jwt, JWTError
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

from app.config import (
    JWT_SECRET, 
    JWT_ALGORITHM, 
    ACCESS_TOKEN_EXPIRE_MINUTES, 
    FIREBASE_PROJECT_ID, 
    LOCAL_DEV_MODE
)
from app.database import get_db
from app.models import User
from app.schemas import TokenData

# OAuth2 scheme
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=False)

# Cache for Google public certificates (to avoid fetching on every request)
GOOGLE_CERTS_URL = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken-system@system.gserviceaccount.com"
certs_cache: Dict[str, str] = {}
certs_cache_expiry: datetime = datetime.min

def fetch_google_public_certs() -> Dict[str, str]:
    global certs_cache, certs_cache_expiry
    now = datetime.utcnow()
    # Refetch cache every 6 hours
    if not certs_cache or now > certs_cache_expiry:
        try:
            response = httpx.get(GOOGLE_CERTS_URL, timeout=5.0)
            if response.status_code == 200:
                certs_cache = response.json()
                certs_cache_expiry = now + timedelta(hours=6)
        except Exception as e:
            # If fetch fails but we have cached certs, keep using them
            if not certs_cache:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail=f"Failed to fetch Google public certificates: {str(e)}"
                )
    return certs_cache

def verify_firebase_token(token: str) -> Dict[str, Any]:
    """
    Decodes and verifies a Firebase ID Token using Google's public certificates.
    """
    try:
        # Get token header to find Key ID ('kid')
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")
        if not kid:
            raise JWTError("Token header does not contain 'kid'")

        # Fetch Google public certs
        certs = fetch_google_public_certs()
        public_key_cert = certs.get(kid)
        if not public_key_cert:
            raise JWTError("Invalid Key ID ('kid') in token header")

        # Verify token claims
        # Firebase aud is the Firebase Project ID, iss is https://securetoken.google.com/<project_id>
        claims = jwt.decode(
            token,
            public_key_cert,
            algorithms=["RS256"],
            audience=FIREBASE_PROJECT_ID,
            issuer=f"https://securetoken.google.com/{FIREBASE_PROJECT_ID}"
        )
        return claims
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid Firebase ID Token: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )

# Helper to sign local tokens for LOCAL_DEV_MODE tests
def create_local_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, JWT_SECRET, algorithm=JWT_ALGORITHM)
    return encoded_jwt

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if not token:
        raise credentials_exception

    user_id = None
    email = None
    role = None

    # Handle local development token verification
    if LOCAL_DEV_MODE:
        try:
            # First try decoding as local HS256 JWT
            payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
            user_id = payload.get("user_id") or payload.get("uid") or payload.get("sub")
            email = payload.get("email") or payload.get("sub")
            role = payload.get("role")
        except JWTError:
            # Fallback: support passing user ID directly as the token in mock testing
            # e.g. "driver_user_1" or "shipper_user_2"
            if "_" in token:
                user_id = token
                email = f"{token}@mock.com"
                role = "driver" if "driver" in token else "shipper"
            else:
                try:
                    claims = verify_firebase_token(token)
                    user_id = claims.get("user_id") or claims.get("uid") or claims.get("sub")
                    email = claims.get("email")
                    role = claims.get("role")
                except Exception:
                    raise credentials_exception
    else:
        # Production mode: Validate Firebase ID Token
        claims = verify_firebase_token(token)
        user_id = claims.get("user_id") or claims.get("uid") or claims.get("sub")
        email = claims.get("email")
        # Role is custom claim in Firebase or can be fetched from database
        role = claims.get("role")  # custom claim

    if not user_id:
        raise credentials_exception

    # Query or create the user in local PostgreSQL db
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        # Automatically register user in local db on first auth call (speeds up hackathon setup)
        # In production, we'd fetch or wait for profile register, but auto-sync is awesome for hackathons!
        # If role is unknown, default to "shipper" for customers, or parse from email/token
        if not role:
            role = "driver" if "driver" in (email or "").lower() else "shipper"
            
        user = User(
            id=user_id,
            email=email or f"{user_id}@firebase.com",
            role=role,
            name=user_id.replace("_", " ").title()
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    return user

class RoleChecker:
    def __init__(self, allowed_roles: list[str]):
        self.allowed_roles = allowed_roles

    def __call__(self, current_user: User = Depends(get_current_user)):
        if current_user.role not in self.allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Operation not permitted for role: {current_user.role}. Allowed: {self.allowed_roles}"
            )
        return current_user
