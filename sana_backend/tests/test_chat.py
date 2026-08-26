def test_new_conversation_is_created_when_no_conversation_id(client, register_and_login):
    _, headers = register_and_login('chat1@example.com')
    resp = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'debate', 'message': 'AI will replace developers.'},
        headers=headers,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body['conversation_id']
    assert body['mode'] == 'debate'
    assert body['response']


def test_debate_mode_reply_is_challenging_in_tone(client, register_and_login):
    _, headers = register_and_login('debate@example.com')
    resp = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'debate', 'message': 'Remote work is always better.'},
        headers=headers,
    )
    assert resp.status_code == 200
    # MockAIProvider's debate templates always push back / ask a challenging question.
    assert '?' in resp.json()['response']


def test_brainstorm_mode_reply_expands_the_idea(client, register_and_login):
    _, headers = register_and_login('brainstorm@example.com')
    resp = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'brainstorm', 'message': 'An app for students.'},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()['mode'] == 'brainstorm'


def test_build_mode_reply_moves_toward_a_plan(client, register_and_login):
    _, headers = register_and_login('build@example.com')
    resp = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'build', 'message': 'I want to build a recipe app.'},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()['mode'] == 'build'


def test_second_message_reuses_the_same_conversation(client, register_and_login):
    _, headers = register_and_login('convo@example.com')
    first = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'debate', 'message': 'First message.'},
        headers=headers,
    ).json()

    second = client.post(
        '/chat/message',
        json={'conversation_id': first['conversation_id'], 'mode': 'debate', 'message': 'Second message.'},
        headers=headers,
    ).json()

    assert second['conversation_id'] == first['conversation_id']

    detail = client.get(f"/conversations/{first['conversation_id']}", headers=headers).json()
    # 2 user + 2 assistant messages across both turns.
    assert len(detail['messages']) == 4
    assert [m['role'] for m in detail['messages']] == ['user', 'assistant', 'user', 'assistant']


def test_invalid_mode_is_rejected(client, register_and_login):
    _, headers = register_and_login('invalidmode@example.com')
    resp = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'therapy', 'message': 'hello'},
        headers=headers,
    )
    assert resp.status_code == 400


def test_empty_message_is_rejected(client, register_and_login):
    _, headers = register_and_login('emptymsg@example.com')
    resp = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'debate', 'message': '   '},
        headers=headers,
    )
    assert resp.status_code == 422


def test_chat_requires_authentication(client):
    resp = client.post(
        '/chat/message', json={'conversation_id': None, 'mode': 'debate', 'message': 'hello'}
    )
    assert resp.status_code == 401


def test_chat_with_nonexistent_conversation_id_returns_404(client, register_and_login):
    _, headers = register_and_login('missingconvo@example.com')
    resp = client.post(
        '/chat/message',
        json={'conversation_id': 'does-not-exist', 'mode': 'debate', 'message': 'hello'},
        headers=headers,
    )
    assert resp.status_code == 404


def test_chat_on_another_users_conversation_is_forbidden(client, register_and_login):
    _, headers_a = register_and_login('usera@example.com')
    _, headers_b = register_and_login('userb@example.com')

    conv = client.post(
        '/chat/message',
        json={'conversation_id': None, 'mode': 'debate', 'message': 'hello'},
        headers=headers_a,
    ).json()

    resp = client.post(
        '/chat/message',
        json={'conversation_id': conv['conversation_id'], 'mode': 'debate', 'message': 'butting in'},
        headers=headers_b,
    )
    assert resp.status_code == 403
