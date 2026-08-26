/// Route path constants, used by [go_router] config and any `context.go(...)`
/// call. Centralized so a path never gets typo'd across features.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String onboarding = '/onboarding';

  /// The tabbed Debate/Brainstorm/Build workspace — the direct
  /// post-login landing screen (no separate mode-picker screen before
  /// it; tabs inside this screen switch modes instead).
  static const String home = '/home';

  static const String profile = '/profile';
  static const String settings = '/settings';
}
