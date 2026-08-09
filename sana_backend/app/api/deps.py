import logging

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from ..core.security import InvalidTokenException, decode_access_token
from ..db.session import get_db
from ..models.user import User

logger = logging.getLogger('sana-backend')

_bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Shared dependency for every protected endpoint (chat, conversations).

    Verifies the JWT, then loads the user it names — a token for a
    since-deleted user is treated the same as an invalid token, not a
    500.
    """
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Missing bearer token.',
            headers={'WWW-Authenticate': 'Bearer'},
        )
    try:
        user_id = decode_access_token(credentials.credentials)
    except InvalidTokenException as e:
        # Log the specific reason server-side; the client only gets a
        # generic message — raw decode errors ("codec can't decode
        # byte...") are internal detail, not something to expose.
        logger.info('Rejected invalid token: %s', e)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Invalid or expired token.',
            headers={'WWW-Authenticate': 'Bearer'},
        ) from e

    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='User for this token no longer exists.',
            headers={'WWW-Authenticate': 'Bearer'},
        )
    return user
