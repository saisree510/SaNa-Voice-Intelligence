import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:livekit_components/livekit_components.dart' as components;
import 'package:provider/provider.dart';

import '../controllers/app_ctrl.dart';
import '../exts.dart';
import '../models/sana_orb_state.dart';
import '../support/agent_selector.dart';
import 'sana_orb.dart';

/// Orb bound to the live LiveKit session / agent participant state.
class SanaOrbView extends StatelessWidget {
  const SanaOrbView({
    super.key,
    this.size = 220,
    this.onTap,
    this.showLabel = true,
    this.forceState,
  });

  final double size;
  final VoidCallback? onTap;
  final bool showLabel;

  /// When set (e.g. idle home before connect), overrides live mapping.
  final SanaOrbState? forceState;

  @override
  Widget build(BuildContext context) {
    if (forceState != null) {
      return SanaOrb(
        state: forceState!,
        size: size,
        onTap: onTap,
        showLabel: showLabel,
      );
    }

    return Consumer2<AppCtrl, sdk.Session>(
      builder: (context, appCtrl, session, _) {
        return AgentParticipantSelector(
          builder: (context, agentParticipant) {
            return ListenableBuilder(
              listenable: Listenable.merge([
                if (agentParticipant != null) agentParticipant,
                session,
              ]),
              builder: (context, _) {
                final roomCtx = context.watch<components.RoomContext>();
                final localSpeaking = roomCtx.localParticipant?.isSpeaking ?? false;
                final agentState = agentParticipant?.agentState;

                final orbState = resolveSanaOrbState(
                  connectionState:
                      appCtrl.isSessionStarting && session.connectionState == sdk.ConnectionState.disconnected
                          ? sdk.ConnectionState.connecting
                          : session.connectionState,
                  sessionHasError: session.error != null,
                  agentHasError: session.agent.error != null,
                  agentIsPending: session.agent.isPending,
                  agentIsBuffering: session.agent.isBuffering,
                  agentIsConnected: session.agent.isConnected,
                  agentState: agentState,
                  localParticipantSpeaking: localSpeaking,
                );

                return SanaOrb(
                  state: orbState,
                  size: size,
                  onTap: onTap,
                  showLabel: showLabel,
                );
              },
            );
          },
        );
      },
    );
  }
}
