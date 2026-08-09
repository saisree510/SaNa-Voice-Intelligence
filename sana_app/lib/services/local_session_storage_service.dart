import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'session_storage_service.dart';

/// [SessionStorageService] backed by on-device storage ([SharedPreferences]).
class LocalSessionStorageService implements SessionStorageService {
  static const _key = 'sana_session';

  @override
  Future<AuthUser?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final id = map['id'] as String?;
    final email = map['email'] as String?;
    if (id == null || email == null) return null;
    return AuthUser(id: id, email: email, token: map['token'] as String?);
  }

  @override
  Future<void> saveSession(AuthUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({'id': user.id, 'email': user.email, 'token': user.token}),
    );
  }

  @override
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
