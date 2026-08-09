import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:provider/provider.dart';

import '../controllers/app_ctrl.dart';
import '../models/sana_orb_state.dart';
import '../ui/sana_theme.dart';
import '../widgets/sana_orb_view.dart';

/// SaNa home: brand, greeting, orb, mode shells, minimal bottom nav.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppCtrl>(
      builder: (context, appCtrl, _) {
        return Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(
              color: SanaColors.nearBlack,
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(child: _HomeTabBody(appCtrl: appCtrl)),
                  NavigationBar(
                    selectedIndex: appCtrl.homeTab.index,
                    onDestinationSelected: (index) {
                      appCtrl.setHomeTab(HomeTab.values[index]);
                    },
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.history_outlined),
                        selectedIcon: Icon(Icons.history_rounded),
                        label: 'History',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.folder_outlined),
                        selectedIcon: Icon(Icons.folder_rounded),
                        label: 'Projects',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: 'Profile',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeTabBody extends StatelessWidget {
  const _HomeTabBody({required this.appCtrl});

  final AppCtrl appCtrl;

  @override
  Widget build(BuildContext context) {
    switch (appCtrl.homeTab) {
      case HomeTab.home:
        return _SaNaHome(appCtrl: appCtrl);
      case HomeTab.history:
        return const _PlaceholderPane(
          title: 'History',
          body: 'Past conversations will appear here after persistence lands.',
        );
      case HomeTab.projects:
        return const _PlaceholderPane(
          title: 'Projects',
          body: 'Build projects will live here in a later phase.',
        );
      case HomeTab.profile:
        return const _PlaceholderPane(
          title: 'Profile',
          body: 'Sign-in and assistant preferences arrive with auth.',
        );
    }
  }
}

class _SaNaHome extends StatelessWidget {
  const _SaNaHome({required this.appCtrl});

  final AppCtrl appCtrl;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final orbSize = (constraints.maxHeight * 0.32).clamp(140.0, 240.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'Sana',
                    textAlign: TextAlign.center,
                    style: textTheme.displaySmall?.copyWith(
                      color: SanaColors.lavender,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    appCtrl.greetingLine,
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      color: SanaColors.fgSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(flex: 2),
                  Center(
                    child: Consumer2<AppCtrl, sdk.Session>(
                      builder: (context, ctrl, session, _) {
                        final connecting = ctrl.isConnecting;
                        final live = session.connectionState == sdk.ConnectionState.connected ||
                            session.connectionState == sdk.ConnectionState.reconnecting;

                        return SanaOrbView(
                          size: orbSize,
                          forceState: connecting
                              ? SanaOrbState.connecting
                              : live
                                  ? null
                                  : SanaOrbState.idle,
                          onTap: () {
                            if (connecting) {
                              unawaited(ctrl.cancelConnect());
                            } else {
                              unawaited(ctrl.connect());
                            }
                          },
                        );
                      },
                    ),
                  ),
                  const Spacer(flex: 2),
                  Text(
                    'Mode',
                    style: textTheme.labelSmall?.copyWith(color: SanaColors.fgMuted),
                  ),
                  const SizedBox(height: 10),
                  _ModeRow(appCtrl: appCtrl),
                  const SizedBox(height: 22),
                  Consumer2<AppCtrl, sdk.Session>(
                    builder: (context, ctrl, session, _) {
                      final connecting = ctrl.isConnecting;
                      final live = session.connectionState == sdk.ConnectionState.connected ||
                          session.connectionState == sdk.ConnectionState.reconnecting;

                      late final String label;
                      late final VoidCallback onPressed;
                      if (connecting) {
                        label = 'Cancel';
                        onPressed = () => unawaited(ctrl.cancelConnect());
                      } else if (live) {
                        label = 'Continue';
                        onPressed = () => unawaited(ctrl.connect());
                      } else {
                        label = 'Talk with Sana';
                        onPressed = () => unawaited(ctrl.connect());
                      }

                      return FilledButton(
                        onPressed: onPressed,
                        child: Text(label),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.appCtrl});

  final AppCtrl appCtrl;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in ConversationMode.values)
          _ModeChip(
            label: mode.label,
            selected: appCtrl.conversationMode == mode,
            enabled: mode == ConversationMode.general,
            onTap: mode == ConversationMode.general
                ? () => appCtrl.setConversationMode(mode)
                : null,
          ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? SanaColors.lavender.withValues(alpha: 0.22)
        : SanaColors.surface.withValues(alpha: enabled ? 1 : 0.55);
    final fg = selected
        ? SanaColors.lavender
        : enabled
            ? SanaColors.fgSecondary
            : SanaColors.fgMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: enabled ? label : '$label, coming soon',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              enabled ? label : '$label · soon',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontSize: 13,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderPane extends StatelessWidget {
  const _PlaceholderPane({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
