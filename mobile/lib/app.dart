import 'package:flutter/material.dart';
import 'package:livekit_components/livekit_components.dart' as components;
import 'package:provider/provider.dart';

import 'controllers/app_ctrl.dart';
import 'screens/agent_screen.dart';
import 'screens/home_shell.dart';
import 'ui/sana_theme.dart';
import 'widgets/app_layout_switcher.dart';
import 'widgets/session_error_banner.dart';

final appCtrl = AppCtrl();

class VoiceAssistantApp extends StatelessWidget {
  const VoiceAssistantApp({super.key});

  @override
  Widget build(BuildContext ctx) => MultiProvider(
        providers: [
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
            themeMode: ThemeMode.dark,
            home: Builder(
              builder: (ctx) => Center(
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
            ),
          ),
        ),
      );
}
