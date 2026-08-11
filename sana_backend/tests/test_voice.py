"""Tests for POST /api/voice/token's conversation-resume logic (see
app/api/voice.py) -- the piece that lets a voice call started after
stopping the mic actually continue the same conversation instead of
always starting fresh. Doesn't test the LiveKit token/room mechanics
themselves (that needs real LiveKit credentials + a live connection);
just the DB-backed conversation creation/validation this endpoint does
before minting one.
"""


def _register(client, email='voiceuser@example.com'):
    resp = client.post('/auth/register', json={'email': email, 'password': 'password123'})
    return resp.json()['user']['id']


def test_token_without_conversation_id_creates_a_new_conversation(client):
    user_id = _register(client)
    resp = client.post(
        '/api/voice/token', json={'mode': 'debate', 'user_id': user_id, 'user_name': 'Test'}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body['conversation_id']
    assert body['room_name']
    assert body['token']


def test_token_with_a_valid_conversation_id_resumes_it(client):
    user_id = _register(client, 'resume@example.com')
    first = client.post(
        '/api/voice/token', json={'mode': 'build', 'user_id': user_id, 'user_name': 'Test'}
    ).json()

    second = client.post(
        '/api/voice/token',
        json={
            'mode': 'build',
            'user_id': user_id,
            'user_name': 'Test',
            'conversation_id': first['conversation_id'],
        },
    ).json()

    assert second['conversation_id'] == first['conversation_id']
    # A different room each time even when resuming the same
    # conversation -- LiveKit rooms aren't reused, only the underlying
    # conversation record is.
    assert second['room_name'] != first['room_name']


def test_token_rejects_a_conversation_id_belonging_to_another_user(client):
    user_a = _register(client, 'voicea@example.com')
    user_b = _register(client, 'voiceb@example.com')

    created = client.post(
        '/api/voice/token', json={'mode': 'debate', 'user_id': user_a, 'user_name': 'A'}
    ).json()

    resp = client.post(
        '/api/voice/token',
        json={
            'mode': 'debate',
            'user_id': user_b,
            'user_name': 'B',
            'conversation_id': created['conversation_id'],
        },
    )
    assert resp.status_code == 403


def test_token_rejects_a_conversation_id_in_the_wrong_mode(client):
    user_id = _register(client, 'wrongmode@example.com')
    created = client.post(
        '/api/voice/token', json={'mode': 'debate', 'user_id': user_id, 'user_name': 'Test'}
    ).json()

    resp = client.post(
        '/api/voice/token',
        json={
            'mode': 'brainstorm',
            'user_id': user_id,
            'user_name': 'Test',
            'conversation_id': created['conversation_id'],
        },
    )
    assert resp.status_code == 400


def test_token_rejects_a_nonexistent_conversation_id(client):
    user_id = _register(client, 'nosuchconvo@example.com')
    resp = client.post(
        '/api/voice/token',
        json={
            'mode': 'debate',
            'user_id': user_id,
            'user_name': 'Test',
            'conversation_id': 'does-not-exist',
        },
    )
    assert resp.status_code == 404


def test_token_rejects_unknown_mode(client):
    user_id = _register(client, 'unknownmode@example.com')
    resp = client.post(
        '/api/voice/token', json={'mode': 'therapy', 'user_id': user_id, 'user_name': 'Test'}
    )
    assert resp.status_code == 400
