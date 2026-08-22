import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:provider/provider.dart';

import 'package:intl/intl.dart';

import '../controllers/app_ctrl.dart';
import '../models/sana_orb_state.dart';
import '../services/auth_service.dart';
import '../services/build_projects_service.dart';
import '../services/conversation_service.dart';
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
        return const _HistoryPane();
      case HomeTab.projects:
        return const _ProjectsPane();
      case HomeTab.profile:
        return const _ProfilePane();
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
        final orbSize = (constraints.maxHeight * 0.28).clamp(120.0, 200.0);

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
                  Consumer<AppCtrl>(
                    builder: (context, ctrl, _) {
                      final error = ctrl.connectionError;
                      if (error == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                        ),
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
            enabled: true,
            onTap: () => appCtrl.setConversationMode(mode),
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

class _ProjectsPane extends StatefulWidget {
  const _ProjectsPane();

  @override
  State<_ProjectsPane> createState() => _ProjectsPaneState();
}

class _ProjectsPaneState extends State<_ProjectsPane> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<BuildProjectsService>().fetchProjects());
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectsService = context.watch<BuildProjectsService>();
    final textTheme = Theme.of(context).textTheme;
    final projects = projectsService.projects;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Build Projects',
            style: textTheme.headlineMedium?.copyWith(
              color: SanaColors.lavender,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Download generated project files from your latest builds.',
            style: textTheme.bodySmall?.copyWith(color: SanaColors.fgMuted),
          ),
          const SizedBox(height: 20),
          if (projectsService.errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SanaColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
              ),
              child: Text(
                projectsService.errorMessage!,
                style: textTheme.bodySmall?.copyWith(color: Colors.redAccent),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: projectsService.isLoading && projects.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: SanaColors.lavender),
                  )
                : !projectsService.hasBackend
                    ? Center(
                        child: Text(
                          'Configure SANA_BACKEND_URL to load build projects.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(color: SanaColors.fgSecondary),
                        ),
                      )
                    : projects.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.folder_copy_outlined,
                                    size: 48, color: SanaColors.fgMuted),
                                const SizedBox(height: 12),
                                Text(
                                  'No build projects yet',
                                  style: textTheme.titleMedium
                                      ?.copyWith(color: SanaColors.fgSecondary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Start a build conversation and approve execution first.',
                                  textAlign: TextAlign.center,
                                  style: textTheme.bodySmall
                                      ?.copyWith(color: SanaColors.fgMuted),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            color: SanaColors.lavender,
                            onRefresh: () => projectsService.fetchProjects(),
                            child: ListView.separated(
                              itemCount: projects.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final project = projects[index];
                                final updatedAt = DateFormat('MMM d, h:mm a').format(project.updatedAt);
                                final isDownloading =
                                    projectsService.activeDownloadProjectId == project.projectId;

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: SanaColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: SanaColors.lavender.withValues(alpha: 0.12)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              project.title,
                                              style: textTheme.titleMedium?.copyWith(
                                                color: SanaColors.fgPrimary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: SanaColors.nearBlack,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              project.status,
                                              style: textTheme.labelSmall?.copyWith(
                                                color: SanaColors.lavender,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Updated $updatedAt',
                                        style: textTheme.bodySmall?.copyWith(color: SanaColors.fgMuted),
                                      ),
                                      if (project.workspacePath.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          project.workspacePath,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: textTheme.bodySmall?.copyWith(color: SanaColors.fgSecondary),
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton.icon(
                                          onPressed: !project.canDownload || isDownloading
                                              ? null
                                              : () async {
                                                  final ok = await context
                                                      .read<BuildProjectsService>()
                                                      .downloadProject(project);
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        ok
                                                            ? 'Download link opened for ${project.title}.'
                                                            : (context.read<BuildProjectsService>().errorMessage ??
                                                                'Failed to open download link.'),
                                                      ),
                                                    ),
                                                  );
                                                },
                                          icon: isDownloading
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Icon(Icons.download_rounded),
                                          label: Text(project.canDownload ? 'Download files' : 'Await completion'),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePane extends StatelessWidget {
  const _ProfilePane();

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final textTheme = Theme.of(context).textTheme;

    final userName = authService.userName ?? 'User';
    final userEmail = authService.userEmail ?? 'No email';
    final assistantName = authService.assistantName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Profile & Settings', style: textTheme.headlineMedium?.copyWith(color: SanaColors.lavender)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SanaColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SanaColors.lavender.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: SanaColors.lavender,
                    child: Icon(Icons.person, color: SanaColors.nearBlack),
                  ),
                  title: Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, color: SanaColors.fgPrimary)),
                  subtitle: Text(userEmail, style: const TextStyle(color: SanaColors.fgSecondary)),
                ),
                const Divider(color: SanaColors.nearBlack, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Assistant Name', style: TextStyle(color: SanaColors.fgSecondary)),
                    Text(assistantName, style: const TextStyle(color: SanaColors.lavender, fontWeight: FontWeight.w600)),
                  ],
                ),
                if (authService.isMock) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Auth Mode', style: TextStyle(color: SanaColors.fgSecondary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: SanaColors.nearBlack,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Dev Local Mode', style: TextStyle(color: SanaColors.fgMuted, fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await context.read<AuthService>().signOut();
              },
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              label: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _HistoryPane extends StatefulWidget {
  const _HistoryPane();

  @override
  State<_HistoryPane> createState() => _HistoryPaneState();
}

class _HistoryPaneState extends State<_HistoryPane> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<ConversationService>().fetchUserConversations());
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversationService = context.watch<ConversationService>();
    final appCtrl = context.read<AppCtrl>();
    final textTheme = Theme.of(context).textTheme;
    final conversations = conversationService.conversations;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conversation History',
            style: textTheme.headlineMedium?.copyWith(
              color: SanaColors.lavender,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap any past session to rehydrate and resume',
            style: textTheme.bodySmall?.copyWith(color: SanaColors.fgMuted),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: conversationService.isLoading && conversations.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: SanaColors.lavender),
                  )
                : conversations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble_outline_rounded,
                                size: 48, color: SanaColors.fgMuted),
                            const SizedBox(height: 12),
                            Text(
                              'No past conversations yet',
                              style: textTheme.titleMedium
                                  ?.copyWith(color: SanaColors.fgSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Start talking with Sana on the Home tab!',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: SanaColors.fgMuted),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: SanaColors.lavender,
                        onRefresh: () =>
                            conversationService.fetchUserConversations(),
                        child: ListView.separated(
                          itemCount: conversations.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final session = conversations[index];
                            final timeFormatted =
                                DateFormat('MMM d, h:mm a').format(session.updatedAt);
                            final preview = session.previewText ?? 'Voice & text session';

                            return Material(
                              color: SanaColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  unawaited(appCtrl.openPastConversation(
                                    session,
                                    conversationService,
                                  ));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              session.title,
                                              style: textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: SanaColors.fgPrimary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: SanaColors.lavender
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              session.mode.toUpperCase(),
                                              style: const TextStyle(
                                                color: SanaColors.lavender,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        preview,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: SanaColors.fgSecondary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            timeFormatted,
                                            style: textTheme.bodySmall
                                                ?.copyWith(
                                                    color: SanaColors.fgMuted),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18,
                                              color: SanaColors.fgMuted,
                                            ),
                                            onPressed: () {
                                              unawaited(
                                                conversationService
                                                    .deleteConversation(
                                                        session.id),
                                              );
                                            },
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
