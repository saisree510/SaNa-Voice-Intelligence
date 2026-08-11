import '../features/conversation/models/chat_message.dart';

/// Persists a mode's conversation across screen visits and app restarts
/// (spec §15: "Design the architecture so conversation history can
/// later be persisted securely"). Keyed by user + mode so switching
/// modes or accounts never mixes histories.
abstract interface class ConversationHistoryService {
  Future<List<ChatMessage>> load(String userId, String modeId);

  Future<void> save(String userId, String modeId, List<ChatMessage> messages);

  /// The backend conversation id this mode was last continuing, if any —
  /// separate from [load]/[save] (which only cache the *messages*).
  /// Without this, a page refresh/app restart still shows the cached
  /// messages but has no idea which backend thread they belong to, so
  /// the next message silently starts a brand-new conversation while
  /// the old messages stay on screen — two conversations rendered as
  /// one, out of order. Restoring this before the first send is what
  /// prevents that.
  Future<String?> loadActiveConversationId(String userId, String modeId);

  /// [conversationId] null clears it (see [ConversationProvider.startNewConversation]).
  Future<void> saveActiveConversationId(String userId, String modeId, String? conversationId);
}
