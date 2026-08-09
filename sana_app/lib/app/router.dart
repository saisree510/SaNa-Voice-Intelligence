import 'package:go_router/go_router.dart';

import '../core/constants/app_modes.dart';
import '../core/constants/app_routes.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/auth/widgets/auth_tab_toggle.dart';
import '../features/conversation/unified_conversation_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/settings_screen.dart';

/// SANA's top-level route table.
///
/// `redirect` is the single place that decides splash → login →
/// onboarding → home, driven entirely by [AuthProvider] state (passed
/// in as [authProvider] and wired as `refreshListenable` so the router
/// re-evaluates automatically on every login/logout/onboarding change —
/// no screen has to manually navigate after those actions).
///
/// [AppRoutes.home] is the tabbed Debate/Brainstorm/Build workspace
/// directly — there's no separate mode-picker screen before it.
GoRouter buildRouter(AuthProvider authProvider) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: authProvider,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc == AppRoutes.splash) return null; // splash drives its own timed navigation

      final authScreens = {AppRoutes.login, AppRoutes.signup, AppRoutes.forgotPassword};

      if (!authProvider.isLoggedIn) {
        return authScreens.contains(loc) ? null : AppRoutes.login;
      }
      if (!authProvider.onboardingCompleted) {
        return loc == AppRoutes.onboarding ? null : AppRoutes.onboarding;
      }
      if (authScreens.contains(loc) || loc == AppRoutes.onboarding) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const WelcomeScreen(initialTab: WelcomeTab.signUp),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => UnifiedConversationScreen(initialModeId: AppModes.all.first.id),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
