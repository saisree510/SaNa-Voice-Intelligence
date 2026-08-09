from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..db.session import get_db
from ..schemas.auth import LoginRequest, RegisterRequest, TokenResponse, UserPublic
from ..services.auth_service import authenticate_user, issue_token_for, register_user

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
