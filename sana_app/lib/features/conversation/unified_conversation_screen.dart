import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:go_router/go_router.dart';

import '../../core/constants/app_modes.dart';
import '../../core/constants/app_routes.dart';
import '../../core/errors/error_display.dart';
import '../../services/build_service.dart';
import '../../services/conversation_history_api_service.dart';
import '../../services/livekit_voice_service.dart';
import '../../services/real_conversation_service.dart';
import '../../services/voice_service.dart';
import '../auth/auth_provider.dart';
import '../build/build_job_provider.dart';
import '../build/widgets/build_workspace_panel.dart';
import 'conversation_provider.dart';
import 'models/conversation_summary.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/conversation_input_bar.dart';
import 'widgets/mode_tab_bar.dart';
import 'widgets/sana_drawer.dart';
import 'widgets/sana_orb.dart';
import 'widgets/thinking_indicator.dart';
import 'widgets/voice_active_bar.dart';

/// SANA's home screen — the direct post-login landing (no separate
/// mode-picker screen before it), all three modes switched via
/// [ModeTabBar] inside this one screen, per the user's architecture
/// diagram.
///
/// Each mode keeps its own live [_ModeSession] (provider, voice
/// service, scroll/text controllers) for the whole time this screen is
/// open — an [IndexedStack], not a rebuild-on-switch — so switching
/// tabs preserves scroll position and in-progress typing instead of
/// reloading. [initialModeId] just picks which tab starts active.
class UnifiedConversationScreen extends StatefulWidget {
  const UnifiedConversationScreen({super.key, required this.initialModeId});

  final String initialModeId;

  @override
  State<UnifiedConversationScreen> createState() => _UnifiedConversationScreenState();
}

class _ModeSession {
  _ModeSession(
    this.mode,
    this.textProvider,
    this.voiceService,
    this.controller,
    this.scrollController,
    this.buildJobProvider,
  );

  final AppMode mode;
  final ConversationProvider textProvider;
  final VoiceService voiceService;
  final TextEditingController controller;
  final ScrollController scrollController;

  /// Only non-null for the Build-mode session — tracks the build job
  /// (if any) tied to this session's current conversation. See
  /// [BuildWorkspacePanel].
  final BuildJobProvider? buildJobProvider;
}

class _UnifiedConversationScreenState extends State<UnifiedConversationScreen> {
  final _historyApi = RealConversationHistoryApiService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final List<_ModeSession> _sessions;
  late int _selectedIndex;

  _ModeSession get _current => _sessions[_selectedIndex];

  @override
  void initState() {
    super.initState();
    final foundIndex = AppModes.all.indexWhere((m) => m.id == widget.initialModeId);
    _selectedIndex = foundIndex < 0 ? 0 : foundIndex;

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.user?.id ?? 'unknown';

    _sessions = [
      for (final mode in AppModes.all)
        _ModeSession(
          mode,
          ConversationProvider(
            mode: mode,
            userId: userId,
            conversationService: RealConversationService(getAuthToken: () => authProvider.authToken),
          ),
          LiveKitVoiceService(),
          TextEditingController(),
          ScrollController(),
          // Only Build mode tracks a build job — Debate/Brainstorm never
          // trigger one, so there's nothing for this to watch there.
          mode.id == 'build'
              ? BuildJobProvider(buildService: BuildService(getAuthToken: () => authProvider.authToken))
              : null,
        ),
    ];

    for (final session in _sessions) {
      session.voiceService.addListener(() => session.textProvider.mergeExternal(session.voiceService.transcript));
      // Text's restore (conversation_provider.dart's _loadHistory) is the
      // one that reads persisted state; mirror whatever it finds into
      // voice too, once it's actually loaded — so resuming by voice
      // right after a refresh continues the same thread a text message
      // would, instead of voice starting a separate one from scratch.
      session.textProvider.ready.then((_) {
        final restoredId = session.textProvider.conversationId;
        if (restoredId != null) session.voiceService.resumeConversation(restoredId);
      });
    }
  }

