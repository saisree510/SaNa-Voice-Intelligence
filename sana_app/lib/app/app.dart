import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/auth/auth_provider.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// SANA's root widget: wires auth state, theme, and router together.
///
/// [authProvider] is built once in `main()` (not here) so the same
/// instance can be handed to both [ChangeNotifierProvider.value] and
/// [buildRouter] as its `refreshListenable` — the router is built once,
/// not recreated on every rebuild.
class SanaApp extends StatelessWidget {
  const SanaApp({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: authProvider,
      child: MaterialApp.router(
        title: 'SANA',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        routerConfig: buildRouter(authProvider),
      ),
    );
  }
}
