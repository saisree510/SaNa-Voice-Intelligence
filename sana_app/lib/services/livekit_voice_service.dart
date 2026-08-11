import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// livekit_client also exports its own unrelated `ChatMessage` (data-stream
// chat) — hidden here since this file uses SANA's own ChatMessage model.
import 'package:livekit_client/livekit_client.dart' hide ChatMessage;
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/app_config.dart';
import '../core/errors/app_exception.dart';
import '../features/conversation/models/chat_message.dart';
import 'voice_service.dart';

/// Fetches a LiveKit connection token from the SANA backend
/// (sana_backend/app/api/voice.py) — the mobile app never talks to
/// LiveKit's servers without going through our backend first, so the
/// LiveKit API secret never has to exist on-device.
class _SanaTokenSource implements TokenSourceFixed {
  _SanaTokenSource({
    required this.modeId,
    required this.userId,
    required this.userName,
    required this.resumeConversationId,
  });

  final String modeId;
  final String userId;
  final String userName;
  // Passed straight through to the backend if non-null (see
  // app/api/voice.py's TokenRequest.conversation_id) to continue that
  // conversation instead of starting a new one.
  final String? resumeConversationId;

  // Set by fetch() once the response arrives -- LiveKitVoiceService.start()
  // reads this straight after `await session.start()` to learn (or
  // re-confirm) which conversation this call belongs to. There's no
  // richer return path than TokenSourceResponse's fixed shape (roomName
  // etc.), so this is the plain, direct way to hand an extra value back
  // to the caller that constructed this source.
  String? resolvedConversationId;

  @override
  Future<TokenSourceResponse> fetch() async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/api/voice/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mode': modeId,
          'user_id': userId,
          'user_name': userName,
          if (resumeConversationId != null) 'conversation_id': resumeConversationId,
        }),
      );
    } catch (e) {
      throw NetworkException(
        "Couldn't reach SANA's voice service. Is the backend running?",
        e,
      );
    }
    if (response.statusCode != 200) {
      throw NetworkException('Voice service returned an error (${response.statusCode}).');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    resolvedConversationId = data['conversation_id'] as String?;
    return TokenSourceResponse(
      serverUrl: data['url'] as String,
      participantToken: data['token'] as String,
      roomName: data['room_name'] as String?,
    );
  }
}

/// Real-time voice via LiveKit. Wraps [Session] (from livekit_client)
/// and translates its [Agent]/connection state into [VoiceState] plus
/// [ChatMessage]s, so the rest of the app never touches LiveKit types
/// directly — see VoiceService's doc comment for why this boundary
/// exists.
class LiveKitVoiceService extends VoiceService {
  Session? _session;
  VoiceState _state = VoiceState.idle;
  String? _errorMessage;
  bool _disposed = false;
  String? _conversationId;

  @override
  String? get conversationId => _conversationId;

  @override
  void startNewConversation() => _conversationId = null;

  @override
  void resumeConversation(String conversationId) => _conversationId = conversationId;

  /// [end]'s cleanup is async but [dispose] can't await it (Flutter's
  /// dispose() is sync) — it fires end() and returns immediately, so
  /// end()'s trailing notifyListeners() can resume *after* super.dispose()
  /// already ran. Confirmed by testing: "A LiveKitVoiceService was used
  /// after being disposed." This guard is what actually fixes it.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  VoiceState get state => _state;

  @override
  String? get errorMessage => _errorMessage;

  @override
  List<ChatMessage> get transcript => _session == null ? const [] : _mapMessages(_session!.messages);

  @override
  Future<void> start({required String modeId, required String userId, required String userName}) async {
    if (_session != null) return;

    final isMobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    if (!kIsWeb && isMobile) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        _errorMessage = const PermissionException(
          'Microphone access is needed for voice mode. Enable it in Settings.',
        ).message;
        _state = VoiceState.error;
        _safeNotify();
        return;
      }
    }

    // Continues _conversationId if this isn't the first call this app
    // session (see VoiceService.conversationId's doc comment) — the
    // backend creates a fresh one and hands it back if it's null.
    final tokenSource = _SanaTokenSource(
      modeId: modeId,
      userId: userId,
      userName: userName,
      resumeConversationId: _conversationId,
    );
    final session = Session.fromFixedTokenSource(tokenSource);
    _session = session;
    session.addListener(_onSessionChanged);

    _state = VoiceState.connecting;
    _errorMessage = null;
    _safeNotify();

    await session.start();
    _conversationId = tokenSource.resolvedConversationId ?? _conversationId;
  }

  @override
  Future<void> sendText(String text) async {
    await _session?.sendText(text);
  }

  @override
  Future<void> end() async {
    final session = _session;
    if (session == null) return;
    session.removeListener(_onSessionChanged);
    // The button getting stuck showing "in call" (never resetting) is
    // exactly what happens if session.end() hangs or throws — the old
    // code only reset _state to idle *after* a successful await. try/
    // finally guarantees the UI always returns to idle, even if the
    // underlying LiveKit disconnect has trouble.
    try {
      await session.end();
    } finally {
      session.dispose();
      _session = null;
      _state = VoiceState.idle;
      _errorMessage = null;
      _safeNotify();
    }
  }

  void _onSessionChanged() {
    final session = _session;
    if (session == null) return;

    if (session.error != null) {
      _errorMessage = session.error!.message;
      _state = VoiceState.error;
      _safeNotify();
      return;
    }

    if (!session.isConnected) {
      _state = VoiceState.connecting;
      _safeNotify();
      return;
    }

    final next = switch (session.agent.agentState) {
      AgentState.listening => VoiceState.listening,
      AgentState.thinking => VoiceState.thinking,
      AgentState.speaking => VoiceState.speaking,
      AgentState.idle || AgentState.initializing || null => VoiceState.connecting,
    };
    _state = next;
    _safeNotify();
  }

  List<ChatMessage> _mapMessages(List<ReceivedMessage> raw) {
    return raw.map((m) {
      final content = m.content;
      final role = content is AgentTranscript ? ChatRole.sana : ChatRole.user;
      return ChatMessage(id: m.id, role: role, text: content.text, timestamp: m.timestamp);
    }).toList(growable: false);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(end());
    super.dispose();
  }
}
