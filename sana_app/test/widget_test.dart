// Smoke test: the app boots on splash, then (with no persisted session)
// routes to the combined Log In / Sign Up screen, and the login form
// (default tab) is present.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sana_app/app/app.dart';
import 'package:sana_app/features/auth/auth_provider.dart';
import 'package:sana_app/services/local_session_storage_service.dart';
import 'package:sana_app/services/local_user_profile_service.dart';
import 'package:sana_app/services/mock_auth_service.dart';

void main() {
  testWidgets('SANA boots to splash, then routes to the login screen', (
    WidgetTester tester,
  ) async {
    // Empty, not unset — splash now restores any saved session (see
    // AuthProvider.restoreSession) before this test's real assertion
    // (no session saved => still lands on login), so SharedPreferences
    // needs a real, if empty, backing store instead of throwing.
    SharedPreferences.setMockInitialValues({});

    final authProvider = AuthProvider(
      authService: MockAuthService(),
      profileService: LocalUserProfileService(),
      sessionService: LocalSessionStorageService(),
    );

    await tester.pumpWidget(SanaApp(authProvider: authProvider));

    expect(find.text('SANA'), findsWidgets);
    expect(find.text('Your AI conversation partner'), findsOneWidget);

    // Splash auto-navigates after 900ms. Pumped explicitly (not
    // pumpAndSettle) because the welcome screen's orb animates forever,
    // so there's never a fully "settled" frame to wait for.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });
}