  @override
  void dispose() {
    for (final session in _sessions) {
      session.controller.dispose();
      session.scrollController.dispose();
      session.textProvider.dispose();
      session.voiceService.dispose();
      session.buildJobProvider?.dispose();
    }
    super.dispose();
  }

  /// Checks whether the message/call that just finished for [session]
  /// started (or advanced) a build, and if so starts the workspace
  /// panel tracking it. No-op outside Build mode.
  void _refreshBuildFor(_ModeSession session) {
    final provider = session.buildJobProvider;
    if (provider == null) return;
    final conversationId = session.voiceService.conversationId ?? session.textProvider.conversationId;
    unawaited(provider.refreshForConversation(conversationId));
  }

  Future<void> _selectTab(int index) async {
    if (index == _selectedIndex) return;
    // Don't leave a live call running in a tab you've switched away
    // from and can no longer see or control.
    final leaving = _sessions[_selectedIndex];
    if (leaving.voiceService.isActive) await leaving.voiceService.end();
    if (!mounted) return;
    setState(() => _selectedIndex = index);
  }

  void _sendFor(_ModeSession session) {
    final text = session.controller.text;
    if (text.trim().isEmpty) return;
    session.controller.clear();
    if (session.voiceService.isActive) {
      unawaited(session.voiceService.sendText(text).then((_) => _refreshBuildFor(session)));
    } else {
      unawaited(session.textProvider.sendText(text).then((_) => _refreshBuildFor(session)));
    }
  }

  Future<void> _toggleVoiceFor(_ModeSession session) async {
    if (session.voiceService.isActive) {
      await session.voiceService.end();
      _refreshBuildFor(session);
      return;
    }
    final auth = context.read<AuthProvider>();
    final userId = auth.user?.id ?? 'unknown';
    final userName = auth.profile?.name ?? 'there';
    await session.voiceService.start(modeId: session.mode.id, userId: userId, userName: userName);
    // The token exchange above resolves (creates or confirms) which
    // conversation this call belongs to — persist it as this mode's
    // active thread so a refresh right after starting a call still
    // continues it, the same way a sent text message does.
    await session.textProvider.persistExternalConversationId(session.voiceService.conversationId);
  }

  Future<void> _startNewChat() async {
    final session = _current;
    if (session.voiceService.isActive) await session.voiceService.end();
    session.voiceService.startNewConversation();
    await session.textProvider.startNewConversation();
    session.buildJobProvider?.reset();
  }

  /// Tapping a chat in [ChatsDrawer] calls this — closes the drawer, ends
  /// any active call for the current tab, loads that conversation's real
  /// history, and makes it the one subsequent messages continue.
  Future<void> _onChatSelected(ConversationSummary selected) async {
    _scaffoldKey.currentState?.closeDrawer();
    final session = _current;
    if (session.voiceService.isActive) await session.voiceService.end();
    if (!mounted) return;

    final token = context.read<AuthProvider>().authToken;
    if (token == null) return;

    try {
      final loadedMessages = await _historyApi.getConversationMessages(
        authToken: token,
        conversationId: selected.id,
      );
      await session.textProvider.loadConversation(selected.id, loadedMessages);
      // So tapping the mic next continues *this* thread (voice or
      // text turns alike) instead of whatever voice conversation was
      // active before, or a brand-new one.
      session.voiceService.resumeConversation(selected.id);
      // Reopening a Build conversation should restore whatever build
      // it already has (in progress or completed), not show a stale
      // panel from the conversation switched away from.
      session.buildJobProvider?.reset();
      _refreshBuildFor(session);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessageFor(e))));
    }
  }

  /// Below this width the sidebar hides behind a hamburger drawer
  /// (phones); at or above it, the sidebar docks permanently beside
  /// the workspace instead (tablets/desktop web) — same content
  /// either way, see [SanaDrawer] / [SanaSidebarPanel].
  static const _wideBreakpoint = 700.0;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    final workspace = Scaffold(
      key: _scaffoldKey,
      // On narrow screens there's no screen beneath this one to pop
      // back to, so the leading icon is left to Flutter's default —
      // with `drawer` set, that's automatically a hamburger menu icon.
      // On wide screens the sidebar is already docked permanently
      // beside this Scaffold, so no drawer/hamburger is needed at all.
      drawer: isWide
          ? null
          : SanaDrawer(mode: _current.mode, onSelectChat: _onChatSelected, onNewChat: _startNewChat),
      appBar: AppBar(
        title: const Text('SANA'),
        actions: [
          IconButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Notifications are coming soon.')),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Notifications',
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.profile),
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Profile',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: ModeTabBar(selectedIndex: _selectedIndex, onChanged: _selectTab),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (final session in _sessions)
            _ModeConversationBody(
              session: session,
              onSend: () => _sendFor(session),
              onToggleVoice: () => _toggleVoiceFor(session),
            ),
        ],
      ),
    );

    if (!isWide) return workspace;

    // Outer Scaffold so SnackBars fired from the sidebar (e.g. the
    // Inbox/Schedule/Projects "coming soon" messages) have a
    // ScaffoldMessenger to find — the sidebar sits beside, not inside,
    // `workspace`'s own Scaffold.
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SanaSidebarPanel(mode: _current.mode, onSelectChat: _onChatSelected, onNewChat: _startNewChat),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: workspace),
        ],
      ),
    );
  }
}

