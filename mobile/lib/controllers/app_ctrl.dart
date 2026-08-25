import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:livekit_components/livekit_components.dart' as components;
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'conversation_timeline.dart';
import '../models/conversation_model.dart';
import '../models/conversation_turn.dart';
import '../services/conversation_memory.dart';
import '../services/conversation_service.dart';
import '../services/token_service.dart';
import '../services/architecture_service.dart';

final String homepageAgentTokenEndpoint = 'https://livekit.com/api/homepage-agent/token';

enum AppScreenState { welcome, agent }

enum AgentScreenState { visualizer, transcription }

enum HomeTab { home, history, projects, profile }

/// Product modes — only General is live in Phase 5; others are UI shells.
enum ConversationMode {
  general,
  debate,
  brainstorm,
  build,
}

extension ConversationModeLabel on ConversationMode {
  String get label => switch (this) {
        ConversationMode.general => 'General',
        ConversationMode.debate => 'Debate',
        ConversationMode.brainstorm => 'Brainstorm',
        ConversationMode.build => 'Build',
      };
}

class AppCtrl extends ChangeNotifier {
  static const uuid = Uuid();
  static final _logger = Logger('AppCtrl');
  static const Duration connectTimeout = Duration(seconds: 45);
  static const Duration endTimeout = Duration(seconds: 12);

  /// Placeholder fallback if user name is not set.
  static const String placeholderUserName = 'Sai';
  String _customUserName = placeholderUserName;

  void updateUserName(String? name) {
    final cleanName = name?.trim();
    if (cleanName != null && cleanName.isNotEmpty && cleanName != _customUserName) {
      _customUserName = cleanName;
      notifyListeners();
    }
  }

  // States
  AppScreenState appScreenState = AppScreenState.welcome;
  AgentScreenState agentScreenState = AgentScreenState.visualizer;
  HomeTab homeTab = HomeTab.home;
  ConversationMode conversationMode = ConversationMode.general;
  bool isCanvasFocusVisible = false;

  //Test
  bool isUserCameEnabled = false;
  bool isScreenshareEnabled = false;

  String get greetingLine {
    switch (conversationMode) {
      case ConversationMode.general:
        return 'Hey $_customUserName, what are we planning to do today?';
      case ConversationMode.debate:
        return 'Ready to test your ideas, $_customUserName? What topic shall we debate about?';
      case ConversationMode.brainstorm:
        return 'Okay $_customUserName, what are we brainstorming about?';
      case ConversationMode.build:
        return 'Hey $_customUserName, ready to build a new project? What feature shall we build today?';
    }
  }

  final messageCtrl = TextEditingController();
  final messageFocusNode = FocusNode();

  late final sdk.Room room = sdk.Room(roomOptions: const sdk.RoomOptions(enableVisualizer: true));
  late final roomContext = components.RoomContext(room: room);
  late final sdk.Session session = _createSession(room: room);
  late final ConversationTimeline conversationTimeline = ConversationTimeline(session);

  String? activeConversationId;
  String? activeArchitectureId;
  ConversationService? _conversationService;
  ArchitectureService? _architectureService;
  sdk.EventsListener<sdk.RoomEvent>? _roomListener;
  List<PersistedMessage> _restoredMessages = const [];
  String? _restoreRetriesScheduledForConversationId;

  void bindArchitectureService(ArchitectureService service) {
    _architectureService = service;
  }

  void bindConversationService(ConversationService service) {
    _conversationService = service;
    conversationTimeline.onFinalTurn = (turn) {
      if (activeConversationId != null && _conversationService != null) {
        final role = turn.role == ConversationRole.user ? 'user' : 'assistant';
        final source = turn.source == ConversationSource.voice ? 'voice' : 'text';

        unawaited(_conversationService!.saveMessage(
          conversationId: activeConversationId!,
          sender: role,
          content: turn.text,
          source: source,
          idempotencyKey: turn.id,
        ));
      }
    };
  }

