import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_components/livekit_components.dart' as components;
import 'package:provider/provider.dart';

import 'controllers/app_ctrl.dart';
import 'screens/agent_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'ui/sana_theme.dart';
import 'widgets/app_layout_switcher.dart';
import 'widgets/session_error_banner.dart';

final appCtrl = AppCtrl();
final authService = AuthService();

class VoiceAssistantApp extends StatelessWidget {
  const VoiceAssistantApp({super.key});

  @override
  Widget build(BuildContext ctx) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: authService),
          ChangeNotifierProvider.value(value: appCtrl),
          ChangeNotifierProvider.value(value: appCtrl.session),
          ChangeNotifierProvider.value(value: appCtrl.roomContext),
          ChangeNotifierProvider.value(value: appCtrl.conversationTimeline),
        ],
        child: components.SessionContext(
          session: appCtrl.session,
          child: MaterialApp(
            title: 'Sana',
            theme: buildSanaTheme(),
            darkTheme: buildSanaTheme(),
            themeMode: ThemeMode.light,
            home: const AuthGate(),
          ),
        ),
      );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<AuthService>().initialize());
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    if (!authService.isInitialized) {
      return const Scaffold(
        backgroundColor: SanaColors.nearBlack,
        body: Center(
          child: CircularProgressIndicator(
            color: SanaColors.lavender,
          ),
        ),
      );
    }

    if (!authService.isAuthenticated) {
      return const AuthScreen();
    }

    if (!authService.hasCompletedOnboarding) {
      return const OnboardingScreen();
    }

    // Sync authenticated user display name to AppCtrl for greeting line
    final appCtrl = context.read<AppCtrl>();
    appCtrl.updateUserName(authService.userName);

    return Scaffold(
      backgroundColor: SanaColors.nearBlack,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Stack(
            children: [
              Selector<AppCtrl, AppScreenState>(
                selector: (ctx, appCtx) => appCtx.appScreenState,
                builder: (ctx, screen, _) => AppLayoutSwitcher(
                  frontBuilder: (ctx) => const HomeShell(),
                  backBuilder: (ctx) => const AgentScreen(),
                  isFront: screen == AppScreenState.welcome,
                ),
              ),
              const SessionErrorBanner(),
            ],
          ),
        ),
      ),
    );
  }
}
