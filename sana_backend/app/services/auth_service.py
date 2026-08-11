from fastapi import HTTPException, status
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from ..core.security import create_access_token, hash_password, verify_password
from ..models.user import User


def register_user(db: Session, *, email: str, password: str) -> User:
    existing = db.query(User).filter(User.email == email).first()
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='An account with this email already exists.')

    user = User(email=email, password_hash=hash_password(password))
    try:
        db.add(user)
        db.commit()
    except SQLAlchemyError as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Could not create account.'
        ) from e
    db.refresh(user)
    return user


def authenticate_user(db: Session, *, email: str, password: str) -> User:
    user = db.query(User).filter(User.email == email).first()
    # Deliberately identical error for "no such user" and "wrong password"
    # — distinguishing them lets an attacker enumerate registered emails.
    if user is None or not verify_password(password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Incorrect email or password.')
    return user


def issue_token_for(user: User) -> str:
    return create_access_token(subject=user.id)


def update_name(db: Session, *, user: User, name: str) -> User:
    user.name = name
    try:
        db.commit()
    except SQLAlchemyError as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Could not save your name.'
        ) from e
    db.refresh(user)
    return user
