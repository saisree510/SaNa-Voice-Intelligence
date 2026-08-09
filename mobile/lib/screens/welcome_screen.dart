import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;
import '../controllers/app_ctrl.dart' as ctrl;
import '../widgets/agent_status_indicator.dart';
import '../widgets/button.dart' as buttons;

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext ctx) => Material(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 30,
              children: [
                Image.asset(
                  'assets/terminal.png',
                  width: 80,
                  height: 80,
                  color: Theme.brightnessOf(ctx) == Brightness.light ? Colors.black : Colors.white,
                ),
                Text.rich(
                  textAlign: TextAlign.center,
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Start a call to chat with your voice agent. Need help getting set up? Check out the ',
                      ),
                      TextSpan(
                        text: 'Voice AI quickstart',
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.blue,
                          decorationThickness: 1,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () async {
                            await launchUrl(Uri.parse('https://docs.livekit.io/agents/start/voice-ai/'));
                          },
                      ),
                      const TextSpan(
                        text: '.',
                      ),
                    ],
                  ),
                ),
                Consumer<ctrl.AppCtrl>(
                  builder: (ctx, appCtrl, child) {
                    // Only show agent status while a connect is actually in progress.
                    // Avoids stale "Agent is listening" on a stuck welcome screen.
                    if (!appCtrl.isConnecting) {
                      return const SizedBox.shrink();
                    }
                    return const AgentStatusIndicator();
                  },
                ),
                Consumer2<ctrl.AppCtrl, sdk.Session>(
                  builder: (ctx, appCtrl, session, child) {
                    final isConnecting = appCtrl.isConnecting;
                    final isLive = session.connectionState == sdk.ConnectionState.connected ||
                        session.connectionState == sdk.ConnectionState.reconnecting;

                    late final String label;
                    late final VoidCallback onPressed;
                    if (isConnecting) {
                      label = 'Cancel';
                      onPressed = () => appCtrl.cancelConnect();
                    } else if (isLive) {
                      label = 'Continue call';
                      onPressed = () => appCtrl.connect();
                    } else {
                      label = 'Start call';
                      onPressed = () => appCtrl.connect();
                    }

                    return buttons.Button(
                      text: label,
                      isProgressing: isConnecting,
                      enabled: true,
                      onPressed: onPressed,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
}
