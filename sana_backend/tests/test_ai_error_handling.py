"""Confirms chat_service.py maps AIService failures to the right HTTP
status instead of letting them 500 or corrupt the conversation. Uses
fake providers (not the real network-calling one) so this stays fast
and offline, same as the rest of the suite.
"""

from app.main import app
from app.services.ai_service import AIProvider, AIServiceError, AITimeoutError, AIUnexpectedResponseError, get_ai_provider


class _TimeoutProvider(AIProvider):
    async def generate_reply(self, *, mode, history, user_message):
        raise AITimeoutError('simulated timeout')


class _UnexpectedProvider(AIProvider):
    async def generate_reply(self, *, mode, history, user_message):
        raise AIUnexpectedResponseError('simulated empty response')


class _GenericFailureProvider(AIProvider):
    async def generate_reply(self, *, mode, history, user_message):
        raise AIServiceError('simulated provider outage')


def test_ai_timeout_returns_504(client, register_and_login):
    # Each test gets a fresh `client` fixture, which resets
    # dependency_overrides — no manual cleanup needed here.
    _, headers = register_and_login('aitimeout@example.com')
    app.dependency_overrides[get_ai_provider] = lambda: _TimeoutProvider()
    resp = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'debate', 'message': 'hello'},
        headers=headers,
    )
    assert resp.status_code == 504


def test_ai_unexpected_response_returns_502(client, register_and_login):
    _, headers = register_and_login('aiunexpected@example.com')
    app.dependency_overrides[get_ai_provider] = lambda: _UnexpectedProvider()
    resp = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'debate', 'message': 'hello'},
        headers=headers,
    )
    assert resp.status_code == 502


def test_ai_generic_failure_returns_502_and_no_conversation_is_created(client, register_and_login):
    _, headers = register_and_login('aifailure@example.com')
    app.dependency_overrides[get_ai_provider] = lambda: _GenericFailureProvider()
    resp = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'debate', 'message': 'hello'},
        headers=headers,
    )
    assert resp.status_code == 502

    # The failed attempt shouldn't leave a half-created conversation behind.
    listing = client.get('/conversations', headers=headers)
    assert listing.json() == []
