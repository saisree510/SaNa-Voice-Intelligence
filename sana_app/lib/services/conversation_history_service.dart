import '../features/conversation/models/chat_message.dart';

/// Persists a mode's conversation across screen visits and app restarts
/// (spec §15: "Design the architecture so conversation history can
/// later be persisted securely"). Keyed by user + mode so switching
/// modes or accounts never mixes histories.
abstract interface class ConversationHistoryService {
  Future<List<ChatMessage>> load(String userId, String modeId);

  Future<void> save(String userId, String modeId, List<ChatMessage> messages);
}
