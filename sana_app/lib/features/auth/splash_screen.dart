import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';

/// SANA's launch screen — purely branding at this point. Session
/// restoration (see [AuthProvider.restoreSession]) happens in `main()`
/// before this screen (or any other) is even built, so by the time
/// anything here runs, the router's redirect already knows whether
/// there's a logged-in, onboarded session — this just shows the brand
/// for a beat before handing off to it.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) context.go(AppRoutes.home);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 20),
            Text('SANA', style: theme.textTheme.displaySmall),
            const SizedBox(height: 6),
            Text(
              'Your AI conversation partner',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
