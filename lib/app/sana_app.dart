import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/sana_theme.dart';
import 'router.dart';

class SanaApp extends ConsumerStatefulWidget {
  const SanaApp({super.key});

  @override
  ConsumerState<SanaApp> createState() => _SanaAppState();
}

class _SanaAppState extends ConsumerState<SanaApp> {
  late final _router = createSanaRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SaNa',
      debugShowCheckedModeBanner: false,
      theme: SanaTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
