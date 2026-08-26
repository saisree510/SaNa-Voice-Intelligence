import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_provider.dart';

/// Real settings — currently just account info and a working Log Out
/// (moved here from the old Home screen's icon). Logging out flips
/// [AuthProvider.isLoggedIn], which the router's redirect reacts to
/// automatically — no explicit navigation needed here.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Account'),
              subtitle: Text(auth.user?.email ?? ''),
            ),
            const Divider(height: 32),
            ListTile(
              leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
              title: Text('Log out', style: TextStyle(color: theme.colorScheme.error)),
              onTap: () => context.read<AuthProvider>().logout(),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Text('More settings (theme, voice preferences, notifications) are coming later.'),
            ),
          ],
        ),
      ),
    );
  }
}
