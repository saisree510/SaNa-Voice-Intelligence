import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_modes.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_display.dart';
import '../../../services/conversation_history_api_service.dart';
import '../../auth/auth_provider.dart';
import '../models/conversation_summary.dart';

/// SANA's navigation drawer for narrow (phone-width) screens — the
/// same [SanaSidebarBody] content as [SanaSidebarPanel], just slid in
/// as a dismissible overlay instead of sitting permanently on screen.
class SanaDrawer extends StatelessWidget {
  const SanaDrawer({super.key, required this.mode, required this.onSelectChat, required this.onNewChat});

  final AppMode mode;
  final ValueChanged<ConversationSummary> onSelectChat;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SanaSidebarBody(
        mode: mode,
        onSelectChat: onSelectChat,
        onNewChat: onNewChat,
        closeOverlay: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// The same sidebar, docked permanently beside the workspace on wide
/// (tablet/desktop-width) screens instead of hiding behind a hamburger
/// — no scrim, nothing to dismiss, visible next to all three modes at
/// once. [SanaDrawer] wraps the same body in a [Drawer] for phones.
class SanaSidebarPanel extends StatelessWidget {
  const SanaSidebarPanel({super.key, required this.mode, required this.onSelectChat, required this.onNewChat});

  final AppMode mode;
  final ValueChanged<ConversationSummary> onSelectChat;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: 280,
        child: SanaSidebarBody(
          mode: mode,
          onSelectChat: onSelectChat,
          onNewChat: onNewChat,
          closeOverlay: null,
        ),
      ),
    );
  }
}

/// New Chat, a few not-yet-built sections shown as honest placeholders
/// (Inbox/Schedule/Projects — tapping says "coming soon", nothing fake
/// happens), the current mode's real chat history, and Settings.
/// [closeOverlay] pops the enclosing [Drawer] before navigating when
/// this is shown as an overlay (phones); it's null when shown as a
/// permanent panel (nothing to close).
class SanaSidebarBody extends StatefulWidget {
  const SanaSidebarBody({
    super.key,
    required this.mode,
    required this.onSelectChat,
    required this.onNewChat,
    required this.closeOverlay,
  });

  final AppMode mode;
  final ValueChanged<ConversationSummary> onSelectChat;
  final VoidCallback onNewChat;
  final VoidCallback? closeOverlay;

  @override
  State<SanaSidebarBody> createState() => _SanaSidebarBodyState();
}

class _SanaSidebarBodyState extends State<SanaSidebarBody> {
  final _apiService = RealConversationHistoryApiService();
  late Future<List<ConversationSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant SanaSidebarBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode.id != widget.mode.id) {
      _refresh();
    }
  }

  // Block body, not `setState(() => _future = _load())` -- that arrow
  // form's "value" is the assignment's RHS (a Future, since _load() is
  // async), so setState() throws "callback argument returned a
  // Future." Splitting the assignment onto its own statement makes the
  // closure return void instead.
  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<List<ConversationSummary>> _load() async {
    final token = context.read<AuthProvider>().authToken;
    if (token == null) {
      throw const AuthException('You need to be logged in to see past conversations.');
    }
    final all = await _apiService.listConversations(authToken: token);
    final forThisMode = all.where((c) => c.mode == widget.mode.id).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return forThisMode;
  }

  void _comingSoon(String feature) {
    widget.closeOverlay?.call();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$feature is coming soon.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                Text(
                  'SANA',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_comment_outlined),
            title: const Text('New Chat'),
            onTap: () {
              widget.closeOverlay?.call();
              widget.onNewChat();
              // The chat just left behind already has its messages
              // saved server-side (every send persists immediately,
              // not just on "New Chat") — but this sidebar's list was
              // fetched once at mount, so without this it keeps
              // showing stale data and the just-finished chat never
              // appears until the whole screen is rebuilt some other way.
              _refresh();
            },
          ),
          ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: const Text('Inbox'),
            onTap: () => _comingSoon('Inbox'),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Schedule'),
            onTap: () => _comingSoon('Schedule'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Projects'),
            onTap: () => _comingSoon('Projects'),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Chats',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ConversationSummary>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: ErrorBanner(
                      message: errorMessageFor(snapshot.error!),
                      onRetry: _refresh,
                    ),
                  );
                }
                final conversations = snapshot.data!;
                if (conversations.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'No past ${widget.mode.title.toLowerCase()} conversations yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (final conversation in conversations)
                      ListTile(
                        title: Text(
                          conversation.title?.trim().isNotEmpty == true
                              ? conversation.title!
                              : 'Untitled conversation',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => widget.onSelectChat(conversation),
                      ),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              widget.closeOverlay?.call();
              context.push(AppRoutes.settings);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
