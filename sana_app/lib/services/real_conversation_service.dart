import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/errors/app_exception.dart';
import '../features/conversation/models/chat_message.dart';
import 'backend_error.dart';
import 'conversation_service.dart';

/// [ConversationService] backed by the real sana_backend (POST
/// /chat/message) — see sana_backend/app/services/chat_service.py.
/// Replaces [MockConversationService]'s canned templates with real
/// mode-specific AI replies.
///
/// [_conversationId] tracks which backend thread subsequent messages
/// continue — the backend loads prior turns by that id, not from
/// [history] (which this implementation ignores; [history] exists for
/// [MockConversationService], which has no server-side memory). Starts
/// null (fresh conversation on first send); [startNewConversation] and
/// [resumeConversation] are how [ConversationProvider] points it at a
/// different thread — see ConversationHistoryScreen.
class RealConversationService implements ConversationService {
  RealConversationService({required String? Function() getAuthToken, http.Client? httpClient})
      : _getAuthToken = getAuthToken,
        _http = httpClient ?? http.Client();

  final String? Function() _getAuthToken;
  final http.Client _http;
  String? _conversationId;

  @override
  Future<String> sendMessage({
    required String modeId,
    required List<ChatMessage> history,
    required String userText,
  }) async {
    final token = _getAuthToken();
    if (token == null) {
      throw const AuthException('You need to be logged in to chat with SANA.');
    }

    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/chat/message'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'conversation_id': _conversationId, 'mode': modeId, 'message': userText}),
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's servers. Check your connection and try again.", e);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _conversationId = data['conversation_id'] as String;
      return data['response'] as String;
    }

    if (response.statusCode == 401) {
      throw const AuthException('Your session has expired. Please log in again.');
    }

    throw AiException(extractBackendErrorDetail(response) ?? "SANA couldn't generate a response. Please try again.");
  }

  @override
  void startNewConversation() {
    _conversationId = null;
  }

  @override
  void resumeConversation(String conversationId) {
    _conversationId = conversationId;
  }
}
