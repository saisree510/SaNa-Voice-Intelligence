import logging
import hmac
import uuid
from typing import Optional, Dict, Any

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from supabase import create_client

from app.config import settings

logger = logging.getLogger("backend.auth")
security = HTTPBearer(auto_error=False)


class AuthenticatedUser:
    def __init__(self, user_id: str, email: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None):
        self.id = user_id
        self.email = email
        self.metadata = metadata or {}


def normalize_user_id(user_id: Optional[str]) -> str:
    candidate = user_id.strip() if isinstance(user_id, str) else ""
    if candidate.startswith("user-"):
        suffix = candidate[5:]
        try:
            uuid.UUID(suffix)
            return suffix
        except ValueError:
            return candidate
    return candidate


def user_id_aliases(user_id: Optional[str]) -> set[str]:
    normalized = normalize_user_id(user_id)
    aliases = {normalized} if normalized else set()
    try:
        uuid.UUID(normalized)
    except ValueError:
        return aliases
    aliases.add(f"user-{normalized}")
    return aliases


def _get_agent_authenticated_user(request: Request) -> Optional[AuthenticatedUser]:
    shared_secret = (settings.AGENT_BACKEND_SHARED_SECRET or settings.LIVEKIT_API_SECRET or '').strip()
    if not shared_secret:
        return None

    provided_secret = request.headers.get('X-Sana-Agent-Secret', '').strip()
    if not hmac.compare_digest(provided_secret, shared_secret):
        return None

    user_id = normalize_user_id(request.headers.get('X-Sana-Agent-User-Id', ''))
    if not user_id:
        return None

    email = request.headers.get('X-Sana-Agent-User-Email')
    if isinstance(email, str):
        email = email.strip() or None

    logger.info('Authenticated internal agent request for user %s', user_id)
    return AuthenticatedUser(user_id=user_id, email=email, metadata={'source': 'internal-agent'})


def _decode_authenticated_claims(token: str) -> Dict[str, Any]:
    if settings.SUPABASE_JWT_SECRET:
        return jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            options={"verify_aud": False, "require": ["sub", "exp"]},
        )

    if not settings.SUPABASE_URL or not settings.SUPABASE_ANON_KEY:
        raise jwt.InvalidTokenError(
            "Backend authentication is not configured. Set SUPABASE_JWT_SECRET or SUPABASE_URL and SUPABASE_ANON_KEY."
        )

    try:
        response = create_client(
            settings.SUPABASE_URL,
            settings.SUPABASE_ANON_KEY,
        ).auth.get_user(token)
    except Exception as exc:
        raise jwt.InvalidTokenError("Supabase rejected the access token") from exc

    user = getattr(response, "user", None)
    if user is None or not getattr(user, "id", None):
        raise jwt.InvalidTokenError("Supabase session has no authenticated user")

    return {
        "sub": user.id,
        "email": getattr(user, "email", None),
        "user_metadata": getattr(user, "user_metadata", None) or {},
    }


async def get_current_user(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
) -> AuthenticatedUser:
    """
    Extracts and cryptographically validates a Supabase access token.

    Internal LiveKit-agent calls may authenticate with the dedicated shared-secret
    headers, but public callers never receive a development-user fallback.
    """
    if not credentials:
        agent_user = _get_agent_authenticated_user(request)
        if agent_user is not None:
            return agent_user
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="A valid Supabase session is required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = credentials.credentials
    try:
        payload = _decode_authenticated_claims(token)

        user_id = normalize_user_id(payload.get("sub"))
        email = payload.get("email")
        user_metadata = payload.get("user_metadata", {})

        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token: sub claim missing",
            )

        return AuthenticatedUser(user_id=user_id, email=email, metadata=user_metadata)

    except jwt.PyJWTError as e:
        logger.warning("JWT verification failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )
