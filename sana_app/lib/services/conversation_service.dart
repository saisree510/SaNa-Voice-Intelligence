import '../features/conversation/models/chat_message.dart';

/// The one seam the UI talks to for getting SANA's next reply.
///
/// [MockConversationService] is V1's implementation — local templates,
/// no network call. The real implementation (Phase 5 "for real") will
/// call a backend that holds the LLM system prompt for [modeId] and the
/// provider API key server-side (see README §17–18: the key never lives
/// in this app). No screen or provider changes when that swap happens.
abstract interface class ConversationService {
  /// The backend conversation thread subsequent [sendMessage] calls
  /// continue, if any — null before the first message of a fresh
  /// conversation. Build mode uses this to find "the build job(s) tied
  /// to this conversation" (see BuildJobProvider) without introducing
  /// a second, parallel id of its own.
  String? get conversationId;

  /// [modeId] is one of 'debate' | 'brainstorm' | 'build' (see [AppModes]).
  /// [history] is the conversation so far, oldest first, not including
  /// [userText]. Returns SANA's reply text.
  Future<String> sendMessage({
    required String modeId,
    required List<ChatMessage> history,
    required String userText,
  });

  /// Starts a fresh thread — the next [sendMessage] won't continue
  /// whatever conversation was active before. No-op for providers with
  /// no server-side conversation concept (the mock).
  void startNewConversation();

  /// Points subsequent [sendMessage] calls at an existing conversation
  /// (e.g. one the user picked from their history) instead of starting
  /// a new one. No-op for the mock.
  void resumeConversation(String conversationId);
}
