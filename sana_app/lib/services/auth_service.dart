/// A logged-in SANA user. Deliberately minimal — just enough for the app
/// to know who's asking. [id] is a stable identifier ([UserProfileService]
/// keys profiles by it.
///
/// [token] is the backend's JWT (null for the mock implementation,
/// which has no server to authenticate against) — kept here rather
/// than as separate app state since it's 1:1 with "who's logged in".
class AuthUser {
  const AuthUser({required this.id, required this.email, this.token});

  final String id;
  final String email;
  final String? token;
}

/// Auth boundary the rest of the app talks to. [MockAuthService] is V1's
/// implementation (local, offline, dev-only); a Firebase-backed
/// implementation can later satisfy this same interface with no changes
/// to any screen or provider that depends on it.
abstract interface class AuthService {
  Future<AuthUser> signUp({required String email, required String password});

  Future<AuthUser> login({required String email, required String password});

  /// Mock: doesn't send a real email. Real implementation will.
  Future<void> sendPasswordReset({required String email});

  Future<void> logout();
}
