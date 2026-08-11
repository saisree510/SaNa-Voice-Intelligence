import logging

from fastapi import Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from ..core.security import InvalidTokenException, decode_access_token
from ..db.session import get_db
from ..models.user import User

logger = logging.getLogger('sana-backend')

_bearer_scheme = HTTPBearer(auto_error=False)


def _user_for_token(token: str | None, db: Session) -> User:
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Missing bearer token.',
            headers={'WWW-Authenticate': 'Bearer'},
        )
    try:
        user_id = decode_access_token(token)
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


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Shared dependency for every protected endpoint (chat, conversations).

    Verifies the JWT, then loads the user it names — a token for a
    since-deleted user is treated the same as an invalid token, not a
    500.
    """
    return _user_for_token(credentials.credentials if credentials else None, db)


def get_current_user_allow_query_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    token: str | None = Query(default=None),
    db: Session = Depends(get_db),
) -> User:
    """Same verification as [get_current_user], but also accepts the JWT
    as a `?token=` query parameter when there's no Authorization header.

    Deliberately scoped to one route (the build artifact ZIP download,
    see api/build.py) rather than folded into get_current_user itself —
    a browser navigating directly to a URL (an <a href>/new-tab
    download, which is how a ZIP download has to work) can't attach a
    custom header, so the token has to travel some other way for that
    one case. Every other endpoint keeps requiring the header only.
    """
    if credentials is not None:
        return _user_for_token(credentials.credentials, db)
    return _user_for_token(token, db)
