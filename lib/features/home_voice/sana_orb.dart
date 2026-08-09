import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/sana_colors.dart';
import 'orb_state.dart';

/// Soft translucent muted-lavender glass/silk orb.
/// Layers are lavender material folds — not dark concentric rings.
class SanaOrb extends StatefulWidget {
  const SanaOrb({super.key, required this.state, this.size = 240, this.onTap});

  final SanaOrbState state;
  final double size;
  final VoidCallback? onTap;

  @override
  State<SanaOrb> createState() => _SanaOrbState();
}

class _SanaOrbState extends State<SanaOrb> with TickerProviderStateMixin {
  late final AnimationController _breathe;
  late final AnimationController _flow;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat(reverse: true);
    _flow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant SanaOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncControllers();
    }
  }

  void _syncControllers() {
    switch (widget.state) {
      case SanaOrbState.idle:
        _breathe
          ..duration = const Duration(milliseconds: 3600)
          ..repeat(reverse: true);
        _flow
          ..duration = const Duration(milliseconds: 11000)
          ..repeat();
      case SanaOrbState.listening:
      case SanaOrbState.userSpeaking:
        _breathe
          ..duration = const Duration(milliseconds: 1900)
          ..repeat(reverse: true);
        _flow
          ..duration = const Duration(milliseconds: 7500)
          ..repeat();
      case SanaOrbState.thinking:
      case SanaOrbState.connecting:
      case SanaOrbState.reconnecting:
        _breathe
          ..duration = const Duration(milliseconds: 1700)
          ..repeat(reverse: true);
        _flow
          ..duration = const Duration(milliseconds: 5200)
          ..repeat();
      case SanaOrbState.speaking:
        _breathe
          ..duration = const Duration(milliseconds: 1300)
          ..repeat(reverse: true);
        _flow
          ..duration = const Duration(milliseconds: 6200)
          ..repeat();
      case SanaOrbState.error:
        _breathe
          ..duration = const Duration(milliseconds: 2400)
          ..repeat(reverse: true);
        _flow.stop();
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: 'SaNa voice orb, ${widget.state.label}',
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_breathe, _flow]),
            builder: (context, _) {
              final breathe = switch (widget.state) {
                SanaOrbState.listening ||
                SanaOrbState.userSpeaking => 0.985 + (_breathe.value * 0.035),
                SanaOrbState.speaking => 0.98 + (_breathe.value * 0.04),
                _ => 0.99 + (_breathe.value * 0.02),
              };
              final flow = _flow.isAnimating ? _flow.value : 0.0;

              return CustomPaint(
                painter: _SilkOrbPainter(
                  breathe: breathe,
                  flow: flow,
                  state: widget.state,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SilkOrbPainter extends CustomPainter {
  _SilkOrbPainter({
    required this.breathe,
    required this.flow,
    required this.state,
  });

  final double breathe;
  final double flow;
  final SanaOrbState state;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Fill most of the widget — avoid a tiny center inside empty rings.
    final base = size.shortestSide * 0.46 * breathe;
    final phase = flow * math.pi * 2;

    // Soft close ambient glow only (lavender, low opacity, near the orb).
    final glowColor = state == SanaOrbState.error
        ? SanaColors.danger
        : SanaColors.glow;
    canvas.drawCircle(
      center,
      base * 1.08,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
        ..color = glowColor.withValues(alpha: 0.16),
    );

    // 6 overlapping translucent lavender material folds.
    // Outer → inner: lavender folds form the silhouette (no dark rings).
    _drawFold(
      canvas,
      center: center.translate(base * 0.02, -base * 0.01),
      radius: base * 1.0,
      phase: phase * 0.7,
      rotation: phase * 0.15,
      colors: [
        SanaColors.lavender.withValues(alpha: 0.22),
        SanaColors.lavenderLight.withValues(alpha: 0.28),
        SanaColors.lavender.withValues(alpha: 0.18),
        SanaColors.violetDeep.withValues(alpha: 0.08),
      ],
      lobeAmp: 0.07,
      lobes: 5,
    );
    _drawFold(
      canvas,
      center: center.translate(-base * 0.04, base * 0.03),
      radius: base * 0.92,
      phase: phase + 0.8,
      rotation: -phase * 0.2,
      colors: [
        SanaColors.lavenderLight.withValues(alpha: 0.34),
        SanaColors.lavender.withValues(alpha: 0.40),
        SanaColors.glow.withValues(alpha: 0.22),
        SanaColors.violetDeep.withValues(alpha: 0.12),
      ],
      lobeAmp: 0.08,
      lobes: 6,
    );
    _drawFold(
      canvas,
      center: center.translate(base * 0.06, base * 0.05),
      radius: base * 0.82,
      phase: phase * 1.3 + 1.4,
      rotation: phase * 0.25,
      colors: [
        SanaColors.lavender.withValues(alpha: 0.48),
        SanaColors.lavenderLight.withValues(alpha: 0.36),
        SanaColors.violetDeep.withValues(alpha: 0.28),
      ],
      lobeAmp: 0.09,
      lobes: 5,
    );
    _drawFold(
      canvas,
      center: center.translate(-base * 0.05, -base * 0.06),
      radius: base * 0.74,
      phase: phase * 0.9 + 2.1,
      rotation: -phase * 0.18,
      colors: [
        SanaColors.violetDeep.withValues(alpha: 0.42),
        SanaColors.lavender.withValues(alpha: 0.50),
        SanaColors.lavenderLight.withValues(alpha: 0.30),
      ],
      lobeAmp: 0.07,
      lobes: 7,
    );
    _drawFold(
      canvas,
      center: center.translate(base * 0.02, base * 0.01),
      radius: base * 0.62,
      phase: phase + 2.8,
      rotation: phase * 0.1,
      colors: [
        const Color(0xE6B88DE0),
        const Color(0xD9A978D0),
        const Color(0xCC7656A6),
      ],
      lobeAmp: 0.05,
      lobes: 4,
    );
    // Soft inner body — still lavender, never white.
    _drawFold(
      canvas,
      center: center.translate(-base * 0.03, -base * 0.04),
      radius: base * 0.48,
      phase: phase * 1.1 + 0.4,
      rotation: -phase * 0.12,
      colors: [
        const Color(0xE6C9A6EA),
        const Color(0xE0B88DE0),
        const Color(0xD98968B8),
      ],
      lobeAmp: 0.04,
      lobes: 5,
    );

    // Tiny translucent highlight fold (lilac, not blown-out).
    final highlight = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = SanaColors.lavenderLight.withValues(alpha: 0.20);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-base * 0.12, -base * 0.16),
        width: base * 0.55,
        height: base * 0.32,
      ),
      highlight,
    );
  }

  void _drawFold(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double phase,
    required double rotation,
    required List<Color> colors,
    required double lobeAmp,
    required int lobes,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);

    final path = _organicPath(
      center,
      radius,
      phase,
      lobeAmp: lobeAmp,
      lobes: lobes,
    );
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center.translate(-radius * 0.15, -radius * 0.18),
        radius * 1.05,
        colors,
        _stops(colors.length),
      );
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  List<double> _stops(int count) {
    if (count <= 1) return const [0];
    return List<double>.generate(count, (i) => i / (count - 1));
  }

  Path _organicPath(
    Offset center,
    double radius,
    double phase, {
    required double lobeAmp,
    required int lobes,
  }) {
    final path = Path();
    const steps = 80;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final angle = t * math.pi * 2;
      final wave =
          math.sin(angle * lobes + phase) * lobeAmp +
          math.cos(angle * (lobes - 2) - phase * 1.15) * (lobeAmp * 0.55);
      final r = radius * (1 + wave);
      final point = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _SilkOrbPainter oldDelegate) {
    return oldDelegate.breathe != breathe ||
        oldDelegate.flow != flow ||
        oldDelegate.state != state;
  }
}
