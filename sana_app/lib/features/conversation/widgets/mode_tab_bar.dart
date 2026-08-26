import 'package:flutter/material.dart';

import '../../../core/constants/app_modes.dart';

/// The Debate | Brainstorm | Build tab switcher — sits under the
/// AppBar in [UnifiedConversationScreen]. Each tab keeps that mode's
/// icon and identity color (matching the mode cards on Home), active
/// tab underlined in its own color rather than one shared accent.
class ModeTabBar extends StatelessWidget {
  const ModeTabBar({super.key, required this.selectedIndex, required this.onChanged});

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < AppModes.all.length; i++) Expanded(child: _tab(context, AppModes.all[i], i)),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, AppMode mode, int index) {
    final theme = Theme.of(context);
    final active = index == selectedIndex;
    final color = active ? mode.color : theme.colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: () => onChanged(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? mode.color : Colors.transparent, width: 2.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(mode.icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              mode.title,
              style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
