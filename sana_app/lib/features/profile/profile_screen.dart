import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_provider.dart';

/// Real, minimal profile view — name and email as SANA actually has
/// them, not a mock. Editing isn't wired up yet (name is currently
/// set once during onboarding); this screen is deliberately honest
/// about that rather than showing an edit button that doesn't work.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final name = auth.profile?.name ?? 'there';
    final email = auth.user?.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      initial,
                      style: theme.textTheme.displaySmall?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(child: Text(name, style: theme.textTheme.titleLarge)),
              const SizedBox(height: 4),
              Center(
                child: Text(email, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: 32),
              Text(
                'More profile options (editing your name, avatar) are coming later.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
