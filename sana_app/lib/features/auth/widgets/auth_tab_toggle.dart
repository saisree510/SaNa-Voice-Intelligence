import 'package:flutter/material.dart';

enum WelcomeTab { logIn, signUp }

/// Minimal underline-style Log In / Sign Up tabs — switches the welcome
/// screen's form between its two modes without navigating to a
/// different route. Plain text + a thin accent underline on the active
/// tab, in keeping with the screen's minimal design (no filled pill,
/// no extra color beyond the one accent).
class AuthTabToggle extends StatelessWidget {
  const AuthTabToggle({super.key, required this.tab, required this.onChanged});

  final WelcomeTab tab;
  final ValueChanged<WelcomeTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tab(context, 'Log In', WelcomeTab.logIn),
        const SizedBox(width: 32),
        _tab(context, 'Sign Up', WelcomeTab.signUp),
      ],
    );
  }

  Widget _tab(BuildContext context, String label, WelcomeTab value) {
    final theme = Theme.of(context);
    final active = tab == value;
    final color = active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: () => onChanged(value),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
              child: Text(label),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 2,
              width: 24,
              color: active ? theme.colorScheme.primary : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
