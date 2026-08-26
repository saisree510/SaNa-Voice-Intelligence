from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6, max_length=72)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1)


class UserPublic(BaseModel):
    id: str
    email: str
    name: str | None = None
    created_at: datetime

    model_config = {'from_attributes': True}


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = 'bearer'
    user: UserPublic


class UpdateNameRequest(BaseModel):
    name: str = Field(min_length=1, max_length=100)
