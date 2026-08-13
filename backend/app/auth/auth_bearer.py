import logging
from typing import Optional, Dict, Any

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import settings

logger = logging.getLogger("backend.auth")
security = HTTPBearer(auto_error=False)


class AuthenticatedUser:
    def __init__(self, user_id: str, email: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None):
        self.id = user_id
        self.email = email
        self.metadata = metadata or {}


def _get_agent_authenticated_user(request: Request) -> Optional[AuthenticatedUser]:
    shared_secret = (settings.AGENT_BACKEND_SHARED_SECRET or '').strip()
    if not shared_secret:
        return None

    provided_secret = request.headers.get('X-Sana-Agent-Secret', '').strip()
    if provided_secret != shared_secret:
        return None

    user_id = request.headers.get('X-Sana-Agent-User-Id', '').strip()
    if not user_id:
        return None

    email = request.headers.get('X-Sana-Agent-User-Email')
    if isinstance(email, str):
        email = email.strip() or None

    logger.info('Authenticated internal agent request for user %s', user_id)
    return AuthenticatedUser(user_id=user_id, email=email, metadata={'source': 'internal-agent'})


def _decode_unverified_claims(token: str) -> Dict[str, Any]:
    return jwt.decode(token, options={"verify_signature": False, "verify_aud": False})


def _decode_authenticated_claims(token: str) -> Dict[str, Any]:
    if not settings.SUPABASE_JWT_SECRET:
        return _decode_unverified_claims(token)

    try:
        return jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            options={"verify_aud": False},
        )
    except jwt.PyJWTError as exc:
        if settings.ENVIRONMENT.lower() == "production":
            raise
        logger.warning(
            "JWT verification failed in %s environment; falling back to unverified decode for development compatibility: %s",
            settings.ENVIRONMENT,
            exc,
        )
        return _decode_unverified_claims(token)


async def get_current_user(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
) -> AuthenticatedUser:
    """
    Extracts and validates Supabase JWT token from HTTP Authorization header.
    In development mode without JWT secret configured, decodes payload claims directly.
    """
    if not credentials:
        agent_user = _get_agent_authenticated_user(request)
        if agent_user is not None:
            return agent_user
        # Fallback for local development or unauthenticated sandbox access
        logger.warning("No Authorization header provided. Using anonymous dev user.")
        return AuthenticatedUser(user_id="dev-user-0000", email="dev@sana.ai")

    token = credentials.credentials
    try:
        payload = _decode_authenticated_claims(token)

        user_id = payload.get("sub")
        email = payload.get("email")
        user_metadata = payload.get("user_metadata", {})

        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token: sub claim missing",
            )

        return AuthenticatedUser(user_id=user_id, email=email, metadata=user_metadata)

    except jwt.PyJWTError as e:
        logger.error(f"JWT Verification failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid authentication token: {str(e)}",
        )
