import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/auth/auth_provider.dart';
import 'services/local_session_storage_service.dart';
import 'services/local_user_profile_service.dart';
import 'services/real_auth_service.dart';

Future<void> main() async {
  // Restoring the session touches a plugin (shared_preferences) before
  // runApp() -- needs the binding up first.
  WidgetsFlutterBinding.ensureInitialized();

  // Auth now talks to the real sana_backend (see real_auth_service.dart)
  // — was MockAuthService during earlier phases. UserProfileService
  // (name/onboarding) and SessionStorageService (staying logged in
  // across restarts/reloads) both stay local; the backend doesn't
  // model either yet.
  final authProvider = AuthProvider(
    authService: RealAuthService(),
    profileService: LocalUserProfileService(),
    sessionService: LocalSessionStorageService(),
  );

  // Awaited *before* runApp(), not kicked off from a screen's
  // initState — on web, reloading the page can land on any route
  // (whatever the URL bar already said, e.g. /#/home), not just
  // /splash, so a screen-triggered restore would silently never run
  // for most reloads. Doing it here means the router's very first
  // redirect() evaluation already sees the correct restored
  // isLoggedIn/onboardingCompleted state, regardless of which URL the
  // app booted on.
  await authProvider.restoreSession();

  runApp(SanaApp(authProvider: authProvider));
}
