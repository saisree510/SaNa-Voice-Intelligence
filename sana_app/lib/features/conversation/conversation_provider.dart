import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_modes.dart';
import '../../core/errors/error_display.dart';
import '../../services/conversation_history_service.dart';
import '../../services/conversation_service.dart';
import '../../services/local_conversation_history_service.dart';
import 'models/chat_message.dart';

/// State for one mode's conversation — the single source of truth for
/// what's shown on screen, whether a message came from typed text (the
/// mock brain) or a live voice call ([ConversationScreen] folds the
/// voice transcript in via [mergeExternal] as it streams).
///
/// Persisted per user+mode via [ConversationHistoryService] (spec §15),
/// so the conversation survives hanging up a call, leaving the screen,
/// or closing the app — not just held in memory for one visit.
class ConversationProvider extends ChangeNotifier {
  ConversationProvider({
    required this.mode,
    required this.userId,
    required ConversationService conversationService,
    ConversationHistoryService? historyService,
  })  : _conversationService = conversationService,
        _historyService = historyService ?? LocalConversationHistoryService() {
    _loadHistory();
  }

  final AppMode mode;
  final String userId;
  final ConversationService _conversationService;
  final ConversationHistoryService _historyService;

  final List<ChatMessage> messages = [];
  bool isThinking = false;
  String? errorMessage;
  bool _historyLoaded = false;

  Future<void> _loadHistory() async {
    final saved = await _historyService.load(userId, mode.id);
    messages.addAll(saved);
    _historyLoaded = true;
    notifyListeners();
  }

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isThinking) return;

    messages.add(ChatMessage.user(trimmed));
    isThinking = true;
    errorMessage = null;
    notifyListeners();
    unawaited(_persist());

    try {
      final reply = await _conversationService.sendMessage(
        modeId: mode.id,
        history: List.unmodifiable(messages),
        userText: trimmed,
      );
      messages.add(ChatMessage.sana(reply));
    } catch (e) {
      errorMessage = errorMessageFor(e);
    } finally {
      isThinking = false;
      notifyListeners();
      unawaited(_persist());
    }
  }

  /// Folds messages from another source (the live voice transcript) into
  /// this history — updating a message in place if its id is already
  /// present (voice transcripts stream in and grow), appending if new.
  void mergeExternal(List<ChatMessage> incoming) {
    if (incoming.isEmpty) return;
    var changed = false;
    for (final message in incoming) {
      final existingIndex = messages.indexWhere((m) => m.id == message.id);
      if (existingIndex == -1) {
        messages.add(message);
        changed = true;
      } else if (messages[existingIndex].text != message.text) {
        messages[existingIndex] = message;
        changed = true;
      }
    }
    if (!changed) return;
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() async {
    // Avoid clobbering saved history with an empty list while the
    // initial load is still in flight.
    if (!_historyLoaded) return;
    await _historyService.save(userId, mode.id, messages);
  }

  /// Clears the current transcript (locally and, for a real backend,
  /// the tracked conversation thread) so the next message starts a
  /// brand-new conversation instead of continuing whatever was here.
  Future<void> startNewConversation() async {
    _conversationService.startNewConversation();
    messages.clear();
    errorMessage = null;
    notifyListeners();
    await _persist();
  }

  /// Replaces the current transcript with a previously-had conversation
  /// (picked from [ConversationHistoryScreen]) and points subsequent
  /// messages at continuing *that* backend thread, not a new one.
  Future<void> loadConversation(String conversationId, List<ChatMessage> loadedMessages) async {
    _conversationService.resumeConversation(conversationId);
    messages
      ..clear()
      ..addAll(loadedMessages);
    errorMessage = null;
    notifyListeners();
    await _persist();
  }
}
