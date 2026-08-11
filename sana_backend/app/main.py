import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError

from .api.auth import router as auth_router
from .api.build import router as build_router
from .api.chat import router as chat_router
from .api.conversations import router as conversations_router
from .api.voice import router as voice_router
from .db.init_db import init_db

logger = logging.getLogger('sana-backend')


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    init_db()
    yield


app = FastAPI(title='SANA Backend', lifespan=lifespan)

# Flutter web runs the app in a browser, which enforces CORS — without
# this, every request from the app to this backend gets silently
# blocked before it even reaches our routes (confirmed by testing:
# "blocked by CORS policy" in the browser console).
#
# Wide open for local development. Before shipping anywhere real,
# replace allow_origins with the app's actual deployed origin(s) —
# native iOS/Android builds aren't affected by CORS at all, only the
# web target is.
app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_methods=['*'],
    allow_headers=['*'],
)


@app.exception_handler(SQLAlchemyError)
def handle_database_error(request: Request, exc: SQLAlchemyError) -> JSONResponse:
    # Catch-all safety net so a database problem never leaks a raw
    # stack trace / connection string to the client — routes and
    # services should normally catch and handle SQLAlchemyError
    # themselves (see chat_service.py's rollback-then-HTTPException
    # pattern) before it gets here.
    logger.exception('Unhandled database error on %s %s', request.method, request.url.path)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={'detail': 'A database error occurred. Please try again.'},
    )


app.include_router(auth_router)
app.include_router(build_router)
app.include_router(chat_router)
app.include_router(conversations_router)
app.include_router(voice_router)


@app.get('/health')
def health() -> dict[str, str]:
    return {'status': 'ok'}
