import 'package:flutter/foundation.dart';

import '../../core/errors/error_display.dart';
import '../../services/auth_service.dart';
import '../../services/session_storage_service.dart';
import '../../services/user_profile_service.dart';

/// App-wide auth/profile state.
///
/// This is what [appRouter]'s `redirect` reads to decide splash → login
/// → onboarding → home, and what auth/onboarding/home screens read and
/// call into. Kept as the single source of truth so those three don't
/// each track their own copy of "am I logged in".
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required AuthService authService,
    required UserProfileService profileService,
    required SessionStorageService sessionService,
  })  : _authService = authService,
        _profileService = profileService,
        _sessionService = sessionService;

  final AuthService _authService;
  final UserProfileService _profileService;
  final SessionStorageService _sessionService;
  // Kept as assigned-in-initializer (not `this._authService`) so the
  // constructor signature stays named-parameter-only for readability.

  AuthUser? _user;
  UserProfile? _profile;
  bool _isLoading = false;
  String? _errorMessage;
  bool _justCompletedOnboarding = false;

  AuthUser? get user => _user;
  UserProfile? get profile => _profile;
  bool get isLoggedIn => _user != null;

  /// The backend JWT for the current session, if any — what
  /// [RealConversationService] sends as `Authorization: Bearer <token>`.
  String? get authToken => _user?.token;
  bool get onboardingCompleted => _profile?.onboardingCompleted ?? false;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// True exactly once, right after onboarding finishes — lets the home
  /// screen say "Hi Navya!" instead of "welcome back" on that first
  /// visit. Reading it resets it, so it won't fire again this session.
  bool consumeJustCompletedOnboarding() {
    final value = _justCompletedOnboarding;
    _justCompletedOnboarding = false;
    return value;
  }

  /// Restores a previously logged-in session from on-device storage, if
  /// one was saved — awaited in `main()` *before* `runApp()`, not
  /// triggered by a screen's `initState`: on web, reloading the page
  /// can land on any route (whatever the URL bar already said), not
  /// just /splash, so a screen-triggered restore would silently never
  /// run for most reloads. Doing it before the app even builds means
  /// the router's very first redirect already sees the correct
  /// restored state. Silently a no-op if nothing was stored or
  /// restoring fails for any reason; worst case the user just sees the
  /// ordinary login screen, not a crash.
  Future<void> restoreSession() async {
    try {
      final restoredUser = await _sessionService.loadSession();
      if (restoredUser == null) return;
      _user = restoredUser;
      _profile = await _profileService.loadProfile(restoredUser.id) ?? UserProfile(userId: restoredUser.id);
      notifyListeners();
    } catch (_) {
      // Corrupted/unreadable stored session — fall back to a normal
      // login rather than taking startup down with it.
    }
  }

  Future<bool> login({required String email, required String password}) => _run(() async {
        _user = await _authService.login(email: email, password: password);
        _profile = await _profileService.loadProfile(_user!.id) ??
            UserProfile(userId: _user!.id);
        await _sessionService.saveSession(_user!);
      });

  Future<bool> signUp({required String email, required String password}) => _run(() async {
        _user = await _authService.signUp(email: email, password: password);
        _profile = UserProfile(userId: _user!.id);
        await _sessionService.saveSession(_user!);
      });

  Future<bool> sendPasswordReset({required String email}) =>
      _run(() => _authService.sendPasswordReset(email: email));

  Future<bool> completeOnboarding(String name) => _run(() async {
        // Backend first: if this fails, the whole call fails and
        // _run() surfaces errorMessage instead of quietly finishing
        // onboarding with a name only this device knows — which is
        // exactly the bug this fixes (SANA insisting it doesn't know
        // your name even after you told the app).
        await _authService.updateName(token: authToken!, name: name);
        final updated = _profile!.copyWith(name: name, onboardingCompleted: true);
        await _profileService.saveProfile(updated);
        _profile = updated;
        _justCompletedOnboarding = true;
      });

  Future<void> logout() async {
    await _authService.logout();
    await _sessionService.clearSession();
    _user = null;
    _profile = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = errorMessageFor(e);
      notifyListeners();
      return false;
    }
  }
}
