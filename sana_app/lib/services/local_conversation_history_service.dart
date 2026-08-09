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
}
