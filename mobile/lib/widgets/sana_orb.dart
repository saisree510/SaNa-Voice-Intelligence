import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/sana_orb_state.dart';
import '../ui/sana_theme.dart';

/// Organic muted-lavender SaNa orb. Motion differs by [SanaOrbState].
class SanaOrb extends StatefulWidget {
  const SanaOrb({
    super.key,
    required this.state,
    this.size = 220,
    this.onTap,
    this.showLabel = true,
  });

  final SanaOrbState state;
  final double size;
  final VoidCallback? onTap;
  final bool showLabel;

  @override
  State<SanaOrb> createState() => _SanaOrbState();
}

class _SanaOrbState extends State<SanaOrb> with TickerProviderStateMixin {
  late final AnimationController _breathe;
  late final AnimationController _pulse;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 9000));
    _syncMotion(widget.state);
  }

  @override
  void didUpdateWidget(covariant SanaOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncMotion(widget.state);
    }
  }

  void _syncMotion(SanaOrbState state) {
    final (breatheMs, pulseMs) = switch (state) {
      SanaOrbState.idle => (3600, 2200),
      SanaOrbState.connecting || SanaOrbState.reconnecting => (1800, 900),
      SanaOrbState.listening => (2800, 1600),
      SanaOrbState.userSpeaking => (1600, 700),
      SanaOrbState.thinking => (2400, 1200),
      SanaOrbState.speaking => (1200, 550),
      SanaOrbState.error => (2400, 2200),
    };

    _breathe.duration = Duration(milliseconds: breatheMs);
    _pulse.duration = Duration(milliseconds: pulseMs);
    if (state == SanaOrbState.thinking) {
      _spin.duration = const Duration(milliseconds: 7000);
    }

    unawaited(_breathe.repeat(reverse: true));
    if (state == SanaOrbState.error) {
      _pulse.stop();
      _pulse.value = 0.2;
    } else {
      unawaited(_pulse.repeat(reverse: true));
    }
    if (state == SanaOrbState.thinking && !_spin.isAnimating) {
      unawaited(_spin.repeat());
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orb = Semantics(
      button: widget.onTap != null,
      label: 'Sana voice orb, ${widget.state.statusLabel}',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_breathe, _pulse, _spin]),
          builder: (context, _) {
            return CustomPaint(
              painter: _SanaOrbPainter(
                state: widget.state,
                breathe: _breathe.value,
                pulse: _pulse.value,
                spin: _spin.value,
              ),
            );
          },
        ),
      ),
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onTap != null)
            GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: orb,
            )
          else
            orb,
          if (widget.showLabel) ...[
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                widget.state.statusLabel,
                key: ValueKey(widget.state),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: SanaColors.fgSecondary,
                      letterSpacing: 0.2,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SanaOrbPainter extends CustomPainter {
  _SanaOrbPainter({
    required this.state,
    required this.breathe,
    required this.pulse,
    required this.spin,
  });

  final SanaOrbState state;
  final double breathe;
  final double pulse;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.shortestSide * 0.28;
    final intensity = switch (state) {
      SanaOrbState.idle => 0.35,
      SanaOrbState.connecting || SanaOrbState.reconnecting => 0.7,
      SanaOrbState.listening => 0.5,
      SanaOrbState.userSpeaking => 0.85,
      SanaOrbState.thinking => 0.65,
      SanaOrbState.speaking => 1.0,
      SanaOrbState.error => 0.4,
    };

    final coreColor = state == SanaOrbState.error ? SanaColors.danger : SanaColors.lavender;
    final deepColor = state == SanaOrbState.error ? const Color(0xFF5A2E2A) : SanaColors.lavenderDeep;

    // Organic blob body
    final path = _organicPath(
      center: center,
      radius: baseRadius * (0.92 + breathe * 0.06 + pulse * 0.04 * intensity),
      spin: spin,
      wobble: 0.08 + intensity * 0.06,
    );

    final gradient = RadialGradient(
      colors: [
        coreColor.withValues(alpha: 0.95),
        coreColor.withValues(alpha: 0.72),
        deepColor.withValues(alpha: 0.85),
        SanaColors.lavenderDeep.withValues(alpha: 0.9),
      ],
      stops: const [0.0, 0.35, 0.7, 1.0],
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = gradient.createShader(Rect.fromCircle(center: center, radius: baseRadius * 1.4))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );

    // Thinking: slow rotating arc accent
    if (state == SanaOrbState.thinking) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = coreColor.withValues(alpha: 0.55);
      final rect = Rect.fromCircle(center: center, radius: baseRadius * 1.15);
      canvas.drawArc(rect, spin * math.pi * 2, math.pi * 0.7, false, arcPaint);
    }
  }

  Path _organicPath({
    required Offset center,
    required double radius,
    required double spin,
    required double wobble,
  }) {
    final path = Path();
    const points = 48;
    for (var i = 0; i <= points; i++) {
      final t = i / points;
      final angle = t * math.pi * 2;
      final n1 = math.sin(angle * 3 + spin * math.pi * 2);
      final n2 = math.cos(angle * 5 - spin * math.pi * 2 * 0.7);
      final r = radius * (1 + wobble * (0.55 * n1 + 0.45 * n2));
      final x = center.dx + math.cos(angle) * r;
      final y = center.dy + math.sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _SanaOrbPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.breathe != breathe ||
        oldDelegate.pulse != pulse ||
        oldDelegate.spin != spin;
  }
}
