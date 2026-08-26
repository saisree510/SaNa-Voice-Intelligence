import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/errors/app_exception.dart';
import '../features/conversation/models/chat_message.dart';
import '../features/conversation/models/conversation_summary.dart';
import 'backend_error.dart';

/// Browses conversations already stored server-side (sana_backend's
/// GET /conversations, GET /conversations/{id}) — separate from
/// [ConversationHistoryService], which persists the *currently active*
/// conversation locally on-device. This is for picking a *different*,
/// previously-had conversation to resume.
abstract interface class ConversationHistoryApiService {
  Future<List<ConversationSummary>> listConversations({required String authToken});

  Future<List<ChatMessage>> getConversationMessages({
    required String authToken,
    required String conversationId,
  });
}

class RealConversationHistoryApiService implements ConversationHistoryApiService {
  RealConversationHistoryApiService({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  @override
  Future<List<ConversationSummary>> listConversations({required String authToken}) async {
    final http.Response response;
    try {
      response = await _http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/conversations'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's servers. Check your connection and try again.", e);
    }
    if (response.statusCode != 200) {
      throw AiException(extractBackendErrorDetail(response) ?? 'Could not load your past conversations.');
    }
    final list = jsonDecode(response.body) as List;
    return list.map((e) => ConversationSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<ChatMessage>> getConversationMessages({
    required String authToken,
    required String conversationId,
  }) async {
    final http.Response response;
    try {
      response = await _http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/conversations/$conversationId'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's servers. Check your connection and try again.", e);
    }
    if (response.statusCode != 200) {
      throw AiException(extractBackendErrorDetail(response) ?? 'Could not load that conversation.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawMessages = data['messages'] as List;
    return rawMessages.map((m) {
      final map = m as Map<String, dynamic>;
      final role = map['role'] == 'assistant' ? ChatRole.sana : ChatRole.user;
      return ChatMessage(
        id: map['id'] as String,
        role: role,
        text: map['content'] as String,
        timestamp: DateTime.parse(map['created_at'] as String),
      );
    }).toList();
  }
}