  Future<void> ensureActiveConversation() async {
    if (_conversationService != null) {
      // Check if current activeConversationId was deleted or is missing
      if (activeConversationId != null) {
        final exists = _conversationService!.conversations.any((c) => c.id == activeConversationId);
        if (!exists) {
          activeConversationId = null;
        }
      }

      if (activeConversationId == null) {
        final session = await _conversationService!.createConversation(
          title: 'New Conversation',
          mode: conversationMode.name,
        );
        activeConversationId = session.id;
      }
    }
  }

  Future<void> openPastConversation(
    dynamic sessionModel,
    ConversationService service,
  ) async {
    bindConversationService(service);
    activeConversationId = sessionModel.id as String;

    // Restore conversation mode from past session
    if (sessionModel.mode != null) {
      final modeStr = sessionModel.mode.toString().toLowerCase();
      final modeMatch = ConversationMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => ConversationMode.general,
      );
      setConversationMode(modeMatch);
    }

    final messages = await service.fetchMessages(sessionModel.id as String);
    _restoredMessages = List.unmodifiable(messages);
    conversationTimeline.rehydrateTurns(messages);
    appScreenState = AppScreenState.agent;
    notifyListeners();

    // Auto-connect voice session if disconnected
    if (session.connectionState == sdk.ConnectionState.disconnected && !isSessionStarting) {
      unawaited(connect());
    } else if (session.connectionState == sdk.ConnectionState.connected) {
      _scheduleConversationRestorePackets();
    }
  }

  void _scheduleConversationRestorePackets() {
    final conversationId = activeConversationId;
    if (conversationId == null || _restoredMessages.isEmpty) return;
    if (_restoreRetriesScheduledForConversationId == conversationId) return;
    _restoreRetriesScheduledForConversationId = conversationId;

    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 600),
      Duration(seconds: 2),
      Duration(seconds: 5),
    ];
    for (final delay in retryDelays) {
      Future.delayed(delay, () {
        if (activeConversationId != conversationId || room.connectionState != sdk.ConnectionState.connected) {
          return;
        }
        _publishConversationRestorePacket(conversationId);
      });
    }
  }

  void _publishConversationRestorePacket(String conversationId) {
    final participant = room.localParticipant;
    if (participant == null) return;
    try {
      final payload = buildConversationRestorePayload(
        conversationId: conversationId,
        messages: _restoredMessages,
        mode: conversationMode.name,
      );
      unawaited(participant.publishData(utf8.encode(jsonEncode(payload))));
      _logger.info(
        'Sent conversation restore packet for $conversationId '
        'with ${(payload['messages'] as List).length} turns.',
      );
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to send conversation restore packet: $error',
        error,
        stackTrace,
      );
    }
  }

  static sdk.Session _createSession({required sdk.Room room}) {
    const configuredAgentName = String.fromEnvironment('SANA_AGENT_NAME');
    final agentName =
        configuredAgentName.isNotEmpty ? configuredAgentName : (kReleaseMode ? 'voice_agent' : 'voice_agent_local');
    // Development-only hardcoded credentials (optional).
    const hardcodedServerUrl = null; // e.g. 'wss://your-host'
    const hardcodedToken = null; // e.g. 'eyJ...'

    if (hardcodedServerUrl != null && hardcodedToken != null) {
      return sdk.Session.fromFixedTokenSource(
        sdk.LiteralTokenSource(
          serverUrl: hardcodedServerUrl,
          participantToken: hardcodedToken,
        ),
        options: sdk.SessionOptions(room: room),
      );
    }

    // Use AuthenticatedTokenSource to attach Supabase JWT headers
    final tokenSource = AuthenticatedTokenSource();

    return sdk.Session.withAgent(
      agentName,
      tokenSource: tokenSource,
      options: sdk.SessionOptions(
        room: room,
      ),
    );
  }

  bool isSendButtonEnabled = false;
  bool isSessionStarting = false;
  String? connectionError;
  bool _hasCleanedUp = false;

  /// True while a connect attempt is in-flight or LiveKit reports connecting.
  bool get isConnecting => isSessionStarting || session.connectionState == sdk.ConnectionState.connecting;

  /// Welcome-screen control should offer cancel whenever connect is active or
  /// the session is not fully idle on the welcome screen.
  bool get canCancelConnect =>
      isConnecting ||
      session.connectionState == sdk.ConnectionState.connected ||
      session.connectionState == sdk.ConnectionState.reconnecting;

  AppCtrl() {
    final format = DateFormat('HH:mm:ss');
    // configure logs for debugging
    Logger.root.level = Level.FINE;
    Logger.root.onRecord.listen((record) {
      debugPrint('${format.format(record.time)}: ${record.message}');
    });

    messageCtrl.addListener(() {
      final newValue = messageCtrl.text.isNotEmpty;
      if (newValue != isSendButtonEnabled) {
        isSendButtonEnabled = newValue;
        notifyListeners();
      }
    });

    session.addListener(_handleSessionChange);

    _roomListener = room.createListener();
    _roomListener!.on<sdk.DataReceivedEvent>((event) {
      try {
        final decoded = utf8.decode(event.data);
        final payload = jsonDecode(decoded);
        if (payload is Map && payload['type'] == 'architecture_created') {
          final archId = payload['architecture_id'] as String;
          _logger.info('Received architecture_created packet for $archId');
          activeArchitectureId = archId;
          notifyListeners();
          if (_architectureService != null) {
            unawaited(_architectureService!.fetchArchitectureById(archId));
          }
        }
      } catch (e, st) {
        _logger.warning('Error handling room data event: $e', e, st);
      }
    });
  }

  Future<void> cleanUp() async {
    if (_hasCleanedUp) return;
    _hasCleanedUp = true;

    conversationTimeline.dispose();
    session.removeListener(_handleSessionChange);
    unawaited(_roomListener?.dispose());
    _roomListener = null;
    await session.dispose();
    await room.dispose();
    roomContext.dispose();
    messageCtrl.dispose();
    messageFocusNode.dispose();
  }

  @override
  void dispose() {
    unawaited(cleanUp());
    super.dispose();
  }

  Future<void> sendMessage() async {
    isSendButtonEnabled = false;

    final text = messageCtrl.text.trim();
    messageCtrl.clear();
    notifyListeners();

    if (text.isEmpty) return;

    // Prefer transcript sheet when the user is actively chatting by text.
    if (agentScreenState != AgentScreenState.transcription) {
      agentScreenState = AgentScreenState.transcription;
      notifyListeners();
    }

    final sent = await session.sendText(text);
    if (sent != null) {
      // Same session timeline as voice; id is the client idempotency key.
      conversationTimeline.trackClientSend(sent);
    }
  }

  void toggleUserCamera(components.MediaDeviceContext? deviceCtx) {
    isUserCameEnabled = !isUserCameEnabled;
    isUserCameEnabled ? deviceCtx?.enableCamera() : deviceCtx?.disableCamera();
    notifyListeners();
  }

  void toggleScreenShare() {
    isScreenshareEnabled = !isScreenshareEnabled;
    notifyListeners();
  }

  void toggleAgentScreenMode() {
    if (isCanvasFocusVisible) {
      isCanvasFocusVisible = false;
      agentScreenState = AgentScreenState.transcription;
      notifyListeners();
      return;
    }

    agentScreenState =
        agentScreenState == AgentScreenState.visualizer ? AgentScreenState.transcription : AgentScreenState.visualizer;
    if (agentScreenState == AgentScreenState.visualizer) {
      isCanvasFocusVisible = false;
    }
    notifyListeners();
  }

  void setCanvasFocusVisible(bool isVisible) {
    if (isCanvasFocusVisible == isVisible) return;
    isCanvasFocusVisible = isVisible;
    notifyListeners();
  }

  void setHomeTab(HomeTab tab) {
    if (tab == homeTab) return;
    homeTab = tab;
    notifyListeners();
  }

  void setConversationMode(ConversationMode mode) {
    if (mode == conversationMode) return;
    final oldMode = conversationMode;
    conversationMode = mode;
    notifyListeners();

    // Send mode switch data packet to live voice agent if connected
    if (room.connectionState == sdk.ConnectionState.connected && room.localParticipant != null) {
      try {
        unawaited(_publishModeMetadata());
        final payload = json.encode({
          'type': 'mode_switch',
          'mode': mode.name,
        });
        unawaited(room.localParticipant!.publishData(
          utf8.encode(payload),
        ));
      } catch (e) {
        _logger.warning('Failed to send mode switch packet: $e');
      }
    }

    if (activeConversationId != null && _conversationService != null) {
      unawaited(_conversationService!.updateMode(
        conversationId: activeConversationId!,
        mode: mode.name,
        fromMode: oldMode.name,
      ));
    }
  }

  String? _currentSessionUserId() {
    final identity = room.localParticipant?.identity;
    if (identity == null || identity.isEmpty) return null;
    if (identity.startsWith('user-') && identity.length > 5) {
      return identity.substring(5);
    }
    return identity;
  }

  Future<void> _publishModeMetadata() async {
    final participant = room.localParticipant;
    if (participant == null) return;

    final metadata = <String, String>{
      'mode': conversationMode.name,
    };
    final userId = _currentSessionUserId();
    if (userId != null && userId.isNotEmpty) {
      metadata['user_id'] = userId;
    }

    await participant.setMetadata(json.encode(metadata));
  }

  void _sendInitialModePacket({int attempt = 0}) {
    if (room.connectionState != sdk.ConnectionState.connected) return;

    if (room.localParticipant != null) {
      try {
        unawaited(_publishModeMetadata());
        final payload = json.encode({
          'type': 'mode_switch',
          'mode': conversationMode.name,
          'is_initial': true,
        });
        unawaited(room.localParticipant!.publishData(
          utf8.encode(payload),
        ));
        _logger.info('Sent initial mode metadata & packet for mode: ${conversationMode.name}');
      } catch (e) {
        _logger.warning('Failed to send initial mode packet (attempt $attempt): $e');
        if (attempt < 4) {
          Future.delayed(const Duration(milliseconds: 300), () {
            _sendInitialModePacket(attempt: attempt + 1);
          });
        }
      }
    } else if (attempt < 4) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _sendInitialModePacket(attempt: attempt + 1);
      });
    }
  }

  Future<void> connect() async {
    if (isSessionStarting) {
      _logger.fine('Connection attempt ignored: session already starting.');
      return;
    }

    // Resume UI if media session is already live.
    if (session.connectionState == sdk.ConnectionState.connected ||
        session.connectionState == sdk.ConnectionState.reconnecting) {
      _logger.info('Session already ${session.connectionState}; showing agent screen.');
      appScreenState = AppScreenState.agent;
      notifyListeners();
      return;
    }

    _logger.info('Starting session connection…');
    isSessionStarting = true;
    connectionError = null;
    notifyListeners();

    try {
      await session.start().timeout(connectTimeout);

      if (room.connectionState == sdk.ConnectionState.connected ||
          session.connectionState == sdk.ConnectionState.connected ||
          session.connectionState == sdk.ConnectionState.reconnecting) {
        // Persist a new record only after LiveKit has accepted the session.
        await ensureActiveConversation();
        appScreenState = AppScreenState.agent;
        notifyListeners();
      } else {
        _logger.warning(
          'Session start finished without a ready connection '
          '(state=${session.connectionState}). Resetting.',
        );
        connectionError = session.error?.message ??
            session.agent.error?.message ??
            'LiveKit did not establish a voice session. Please try again.';
        await _resetToWelcome();
      }
    } on TimeoutException catch (error, stackTrace) {
      _logger.severe('Connection timed out after $connectTimeout', error, stackTrace);
      connectionError = 'Connection timed out. Please try again.';
      await _resetToWelcome();
    } catch (error, stackTrace) {
      _logger.severe('Connection error: $error', error, stackTrace);
      connectionError = _connectionErrorMessage(error);
      await _resetToWelcome();
    } finally {
      if (isSessionStarting) {
        isSessionStarting = false;
        notifyListeners();
      }
    }
  }

  /// Cancel an in-flight connect or force-return to a clean welcome state.
  Future<void> cancelConnect() => disconnect();

  Future<void> disconnect() async {
    _logger.info('Disconnecting session…');
    isSessionStarting = false;
    await _resetToWelcome();
  }

  Future<void> _resetToWelcome() async {
    try {
      await session.end().timeout(endTimeout);
    } catch (error, stackTrace) {
      _logger.warning('session.end during reset: $error', error, stackTrace);
    }

    try {
      session.dismissError();
    } catch (error, stackTrace) {
      _logger.fine('dismissError during reset: $error', error, stackTrace);
    }

    activeConversationId = null;
    activeArchitectureId = null;
    _restoredMessages = const [];
    _restoreRetriesScheduledForConversationId = null;
    session.restoreMessageHistory(const []);
    conversationTimeline.clear();
    if (_architectureService != null) {
      _architectureService!.disconnectFromCanvasStream();
    }
    appScreenState = AppScreenState.welcome;
    agentScreenState = AgentScreenState.visualizer;
    isCanvasFocusVisible = false;
    notifyListeners();
  }

  String _connectionErrorMessage(Object error) {
    final message = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (message.isEmpty || message.length > 180) {
      return 'Unable to start the conversation. Please try again.';
    }
    return message;
  }

  bool _initialModePacketSent = false;

  void _handleSessionChange() {
    final sdk.ConnectionState state = session.connectionState;
    AppScreenState? nextScreen;
    switch (state) {
      case sdk.ConnectionState.connected:
        _scheduleConversationRestorePackets();
        if (!_initialModePacketSent) {
          _initialModePacketSent = true;
          _sendInitialModePacket();
        }
        try {
          unawaited(room.localParticipant?.setMicrophoneEnabled(true));
        } catch (e) {
          _logger.warning('Failed to enable mic on connection: $e');
        }
        nextScreen = AppScreenState.agent;
        break;
      case sdk.ConnectionState.reconnecting:
        nextScreen = AppScreenState.agent;
        break;
      case sdk.ConnectionState.disconnected:
        _initialModePacketSent = false;
        nextScreen = AppScreenState.welcome;
        break;
      case sdk.ConnectionState.connecting:
        nextScreen = null;
        break;
    }

    var shouldNotify = false;
    if (nextScreen != null && nextScreen != appScreenState) {
      appScreenState = nextScreen;
      shouldNotify = true;
    }

    // Ensure welcome never stays locked after a remote disconnect.
    if (state == sdk.ConnectionState.disconnected && isSessionStarting) {
      isSessionStarting = false;
      shouldNotify = true;
    }

    if (shouldNotify) {
      notifyListeners();
    }
  }
}

class AuthenticatedTokenSource implements sdk.TokenSourceConfigurable {
  final TokenService tokenService = TokenService();

  @override
  Future<sdk.TokenSourceResponse> fetch(sdk.TokenRequestOptions options) async {
    final res = await tokenService.fetchToken(
      mode: 'general', // Mode will be updated in setConversationMode if needed
      roomName: options.roomName,
    );
    if (res == null) {
      throw Exception('Failed to fetch authenticated token from backend');
    }
    return sdk.TokenSourceResponse(
      serverUrl: res.url,
      participantToken: res.token,
      roomName: res.roomName,
      participantName: res.participantIdentity,
    );
  }
}
