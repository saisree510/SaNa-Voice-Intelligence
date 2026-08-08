import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/sana_colors.dart';
import 'orb_state.dart';

class SanaOrb extends StatefulWidget {
  const SanaOrb({
    super.key,
    required this.state,
    this.size = 220,
    this.onTap,
  });

  final SanaOrbState state;
  final double size;
  final VoidCallback? onTap;

  @override
  State<SanaOrb> createState() => _SanaOrbState();
}

class _SanaOrbState extends State<SanaOrb> with TickerProviderStateMixin {
  late final AnimationController _breathe;
  late final AnimationController _ripple;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
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
          ..duration = const Duration(milliseconds: 2800)
          ..repeat(reverse: true);
        _ripple.stop();
        _spin.stop();
      case SanaOrbState.listening:
      case SanaOrbState.userSpeaking:
        _breathe
          ..duration = const Duration(milliseconds: 1400)
          ..repeat(reverse: true);
        _ripple
          ..duration = const Duration(milliseconds: 1600)
          ..repeat();
        _spin.stop();
      case SanaOrbState.thinking:
      case SanaOrbState.connecting:
      case SanaOrbState.reconnecting:
        _breathe
          ..duration = const Duration(milliseconds: 1200)
          ..repeat(reverse: true);
        _ripple.stop();
        _spin
          ..duration = const Duration(milliseconds: 3200)
          ..repeat();
      case SanaOrbState.speaking:
        _breathe
          ..duration = const Duration(milliseconds: 900)
          ..repeat(reverse: true);
        _ripple
          ..duration = const Duration(milliseconds: 1100)
          ..repeat();
        _spin.stop();
      case SanaOrbState.error:
        _breathe.stop();
        _ripple.stop();
        _spin.stop();
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _ripple.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glowColor = switch (widget.state) {
      SanaOrbState.error => SanaColors.danger,
      SanaOrbState.thinking ||
      SanaOrbState.connecting ||
      SanaOrbState.reconnecting =>
        SanaColors.accentIndigo,
      SanaOrbState.speaking => SanaColors.accentCyan,
      SanaOrbState.listening || SanaOrbState.userSpeaking => SanaColors.accentTeal,
      SanaOrbState.idle => SanaColors.accentTeal,
    };

    return Semantics(
      button: widget.onTap != null,
      label: 'SaNa voice orb, ${widget.state.label}',
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_breathe, _ripple, _spin]),
            builder: (context, child) {
              final breathe = 0.92 + (_breathe.value * 0.08);
              final ripple = _ripple.isAnimating ? _ripple.value : 0.0;
              final spin = _spin.isAnimating ? _spin.value * math.pi * 2 : 0.0;

              return CustomPaint(
                painter: _OrbPainter(
                  breathe: breathe,
                  ripple: ripple,
                  spin: spin,
                  glowColor: glowColor,
                  state: widget.state,
                ),
                child: child,
              );
            },
            child: Center(
              child: Text(
                'SaNa',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: SanaColors.textPrimary.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.breathe,
    required this.ripple,
    required this.spin,
    required this.glowColor,
    required this.state,
  });

  final double breathe;
  final double ripple;
  final double spin;
  final Color glowColor;
  final SanaOrbState state;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) * breathe * 0.62;

    if (ripple > 0) {
      final ripplePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = glowColor.withValues(alpha: (1 - ripple) * 0.35);
      canvas.drawCircle(center, radius * (1 + ripple * 0.55), ripplePaint);
      canvas.drawCircle(center, radius * (1 + ripple * 0.28), ripplePaint);
    }

    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28)
      ..color = glowColor.withValues(alpha: state == SanaOrbState.error ? 0.35 : 0.28);
    canvas.drawCircle(center, radius * 1.25, glowPaint);

    final coreRect = Rect.fromCircle(center: center, radius: radius);
    final corePaint = Paint()
      ..shader = SanaColors.orbCore.createShader(coreRect);
    canvas.drawCircle(center, radius, corePaint);

    final innerShade = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(coreRect);
    canvas.drawCircle(center, radius, innerShade);

    if (spin != 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.55);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 1.08),
        spin,
        math.pi * 0.7,
        false,
        arcPaint,
      );
    }

    if (state == SanaOrbState.error) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = SanaColors.danger.withValues(alpha: 0.8);
      canvas.drawCircle(center, radius * 1.05, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) {
    return oldDelegate.breathe != breathe ||
        oldDelegate.ripple != ripple ||
        oldDelegate.spin != spin ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.state != state;
  }
}
