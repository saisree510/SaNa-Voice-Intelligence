import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/errors/app_exception.dart';
import 'auth_service.dart';
import 'backend_error.dart';

/// [AuthService] backed by the real sana_backend (POST /auth/register,
/// /auth/login) — see sana_backend/app/api/auth.py. Replaces
/// [MockAuthService] once a backend is available; same interface, no
/// changes needed anywhere else.
class RealAuthService implements AuthService {
  RealAuthService({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Uri _uri(String path) => Uri.parse('${AppConfig.backendBaseUrl}$path');

  @override
  Future<AuthUser> signUp({required String email, required String password}) =>
      _authRequest('/auth/register', email: email, password: password);

  @override
  Future<AuthUser> login({required String email, required String password}) =>
      _authRequest('/auth/login', email: email, password: password);

  Future<AuthUser> _authRequest(String path, {required String email, required String password}) async {
    final http.Response response;
    try {
      response = await _http.post(
        _uri(path),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's servers. Check your connection and try again.", e);
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;
      return AuthUser(
        id: user['id'] as String,
        email: user['email'] as String,
        token: data['access_token'] as String,
      );
    }

    throw AuthException(extractBackendErrorDetail(response) ?? 'Something went wrong. Please try again.');
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    // sana_backend doesn't implement password reset yet (out of scope
    // for the auth/chat backend milestone) — mocked so Forgot Password
    // still behaves reasonably. Swap for a real call once the backend
    // adds POST /auth/forgot-password.
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Future<void> updateName({required String token, required String name}) async {
    final http.Response response;
    try {
      response = await _http.patch(
        _uri('/auth/me'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'name': name}),
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's servers. Check your connection and try again.", e);
    }

    if (response.statusCode != 200) {
      throw AuthException(extractBackendErrorDetail(response) ?? "Couldn't save your name. Please try again.");
    }
  }

  @override
  Future<void> logout() async {
    // JWTs are stateless — nothing to call server-side. AuthProvider
    // just drops the token client-side (see AuthProvider.logout).
  }
}
