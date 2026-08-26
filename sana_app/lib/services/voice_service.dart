import 'package:flutter/foundation.dart';

import '../features/conversation/models/chat_message.dart';

enum VoiceState { idle, connecting, listening, thinking, speaking, error }

/// The seam the UI talks to for real-time voice conversation with SANA.
///
/// [LiveKitVoiceService] is V1's implementation. Kept as its own
/// abstraction (separate from [ConversationService], which drives the
/// mock/text flow) because voice is a fundamentally different transport
/// — a live session, not one request per message — not because a swap
/// is expected soon.
abstract class VoiceService extends ChangeNotifier {
  VoiceState get state;

  /// Live transcript of the current voice session — both what the user
  /// said (speech-to-text) and what SANA said (text-to-speech source
  /// text) — in order. Empty when no session is active.
  List<ChatMessage> get transcript;

  String? get errorMessage;

  bool get isActive => state != VoiceState.idle;

  /// The backend conversation this voice session is (or will be) part
  /// of — null before the first ever [start] this app session, then
  /// whatever the backend resolved (freshly created or resumed) after
  /// that. Persists across [end]/[start] cycles so stopping the mic
  /// and turning it back on continues the same conversation instead of
  /// starting over — until [startNewConversation] or
  /// [resumeConversation] points it elsewhere.
  String? get conversationId;

  /// Starts a live voice session for the given mode. No-ops if a
  /// session is already active (call [end] first to switch modes).
  /// Continues [conversationId] if one is already known (see above);
  /// starts a brand-new conversation otherwise.
  Future<void> start({required String modeId, required String userId, required String userName});

  /// Sends a typed message over the active voice session — SANA
  /// replies with voice the same as if it had been spoken. No-ops if
  /// no session is active.
  Future<void> sendText(String text);

  /// Ends the current voice session, if any.
  Future<void> end();

  /// Forgets [conversationId] — the next [start] begins a brand-new
  /// conversation instead of continuing whatever was active. Mirrors
  /// [ConversationService.startNewConversation].
  void startNewConversation();

  /// Points the next [start] at an existing conversation (e.g. one the
  /// user picked from their history) instead of continuing whatever
  /// was active. Mirrors [ConversationService.resumeConversation].
  void resumeConversation(String conversationId);
}
