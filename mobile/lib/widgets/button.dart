import 'package:flutter/material.dart';

/// Button shown when disconnected to start a new conversation
class Button extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isProgressing;
  final bool enabled;
  final String text;

  const Button({
    super.key,
    required this.text,
    required this.onPressed,
    this.isProgressing = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext ctx) => TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          backgroundColor: Theme.of(ctx).buttonTheme.colorScheme?.surface,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          spacing: 15,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isProgressing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            Text(
              text.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
}
