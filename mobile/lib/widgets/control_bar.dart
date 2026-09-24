import 'package:flutter/material.dart';
import 'package:flutter_sficon/flutter_sficon.dart' as sf;
import 'package:livekit_components/livekit_components.dart' as components;
import 'package:provider/provider.dart';

import '../app.dart';
import '../controllers/app_ctrl.dart' show AppCtrl, AgentScreenState;
import '../ui/sana_theme.dart';
import 'floating_glass.dart';

class ControlBar extends StatelessWidget {
  const ControlBar({super.key, this.buildMode = false});

  final bool buildMode;

  @override
  Widget build(BuildContext ctx) => FloatingGlassView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 10,
          ),
          child: buildMode ? _BuildControls() : _StandardControls(),
        ),
      );
}

class _BuildControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          SizedBox(width: 52, child: _MicrophoneControl()),
          Selector<AppCtrl, bool>(
            selector: (ctx, appCtrl) => appCtrl.isBuildConversationVisible,
            builder: (context, isVisible, _) => SizedBox(
              width: 52,
              child: FloatingGlassButton(
                isActive: isVisible,
                sfIcon: sf.SFIcons.sf_ellipsis_message_fill,
                onTap: () => context.read<AppCtrl>().toggleBuildConversationVisibility(),
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: FloatingGlassButton(
              iconColor: SanaColors.danger,
              sfIcon: sf.SFIcons.sf_power_circle_fill,
              onTap: () => context.read<AppCtrl>().disconnect(),
            ),
          ),
        ],
      );
}

class _StandardControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
        spacing: 5,
        children: [
          const Flexible(flex: 1, fit: FlexFit.tight, child: _MicrophoneControl()),
          Flexible(
            flex: 1,
            fit: FlexFit.tight,
            child: components.MediaDeviceContextBuilder(
              builder: (context, roomCtx, mediaDeviceCtx) => FloatingGlassButton(
                sfIcon: mediaDeviceCtx.cameraOpened ? sf.SFIcons.sf_video_fill : sf.SFIcons.sf_video_slash_fill,
                onTap: () => appCtrl.toggleUserCamera(mediaDeviceCtx),
              ),
            ),
          ),
          const Flexible(
            flex: 1,
            fit: FlexFit.tight,
            child: FloatingGlassButton(sfIcon: sf.SFIcons.sf_arrow_up_square_fill),
          ),
          Selector<AppCtrl, AgentScreenState>(
            selector: (ctx, appCtrl) => appCtrl.agentScreenState,
            builder: (context, screenState, _) => Flexible(
              flex: 1,
              fit: FlexFit.tight,
              child: FloatingGlassButton(
                isActive: screenState == AgentScreenState.transcription,
                sfIcon: sf.SFIcons.sf_ellipsis_message_fill,
                onTap: () => context.read<AppCtrl>().toggleAgentScreenMode(),
              ),
            ),
          ),
          Flexible(
            flex: 1,
            fit: FlexFit.tight,
            child: FloatingGlassButton(
              iconColor: SanaColors.danger,
              sfIcon: sf.SFIcons.sf_phone_down_fill,
              onTap: () => context.read<AppCtrl>().disconnect(),
            ),
          ),
        ],
      );
}

class _MicrophoneControl extends StatelessWidget {
  const _MicrophoneControl();

  @override
  Widget build(BuildContext context) => components.MediaDeviceContextBuilder(
        builder: (context, roomCtx, mediaDeviceCtx) => FloatingGlassButton(
          sfIcon: mediaDeviceCtx.microphoneOpened ? sf.SFIcons.sf_microphone_fill : sf.SFIcons.sf_microphone_slash_fill,
          subWidget: components.ParticipantSelector(
            filter: (identifier) => identifier.isAudio && identifier.isLocal,
            builder: (context, identifier) => const SizedBox(
              width: 15,
              height: 15,
              child: components.AudioVisualizerWidget(
                options: components.AudioVisualizerWidgetOptions(barCount: 5, spacing: 1),
              ),
            ),
          ),
          onTap: () =>
              mediaDeviceCtx.microphoneOpened ? mediaDeviceCtx.disableMicrophone() : mediaDeviceCtx.enableMicrophone(),
        ),
      );
}
