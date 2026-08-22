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
import '../widgets/architecture_canvas_panel.dart';
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
                  final orbSize = compact ? (maxSide * 0.7).clamp(64.0, 120.0) : (maxSide * 0.55).clamp(160.0, 280.0);

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
          builder: (ctx, agentLayoutState, child) => Stack(
            children: [
              ColoredBox(
                color: SanaColors.nearBlack,
                child: _buildLayoutSwitcher(ctx, agentLayoutState),
              ),
              Positioned(
                top: MediaQuery.paddingOf(ctx).top + 8,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => ctx.read<AppCtrl>().disconnect(),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: SanaColors.lavender.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: SanaColors.lavender.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        ctx.watch<AppCtrl>().conversationMode.label.toUpperCase(),
                        style: const TextStyle(
                          color: SanaColors.lavender,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
            child: _ConversationCanvasWorkspace(
              conversationBuilder: (context, viewCanvas) => Column(
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
                          return ConversationSheet(
                            turns: timeline.turns,
                            showCanvasActivityCards: ctx.watch<AppCtrl>().conversationMode == ConversationMode.build,
                            onViewCanvas: viewCanvas,
                          );
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
            ),
          );
        },
      );
}

class _ConversationCanvasWorkspace extends StatefulWidget {
  const _ConversationCanvasWorkspace({required this.conversationBuilder});

  final Widget Function(BuildContext context, VoidCallback viewCanvas) conversationBuilder;

  @override
  State<_ConversationCanvasWorkspace> createState() => _ConversationCanvasWorkspaceState();
}

class _ConversationCanvasWorkspaceState extends State<_ConversationCanvasWorkspace> {
  double _conversationFraction = 0.42;
  bool _isCanvasCollapsed = false;
  bool _isCanvasFullscreen = false;

  void _showCanvas({TabController? tabController}) {
    setState(() {
      _isCanvasCollapsed = false;
      _isCanvasFullscreen = false;
    });
    tabController?.animateTo(1);
  }

  void _toggleCanvasCollapsed() {
    setState(() {
      _isCanvasCollapsed = !_isCanvasCollapsed;
      if (_isCanvasCollapsed) _isCanvasFullscreen = false;
    });
  }

  void _toggleCanvasFullscreen() {
    setState(() {
      _isCanvasFullscreen = !_isCanvasFullscreen;
      if (_isCanvasFullscreen) _isCanvasCollapsed = false;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 980;
          if (!isWide) {
            _isCanvasCollapsed = false;
            _isCanvasFullscreen = false;
            return DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: SanaColors.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: SanaColors.outline),
                      ),
                      child: const TabBar(
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          color: SanaColors.lavender,
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                        ),
                        labelColor: SanaColors.pureWhite,
                        unselectedLabelColor: SanaColors.fgSecondary,
                        tabs: [
                          Tab(text: 'Conversation'),
                          Tab(text: 'Canvas'),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Builder(
                          builder: (tabContext) => widget.conversationBuilder(
                            tabContext,
                            () => _showCanvas(tabController: DefaultTabController.maybeOf(tabContext)),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: ArchitectureCanvasPanel(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LayoutBuilder(
              builder: (context, innerConstraints) {
                if (_isCanvasFullscreen) {
                  return ArchitectureCanvasPanel(
                    isFullscreen: true,
                    onFullscreen: _toggleCanvasFullscreen,
                  );
                }

                final availableWidth = innerConstraints.maxWidth;
                final conversationWidth =
                    (_isCanvasCollapsed ? availableWidth - 64 : availableWidth * _conversationFraction)
                        .clamp(340.0, availableWidth - 430.0);

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: conversationWidth,
                      child: widget.conversationBuilder(context, _showCanvas),
                    ),
                    if (_isCanvasCollapsed) ...[
                      const SizedBox(width: 12),
                      _CollapsedCanvasRail(onTap: _toggleCanvasCollapsed),
                    ] else ...[
                      _CanvasResizeHandle(
                        onDrag: (delta) {
                          setState(() {
                            _conversationFraction =
                                (_conversationFraction + (delta / availableWidth)).clamp(0.28, 0.62);
                          });
                        },
                      ),
                      Expanded(
                        child: ArchitectureCanvasPanel(
                          onCollapse: _toggleCanvasCollapsed,
                          onFullscreen: _toggleCanvasFullscreen,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      );
}

class _CanvasResizeHandle extends StatelessWidget {
  const _CanvasResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: SizedBox(
            width: 18,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: SanaColors.lavender.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const SizedBox(width: 4, height: 74),
              ),
            ),
          ),
        ),
      );
}

class _CollapsedCanvasRail extends StatelessWidget {
  const _CollapsedCanvasRail({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: SanaColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: SizedBox(
            width: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_tree_rounded, color: SanaColors.lavenderDeep),
                const SizedBox(height: 10),
                RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    'Canvas',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: SanaColors.lavenderDeep,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
          'Speak with Soul, or type below. Conversation appears here.',
          style: textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
