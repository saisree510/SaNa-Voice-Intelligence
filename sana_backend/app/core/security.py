"""Password hashing and JWT issuance/verification.

Uses `bcrypt` directly (not passlib — confirmed by testing that
passlib's bcrypt backend is broken against modern bcrypt versions,
see requirements.txt) and PyJWT for tokens.
"""

from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from jwt import InvalidTokenError

from .config import get_settings

# bcrypt's algorithm has a hard 72-byte input limit; anything longer is
# silently truncated by the library. Reject rather than silently
# truncate — a user should know their password wasn't fully used, not
# have '1234567...<72 bytes>REST_IGNORED' work.
_MAX_PASSWORD_BYTES = 72


def hash_password(password: str) -> str:
    if len(password.encode('utf-8')) > _MAX_PASSWORD_BYTES:
        raise ValueError('Password must be 72 bytes or fewer.')
    hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
    return hashed.decode('utf-8')


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode('utf-8'), password_hash.encode('utf-8'))
    except ValueError:
        # Malformed hash in the DB — treat as "doesn't match" rather than 500ing.
        return False


def create_access_token(*, subject: str) -> str:
    """[subject] is the user id, stored in the JWT's `sub` claim."""
    settings = get_settings()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {'sub': subject, 'exp': expires_at}
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


class InvalidTokenException(Exception):
    """Raised for any token problem (expired, malformed, wrong signature)."""


def decode_access_token(token: str) -> str:
    """Returns the user id (`sub` claim) from a valid token, or raises."""
    settings = get_settings()
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
    except InvalidTokenError as e:
        raise InvalidTokenException(str(e)) from e
    subject = payload.get('sub')
    if not subject:
        raise InvalidTokenException('Token missing subject claim.')
    return subject
