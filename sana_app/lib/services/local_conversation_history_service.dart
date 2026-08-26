import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/conversation/models/chat_message.dart';
import 'conversation_history_service.dart';

/// [ConversationHistoryService] backed by on-device storage, the same
/// pattern as [LocalUserProfileService]. Real persistence (not mocked
/// away) — this is what makes a conversation still be there after
/// hanging up a voice call, switching modes, or reopening the app.
class LocalConversationHistoryService implements ConversationHistoryService {
  String _keyFor(String userId, String modeId) => 'sana_history_${userId}_$modeId';
  String _conversationIdKeyFor(String userId, String modeId) => 'sana_active_conversation_${userId}_$modeId';

  @override
  Future<List<ChatMessage>> load(String userId, String modeId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(userId, modeId));
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> save(String userId, String modeId, List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyFor(userId, modeId),
      jsonEncode(messages.map((m) => m.toJson()).toList()),
    );
  }

  @override
  Future<String?> loadActiveConversationId(String userId, String modeId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_conversationIdKeyFor(userId, modeId));
  }

  @override
  Future<void> saveActiveConversationId(String userId, String modeId, String? conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _conversationIdKeyFor(userId, modeId);
    if (conversationId == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, conversationId);
    }
  }
}
