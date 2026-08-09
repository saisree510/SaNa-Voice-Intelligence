import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:livekit_components/livekit_components.dart' as components;
import 'package:provider/provider.dart';

import '../controllers/app_ctrl.dart';
import '../controllers/conversation_timeline.dart';
import '../support/agent_selector.dart';
import '../ui/sana_theme.dart';
import '../widgets/agent_layout_switcher.dart';
import '../widgets/camera_toggle_button.dart';
import '../widgets/conversation_sheet.dart';
import '../widgets/message_bar.dart';
import '../widgets/sana_orb_view.dart';

class AgentTrackView extends StatelessWidget {
  const AgentTrackView({super.key, this.compact = false});

  /// Smaller orb when conversation sheet is open (avoids layout overflow).
  final bool compact;

  @override
  Widget build(BuildContext context) => AgentParticipantSelector(
        builder: (ctx, agentParticipant) => Selector<components.ParticipantContext?, sdk.TrackPublication?>(
          selector: (ctx, agentCtx) {
            final videoTrack = agentCtx?.tracks.where((t) => t.kind == sdk.TrackType.VIDEO).firstOrNull;
            final audioTrack = agentCtx?.tracks.where((t) => t.kind == sdk.TrackType.AUDIO).firstOrNull;
            // Prioritize video track
            return videoTrack ?? audioTrack;
          },
          builder: (ctx, mediaTrack, child) => ChangeNotifierProvider<components.TrackReferenceContext?>.value(
            value:
                agentParticipant == null ? null : components.TrackReferenceContext(agentParticipant, pub: mediaTrack),
            child: Builder(
              builder: (ctx) => LayoutBuilder(
                builder: (ctx, constraints) {
                  final trackReferenceContext = ctx.watch<components.TrackReferenceContext?>();

                  if (trackReferenceContext?.isVideo ?? false) {
                    return const components.VideoTrackWidget();
                  }

                  final maxSide = constraints.biggest.shortestSide;
                  final orbSize = compact
                      ? (maxSide * 0.7).clamp(64.0, 120.0)
                      : (maxSide * 0.55).clamp(160.0, 280.0);

                  return Center(
                    child: SanaOrbView(
                      size: orbSize,
                      showLabel: !compact,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
}

class FrontView extends StatelessWidget {
  final AgentScreenState screenState;

  const FrontView({
    super.key,
    required this.screenState,
  });

  @override
  Widget build(BuildContext context) => components.MediaDeviceContextBuilder(
        builder: (context, roomCtx, mediaDeviceCtx) => Row(
          spacing: 20,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Flexible(
              flex: 2,
              fit: FlexFit.tight,
              child: AgentTrackView(),
            ),
            if (screenState == AgentScreenState.transcription && mediaDeviceCtx.cameraOpened)
              Flexible(
                fit: FlexFit.tight,
                child: AnimatedOpacity(
                  opacity: (screenState == AgentScreenState.transcription && mediaDeviceCtx.cameraOpened) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(15)),
                    child: components.ParticipantSelector(
                      filter: (identifier) => identifier.isVideo && identifier.isLocal,
                      builder: (context, identifier) => components.VideoTrackWidget(
                        fit: sdk.VideoViewFit.cover,
                        noTrackBuilder: (ctx) => Container(color: Theme.of(ctx).cardColor),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class AgentScreen extends StatelessWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext ctx) => Material(
        child: Selector<AppCtrl, AgentLayoutState>(
          selector: (ctx, appCtrl) => AgentLayoutState(
            isTranscriptionVisible: appCtrl.agentScreenState == AgentScreenState.transcription,
            isCameraVisible: appCtrl.isUserCameEnabled,
            isScreenshareVisible: appCtrl.isScreenshareEnabled,
          ),
          builder: (ctx, agentLayoutState, child) => ColoredBox(
            color: SanaColors.nearBlack,
            child: _buildLayoutSwitcher(ctx, agentLayoutState),
          ),
        ),
      );

  Widget _buildLayoutSwitcher(BuildContext ctx, AgentLayoutState agentLayoutState) => AgentLayoutSwitcher(
        layoutState: agentLayoutState,
        buildAgentView: (ctx) => AgentTrackView(compact: agentLayoutState.isTranscriptionVisible),
        buildCameraView: (ctx) => Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
          ),
          child: components.MediaDeviceContextBuilder(
            builder: (context, roomCtx, mediaDeviceCtx) => components.ParticipantSelector(
              filter: (identifier) => identifier.isVideo && identifier.isLocal,
              builder: (context, identifier) => Stack(
                children: [
                  components.VideoTrackWidget(
                    fit: sdk.VideoViewFit.cover,
                    noTrackBuilder: (ctx) => Container(color: Theme.of(ctx).cardColor),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: CameraToggleButton(
                      onTap: () => mediaDeviceCtx.toggleCameraPosition(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        buildScreenShareView: (ctx) => Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.3),
          ),
          child: const Text('Screenshare View'),
        ),
        transcriptionsBuilder: (ctx) {
          final keyboardInset = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: keyboardInset > 0 ? max(0, keyboardInset - 90) : 0),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => ctx.read<AppCtrl>().messageFocusNode.unfocus(),
                    child: Consumer<ConversationTimeline>(
                      builder: (context, timeline, _) {
                        if (!timeline.hasTurns) {
                          return const _AgentStatusPlaceholder();
                        }
                        return ConversationSheet(turns: timeline.turns);
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Selector<AppCtrl, bool>(
                    selector: (ctx, appCtx) => appCtx.isSendButtonEnabled,
                    builder: (ctx, isSendEnabled, child) => MessageBar(
                      focusNode: ctx.read<AppCtrl>().messageFocusNode,
                      isSendEnabled: isSendEnabled,
                      controller: ctx.read<AppCtrl>().messageCtrl,
                      onSendTap: () => ctx.read<AppCtrl>().sendMessage(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _AgentStatusPlaceholder extends StatelessWidget {
  const _AgentStatusPlaceholder();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Speak with Sana, or type below. Conversation appears here.',
          style: textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
