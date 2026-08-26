import 'package:flutter/material.dart';

import 'app_exception.dart';

/// Converts any caught error into a message safe to show a user.
///
/// Centralizing this means feature code never has to decide how to word
/// an error — it just catches, converts, and displays.
String errorMessageFor(Object error) {
  if (error is AppException) return error.message;
  return 'Something went wrong. Please try again.';
}

/// A small inline banner for surfacing [errorMessageFor] in a screen.
/// Used wherever a screen needs to show a recoverable error without
/// interrupting the whole app (e.g. a failed sign-in attempt).
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
