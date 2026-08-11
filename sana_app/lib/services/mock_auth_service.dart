import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/validators.dart';
import 'auth_service.dart';

/// Local, offline, dev-only [AuthService].
///
/// No real password checking or security — this exists so the app is
/// fully clickable/testable before a real backend exists. It persists
/// which emails have "signed up" (so Login vs Sign Up behave sensibly)
/// but never stores or checks the actual password, matching the mock
/// auth flow the app used before SANA.
///
/// Swap for a Firebase-backed implementation later: same interface,
/// zero changes required in any screen or provider.
class MockAuthService implements AuthService {
  static const _registeredEmailsKey = 'sana_mock_registered_emails';

  Future<Set<String>> _registeredEmails() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_registeredEmailsKey);
    if (raw == null) return {};
    return Set<String>.from(jsonDecode(raw) as List);
  }

  Future<void> _saveRegisteredEmails(Set<String> emails) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_registeredEmailsKey, jsonEncode(emails.toList()));
  }

  String _normalize(String email) => email.trim().toLowerCase();

  @override
  Future<AuthUser> signUp({required String email, required String password}) async {
    final normalized = _normalize(email);
    if (!Validators.isValidEmail(normalized)) {
      throw const AuthException('Enter a valid email address.');
    }
    if (!Validators.isValidPassword(password)) {
      throw const AuthException('Password must be at least 6 characters.');
    }
    final registered = await _registeredEmails();
    if (registered.contains(normalized)) {
      throw const AuthException('An account with this email already exists. Try logging in.');
    }
    registered.add(normalized);
    await _saveRegisteredEmails(registered);
    return AuthUser(id: normalized, email: normalized);
  }

  @override
  Future<AuthUser> login({required String email, required String password}) async {
    final normalized = _normalize(email);
    if (!Validators.isValidEmail(normalized)) {
      throw const AuthException('Enter a valid email address.');
    }
    if (!Validators.isValidPassword(password)) {
      throw const AuthException('Incorrect email or password.');
    }
    final registered = await _registeredEmails();
    if (!registered.contains(normalized)) {
      throw const AuthException('No account found for this email. Try creating one.');
    }
    return AuthUser(id: normalized, email: normalized);
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    final normalized = _normalize(email);
    if (!Validators.isValidEmail(normalized)) {
      throw const AuthException('Enter a valid email address.');
    }
    // Mock: no real email is sent. A real backend implementation replaces this.
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Future<void> updateName({required String token, required String name}) async {
    // No server to sync to — MockAuthService has no backend at all;
    // UserProfileService (local storage) already has the name, which
    // is all this mock's world model consists of.
  }

  @override
  Future<void> logout() async {
    // Nothing to clear — no session token is persisted in V1 (see
    // UserProfileService docs for why the profile itself still is).
  }
}