class _ModeConversationBody extends StatelessWidget {
  const _ModeConversationBody({required this.session, required this.onSend, required this.onToggleVoice});

  final _ModeSession session;
  final VoidCallback onSend;
  final VoidCallback onToggleVoice;

  void _scrollToBottom() {
    if (!session.scrollController.hasClients) return;
    session.scrollController.animateTo(
      session.scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session.textProvider),
        ChangeNotifierProvider.value(value: session.voiceService),
      ],
      child: Consumer2<ConversationProvider, VoiceService>(
        builder: (context, textProvider, voice, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          final inCall = voice.isActive;
          final messages = textProvider.messages;
          final errorMessage = inCall ? voice.errorMessage : textProvider.errorMessage;

          return Column(
            children: [
              if (inCall) _VoiceStatusBar(state: voice.state),
              if (session.buildJobProvider != null) BuildWorkspacePanel(provider: session.buildJobProvider!),
              Expanded(
                child: messages.isEmpty
                    ? (inCall
                        ? Center(child: SanaOrb(size: 180, voiceState: voice.state))
                        : _EmptyState(mode: session.mode))
                    : ListView.builder(
                        controller: session.scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length + (!inCall && textProvider.isThinking ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == messages.length) {
                            return const ThinkingIndicator();
                          }
                          return ChatBubble(message: messages[index], modeColor: session.mode.color);
                        },
                      ),
              ),
              if (errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ErrorBanner(message: errorMessage),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: inCall
                      ? VoiceActiveBar(voiceState: voice.state, onCancel: onToggleVoice, onDone: onToggleVoice)
                      : ConversationInputBar(
                          controller: session.controller,
                          modeTitle: session.mode.title,
                          onSend: onSend,
                          onMic: onToggleVoice,
                          onMore: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('More options are coming in a later phase.')),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VoiceStatusBar extends StatelessWidget {
  const _VoiceStatusBar({required this.state});

  final VoiceState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      VoiceState.connecting => 'Connecting…',
      VoiceState.listening => 'Listening…',
      VoiceState.thinking => 'SANA is thinking…',
      VoiceState.speaking => 'SANA is speaking…',
      VoiceState.error => 'Voice error',
      VoiceState.idle => '',
    };
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      child: Text(label, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.mode});

  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SanaOrb(size: 180),
            const SizedBox(height: 28),
            Text(
              _openingLineFor(mode.id),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Text(
              'Tap the mic to talk with SANA out loud.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  static String _openingLineFor(String modeId) {
    switch (modeId) {
      case 'debate':
        return "I'm ready to debate. Bring me a claim or a position — "
            "I'll challenge it, ask questions, and help you pressure-test your thinking.";
      case 'brainstorm':
        return 'Tell me an idea — even a rough one — and I\'ll help you '
            'expand it, explore angles, and shape it into something concrete.';
      case 'build':
        return "Tell me what you want to build. I'll ask what's needed "
            'and help turn it into a clear plan.';
      default:
        return "Let's talk.";
    }
  }
}
