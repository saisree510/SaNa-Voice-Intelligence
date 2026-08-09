import 'auth_service.dart';

/// Persists the logged-in [AuthUser] (id, email, JWT) across app
/// restarts — on web, that includes a plain page reload, which
/// otherwise drops all in-memory state and forces a fresh login every
/// time. Deliberately separate from [UserProfileService]: this is
/// "who's logged in", that's "what do we know about them" — the same
/// split [AuthUser]/[UserProfile] already draw.
abstract interface class SessionStorageService {
  Future<AuthUser?> loadSession();

  Future<void> saveSession(AuthUser user);

  Future<void> clearSession();
}
