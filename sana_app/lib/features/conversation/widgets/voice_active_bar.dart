import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../services/voice_service.dart';

/// Replaces the normal input bar while a voice call is active — a live
/// waveform instead of the text field, with a plain cancel (X) and a
/// primary confirm (✓) button instead of a single red phone/hang-up
/// icon. Modeled on the reference the user shared (ChatGPT's dictate
/// UI): tap the mic, speak, tap the checkmark when you're done.
///
/// [onCancel] and [onDone] both end the call the same way underneath
/// — SANA's turn-detector already knows when you've stopped talking
/// and replies in real time, so unlike text dictation there's no
/// separate "transcript ready, confirm to send" step to distinguish
/// between. Kept as two buttons anyway to match the requested look;
/// worth revisiting if that turns out to be confusing rather than just
/// a style preference.
class VoiceActiveBar extends StatelessWidget {
  const VoiceActiveBar({super.key, required this.voiceState, required this.onCancel, required this.onDone});

  final VoiceState voiceState;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              shape: const CircleBorder(),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _Waveform(voiceState: voiceState),
            ),
          ),
          Material(
            color: theme.colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onDone,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.check_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated bar-style waveform. Not driven by real microphone
/// amplitude (that would need mic-level metering wired up separately)
/// — its pulse height/speed reacts to [VoiceState] instead, so it
/// still reads as "calmer while listening, livelier while SANA speaks"
/// rather than a constant idle loop.
class _Waveform extends StatefulWidget {
  const _Waveform({required this.voiceState});

  final VoiceState voiceState;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _colorFor(VoiceState state) => switch (state) {
        VoiceState.listening => AppColors.voiceListening,
        VoiceState.speaking => AppColors.voiceSpeaking,
        _ => AppColors.voiceIdle,
      };

  double _intensityFor(VoiceState state) => switch (state) {
        VoiceState.speaking => 1.0,
        VoiceState.listening => 0.7,
        _ => 0.35,
      };

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(widget.voiceState);
    final intensity = _intensityFor(widget.voiceState);
    return SizedBox(
      height: 32,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(24, (i) {
              final phase = (_controller.value * 2 * math.pi) + (i * 0.5);
              final height = 4 + (math.sin(phase).abs() * 24 * intensity);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 3,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              );
            }),
          );
        },
      ),
    );
  }
}
