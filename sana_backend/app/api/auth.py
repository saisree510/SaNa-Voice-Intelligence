from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..db.session import get_db
from ..models.user import User
from ..schemas.auth import LoginRequest, RegisterRequest, TokenResponse, UpdateNameRequest, UserPublic
from ..services.auth_service import authenticate_user, issue_token_for, register_user, update_name
from .deps import get_current_user

router = APIRouter(prefix='/auth', tags=['auth'])


@router.post('/register', response_model=TokenResponse, status_code=201)
def register(body: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    user = register_user(db, email=body.email, password=body.password)
    token = issue_token_for(user)
    return TokenResponse(access_token=token, user=UserPublic.model_validate(user))


@router.post('/login', response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    user = authenticate_user(db, email=body.email, password=body.password)
    token = issue_token_for(user)
    return TokenResponse(access_token=token, user=UserPublic.model_validate(user))


@router.patch('/me', response_model=UserPublic)
def update_my_name(
    body: UpdateNameRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> UserPublic:
    """Called once, right after onboarding (see sana_app's
    AuthProvider.completeOnboarding) — this is what lets the AI actually
    know the user's name (see modes/__init__.py's user_name_note),
    instead of it only ever existing in the app's local on-device
    storage the way it did before this endpoint existed.
    """
    updated = update_name(db, user=user, name=body.name)
    return UserPublic.model_validate(updated)
