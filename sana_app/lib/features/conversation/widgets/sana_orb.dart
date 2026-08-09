import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../services/voice_service.dart';

/// SANA's central voice/presence indicator. Breathes gently at idle;
/// once [voiceState] reflects a live call, tints and pulse speed shift
/// to match listening (teal) / thinking (neutral) / speaking (violet),
/// giving the states from spec §21 a visual home without a separate
/// waveform widget.
class SanaOrb extends StatefulWidget {
  const SanaOrb({super.key, this.size = 180, this.voiceState});

  final double size;
  final VoiceState? voiceState;

  @override
  State<SanaOrb> createState() => _SanaOrbState();
}

class _SanaOrbState extends State<SanaOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _durationFor(widget.voiceState),
  )..repeat(reverse: true);

  static Duration _durationFor(VoiceState? state) => switch (state) {
        VoiceState.speaking => const Duration(milliseconds: 900),
        VoiceState.listening => const Duration(milliseconds: 1400),
        _ => const Duration(seconds: 3),
      };

  static Color _tintFor(VoiceState? state) => switch (state) {
        VoiceState.listening => AppColors.voiceListening,
        VoiceState.speaking => AppColors.voiceSpeaking,
        VoiceState.thinking || VoiceState.connecting => AppColors.voiceIdle,
        _ => AppColors.primary,
      };

  @override
  void didUpdateWidget(SanaOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceState != widget.voiceState) {
      _controller.duration = _durationFor(widget.voiceState);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tintFor(widget.voiceState);
    final pulseAmount = widget.voiceState == VoiceState.speaking ? 0.06 : 0.035;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (_controller.value * pulseAmount);
        return Transform.scale(scale: scale, child: child);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [tint, const Color(0xFFAAB6FF), const Color(0xFFFAFAFF)],
            stops: const [0.0, 0.55, 1.0],
          ),
          boxShadow: [
            BoxShadow(color: tint.withValues(alpha: 0.30), blurRadius: 44, spreadRadius: 4),
          ],
        ),
      ),
    );
  }
}
