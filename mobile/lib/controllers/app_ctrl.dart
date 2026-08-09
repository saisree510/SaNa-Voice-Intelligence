import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:livekit_components/livekit_components.dart' as components;
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'conversation_timeline.dart';

final String homepageAgentTokenEndpoint = 'https://livekit.com/api/homepage-agent/token';

enum AppScreenState { welcome, agent }

enum AgentScreenState { visualizer, transcription }

class AppCtrl extends ChangeNotifier {
  static const uuid = Uuid();
  static final _logger = Logger('AppCtrl');
  static const Duration connectTimeout = Duration(seconds: 45);
  static const Duration endTimeout = Duration(seconds: 12);

  // States
  AppScreenState appScreenState = AppScreenState.welcome;
  AgentScreenState agentScreenState = AgentScreenState.visualizer;

  //Test
  bool isUserCameEnabled = false;
  bool isScreenshareEnabled = false;

  final messageCtrl = TextEditingController();
  final messageFocusNode = FocusNode();

  late final sdk.Room room = sdk.Room(roomOptions: const sdk.RoomOptions(enableVisualizer: true));
  late final roomContext = components.RoomContext(room: room);
  late final sdk.Session session = _createSession(room: room);
  late final ConversationTimeline conversationTimeline = ConversationTimeline(session);

  static sdk.Session _createSession({required sdk.Room room}) {
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

    final sandboxId = dotenv.env['LIVEKIT_SANDBOX_ID']?.replaceAll('"', '');
    final sdk.TokenSourceConfigurable tokenSource;
    if (sandboxId == null || sandboxId.isEmpty || sandboxId == '<your-sandbox-id>') {
      tokenSource = sdk.EndpointTokenSource(url: Uri.parse(homepageAgentTokenEndpoint));
    } else {
      // Development sandbox token server (ID only; no API secret in Flutter).
      tokenSource = sdk.SandboxTokenSource(sandboxId: sandboxId);
    }

    // Explicitly dispatch the SaNa cloud agent by name.
    return sdk.Session.withAgent(
      'voice_agent',
      tokenSource: tokenSource,
      options: sdk.SessionOptions(room: room),
    );
  }

  bool isSendButtonEnabled = false;
  bool isSessionStarting = false;
  bool _hasCleanedUp = false;

  /// True while a connect attempt is in-flight or LiveKit reports connecting.
  bool get isConnecting =>
      isSessionStarting || session.connectionState == sdk.ConnectionState.connecting;

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
    conversationTimeline.addListener(_handleTimelineChange);
  }

  Future<void> cleanUp() async {
    if (_hasCleanedUp) return;
    _hasCleanedUp = true;

    conversationTimeline.removeListener(_handleTimelineChange);
    conversationTimeline.dispose();
    session.removeListener(_handleSessionChange);
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
    agentScreenState =
        agentScreenState == AgentScreenState.visualizer ? AgentScreenState.transcription : AgentScreenState.visualizer;
    notifyListeners();
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
    notifyListeners();

    try {
      await session.start().timeout(connectTimeout);
      if (session.connectionState == sdk.ConnectionState.connected ||
          session.connectionState == sdk.ConnectionState.reconnecting) {
        appScreenState = AppScreenState.agent;
        notifyListeners();
      } else {
        _logger.warning(
          'Session start finished without a ready connection '
          '(state=${session.connectionState}). Resetting.',
        );
        await _resetToWelcome();
      }
    } on TimeoutException catch (error, stackTrace) {
      _logger.severe('Connection timed out after $connectTimeout', error, stackTrace);
      await _resetToWelcome();
    } catch (error, stackTrace) {
      _logger.severe('Connection error: $error', error, stackTrace);
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

    session.restoreMessageHistory(const []);
    conversationTimeline.clear();
    appScreenState = AppScreenState.welcome;
    agentScreenState = AgentScreenState.visualizer;
    notifyListeners();
  }

  void _handleTimelineChange() {
    // Reveal the conversation sheet once the unified timeline has content.
    if (conversationTimeline.hasTurns &&
        appScreenState == AppScreenState.agent &&
        agentScreenState != AgentScreenState.transcription) {
      agentScreenState = AgentScreenState.transcription;
      notifyListeners();
    }
  }

  void _handleSessionChange() {
    final sdk.ConnectionState state = session.connectionState;
    AppScreenState? nextScreen;
    switch (state) {
      case sdk.ConnectionState.connected:
      case sdk.ConnectionState.reconnecting:
        // Keep agent UI visible across LiveKit automatic reconnect attempts.
        nextScreen = AppScreenState.agent;
        break;
      case sdk.ConnectionState.disconnected:
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
