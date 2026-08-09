def test_register_creates_account_and_returns_token(client):
    resp = client.post('/auth/register', json={'email': 'new@example.com', 'password': 'password123'})
    assert resp.status_code == 201
    body = resp.json()
    assert body['user']['email'] == 'new@example.com'
    assert 'id' in body['user']
    assert 'password' not in body['user']
    assert 'password_hash' not in body['user']
    assert body['access_token']
    assert body['token_type'] == 'bearer'


def test_register_duplicate_email_is_rejected(client):
    client.post('/auth/register', json={'email': 'dup@example.com', 'password': 'password123'})
    resp = client.post('/auth/register', json={'email': 'dup@example.com', 'password': 'password123'})
    assert resp.status_code == 409


def test_login_with_correct_credentials_returns_token(client):
    client.post('/auth/register', json={'email': 'login@example.com', 'password': 'password123'})
    resp = client.post('/auth/login', json={'email': 'login@example.com', 'password': 'password123'})
    assert resp.status_code == 200
    assert resp.json()['access_token']


def test_login_with_wrong_password_is_rejected(client):
    client.post('/auth/register', json={'email': 'login2@example.com', 'password': 'password123'})
    resp = client.post('/auth/login', json={'email': 'login2@example.com', 'password': 'wrongpassword'})
    assert resp.status_code == 401


def test_login_with_unknown_email_is_rejected(client):
    resp = client.post('/auth/login', json={'email': 'nosuchuser@example.com', 'password': 'password123'})
    assert resp.status_code == 401


def test_protected_endpoint_rejects_missing_token(client):
    resp = client.get('/conversations')
    assert resp.status_code == 401


def test_protected_endpoint_rejects_malformed_token(client):
    resp = client.get('/conversations', headers={'Authorization': 'Bearer not-a-real-token'})
    assert resp.status_code == 401


def test_protected_endpoint_accepts_valid_token(client, register_and_login):
    _, headers = register_and_login('protected@example.com')
    resp = client.get('/conversations', headers=headers)
    assert resp.status_code == 200
