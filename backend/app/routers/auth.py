from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import User
from app.schemas import UserResponse, UserCreate
from app.auth import get_current_user, create_local_token, LOCAL_DEV_MODE

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"]
)

# For local development tests, we expose a mock endpoint to generate JWT tokens
class LocalLoginRequest(UserCreate):
    pass

@router.post("/login", response_model=dict)
def mock_login_for_dev(request: LocalLoginRequest, db: Session = Depends(get_db)):
    """
    Mock login helper (LOCAL_DEV_MODE only).
    Generates a custom local HS256 JWT token representing the user's role and email.
    """
    if not LOCAL_DEV_MODE:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Mock login is only available in LOCAL_DEV_MODE. Use Firebase ID tokens in production."
        )

    # Sync user in local db
    user = db.query(User).filter(User.id == request.id).first()
    if not user:
        user = User(
            id=request.id,
            email=request.email,
            role=request.role,
            name=request.name or request.id.replace("_", " ").title()
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    token_data = {
        "uid": user.id,
        "user_id": user.id,
        "email": user.email,
        "role": user.role
    }
    token = create_local_token(token_data)
    
    return {
        "access_token": token,
        "token_type": "bearer",
        "role": user.role,
        "user_id": user.id
    }


@router.get("/me", response_model=UserResponse)
def get_current_user_profile(current_user: User = Depends(get_current_user)):
    """
    Decodes the Bearer token (Firebase ID token or Local dev token) and returns the profile.
    """
    return current_user
