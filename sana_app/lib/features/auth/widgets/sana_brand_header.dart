import 'package:flutter/material.dart';

/// SANA's icon + wordmark, reused at the top of every auth screen.
class SanaBrandHeader extends StatelessWidget {
  const SanaBrandHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = compact ? 56.0 : 76.0;
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: size * 0.5),
        ),
        SizedBox(height: compact ? 12 : 18),
        Text('SANA', style: theme.textTheme.headlineMedium),
      ],
    );
  }
}
