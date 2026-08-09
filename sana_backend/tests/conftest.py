"""Shared pytest fixtures.

Each test gets a fresh in-memory SQLite database (StaticPool keeps the
same in-memory DB alive across the multiple connections a test request
cycle opens — plain in-memory SQLite would otherwise reset on every
new connection) and the mock AI provider, so the suite runs fully
offline with no real API key and no dependency on a Postgres server.
"""

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.session import Base, get_db
from app.main import app
from app.services.ai_service import MockAIProvider, get_ai_provider


@pytest.fixture()
def db_session():
    engine = create_engine(
        'sqlite://',
        connect_args={'check_same_thread': False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)

    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)


@pytest.fixture()
def client(db_session) -> Iterator[TestClient]:
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_ai_provider] = lambda: MockAIProvider()

    # Deliberately not `with TestClient(app) as ...` — that would run
    # the app's lifespan, which calls init_db() against the *real*
    # DATABASE_URL and creates a stray sana.db file. The test DB is
    # already set up by the db_session fixture; the app never needs its
    # own startup hook here.
    test_client = TestClient(app)
    yield test_client

    app.dependency_overrides.clear()


@pytest.fixture()
def register_and_login(client: TestClient):
    """Returns a function: call it with an email to get back
    (user_json, auth_headers) for a freshly registered account.
    """

    def _do(email: str = 'test@example.com', password: str = 'password123'):
        resp = client.post('/auth/register', json={'email': email, 'password': password})
        assert resp.status_code == 201, resp.text
        body = resp.json()
        headers = {'Authorization': f"Bearer {body['access_token']}"}
        return body['user'], headers

    return _do
