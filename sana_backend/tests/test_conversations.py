def _create_conversation(client, headers, mode='debate', message='hello'):
    resp = client.post(
        '/chat/message', json={'conversation_id': None, 'mode': mode, 'message': message}, headers=headers
    )
    return resp.json()['conversation_id']


def test_list_conversations_returns_only_own_conversations(client, register_and_login):
    _, headers_a = register_and_login('lista@example.com')
    _, headers_b = register_and_login('listb@example.com')

    _create_conversation(client, headers_a)
    _create_conversation(client, headers_a)
    _create_conversation(client, headers_b)

    resp_a = client.get('/conversations', headers=headers_a)
    assert resp_a.status_code == 200
    assert len(resp_a.json()) == 2

    resp_b = client.get('/conversations', headers=headers_b)
    assert len(resp_b.json()) == 1


def test_get_conversation_includes_message_history(client, register_and_login):
    _, headers = register_and_login('history@example.com')
    conv_id = _create_conversation(client, headers, message='What do you think about X?')

    resp = client.get(f'/conversations/{conv_id}', headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body['id'] == conv_id
    assert len(body['messages']) == 2
    assert body['messages'][0]['role'] == 'user'
    assert body['messages'][0]['content'] == 'What do you think about X?'
    assert body['messages'][1]['role'] == 'assistant'


def test_get_nonexistent_conversation_returns_404(client, register_and_login):
    _, headers = register_and_login('nf@example.com')
    resp = client.get('/conversations/does-not-exist', headers=headers)
    assert resp.status_code == 404


def test_get_other_users_conversation_is_forbidden(client, register_and_login):
    _, headers_a = register_and_login('owner@example.com')
    _, headers_b = register_and_login('intruder@example.com')
    conv_id = _create_conversation(client, headers_a)

    resp = client.get(f'/conversations/{conv_id}', headers=headers_b)
    assert resp.status_code == 403


def test_delete_conversation_removes_it(client, register_and_login):
    _, headers = register_and_login('deleter@example.com')
    conv_id = _create_conversation(client, headers)

    resp = client.delete(f'/conversations/{conv_id}', headers=headers)
    assert resp.status_code == 204

    resp = client.get(f'/conversations/{conv_id}', headers=headers)
    assert resp.status_code == 404


def test_delete_other_users_conversation_is_forbidden(client, register_and_login):
    _, headers_a = register_and_login('victim@example.com')
    _, headers_b = register_and_login('attacker@example.com')
    conv_id = _create_conversation(client, headers_a)

    resp = client.delete(f'/conversations/{conv_id}', headers=headers_b)
    assert resp.status_code == 403

    # Confirm it's still there for the actual owner.
    resp = client.get(f'/conversations/{conv_id}', headers=headers_a)
    assert resp.status_code == 200


def test_conversations_endpoints_require_authentication(client):
    assert client.get('/conversations').status_code == 401
    assert client.get('/conversations/some-id').status_code == 401
    assert client.delete('/conversations/some-id').status_code == 401
