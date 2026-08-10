import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;

import '../models/conversation_turn.dart';

/// Builds a unified voice+text timeline from the active LiveKit [sdk.Session].
///
/// Rules:
/// - Typed [sdk.UserInput] and spoken [sdk.UserTranscript] / [sdk.AgentTranscript]
///   share one ordered timeline keyed by message id (idempotent upserts).
/// - Partials update in place; they are not treated as durable finals.
/// - A turn becomes final when a newer message id appears after it, or after a
///   short idle period with no text changes (end of streaming).
class ConversationTimeline extends ChangeNotifier {
  ConversationTimeline(this.session) {
    session.addListener(_handleSessionChange);
    _handleSessionChange();
  }

  static const Duration partialIdle = Duration(milliseconds: 900);

  final sdk.Session session;

  final Map<String, ConversationTurn> _turnsById = {};
  final Map<String, String> _lastTextById = {};
  List<ConversationTurn> _ordered = const [];
  Timer? _finalizeTimer;

  /// Deduped client send ids already represented in the timeline.
  final Set<String> _knownClientSendIds = {};

  List<ConversationTurn> get turns => _ordered;

  bool get hasTurns => _ordered.isNotEmpty;

  void Function(ConversationTurn turn)? onFinalTurn;

  void rehydrateTurns(List<dynamic> persistedMessages) {
    clear();
    for (final item in persistedMessages) {
      final String id = item.id;
      final String roleStr = item.sender;
      final String content = item.content;
      final String sourceStr = item.source;
      final DateTime time = item.createdAt;

      final role = roleStr == 'user'
          ? ConversationRole.user
          : ConversationRole.agent;

      final source = sourceStr == 'voice'
          ? ConversationSource.voice
          : ConversationSource.text;

      final turn = ConversationTurn(
        id: id,
        timestamp: time,
        role: role,
        source: source,
        text: content,
        isFinal: true,
      );

      _turnsById[id] = turn;
      _lastTextById[id] = content;
      _knownClientSendIds.add(id);
    }
    _rebuildOrdered();
    notifyListeners();
  }

  void clear() {
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    _turnsById.clear();
    _lastTextById.clear();
    _knownClientSendIds.clear();
    _ordered = const [];
    notifyListeners();
  }

  /// Records a typed send using the LiveKit [sdk.SentMessage] id for idempotency.
  void trackClientSend(sdk.SentMessage sent) {
    if (_knownClientSendIds.contains(sent.id)) {
      return;
    }
    _knownClientSendIds.add(sent.id);
    // Session loopback usually inserts UserInput with the same id; upsert covers both.
    _upsert(
      ConversationTurn(
        id: sent.id,
        timestamp: sent.timestamp.toLocal(),
        role: ConversationRole.user,
        source: ConversationSource.text,
        text: sent.content.text.trim(),
        isFinal: true,
      ),
    );
    _rebuildOrdered();
    notifyListeners();
  }

  void _handleSessionChange() {
    final messages = session.messages.toList()
      ..sort((a, b) {
        final byTime = a.timestamp.compareTo(b.timestamp);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
    var changed = false;

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final text = message.content.text.trim();
      if (text.isEmpty) {
        continue;
      }

      final previousText = _lastTextById[message.id];
      final textChanged = previousText != text;
      _lastTextById[message.id] = text;

      final isTyped = message.content is sdk.UserInput;
      final isLast = i == messages.length - 1;

      // Typed input is always a durable final for this session timeline.
      // Transcripts on the last id are partial until superseded or idle-finalized.
      final bool isFinal = isTyped || !isLast || (!textChanged && (_turnsById[message.id]?.isFinal ?? false));

      final existing = _turnsById[message.id];
      final next = ConversationTurn(
        id: message.id,
        timestamp: message.timestamp.toLocal(),
        role: ConversationTurn.roleFor(message),
        source: ConversationTurn.sourceFor(message),
        text: text,
        isFinal: isFinal,
      );

      if (existing != next) {
        _turnsById[message.id] = next;
        changed = true;
      }

      if (isTyped) {
        _knownClientSendIds.add(message.id);
      }
    }

    // Any non-last transcript should be finalized (superseded by a later id).
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final turn = _turnsById[message.id];
      if (turn == null) continue;
      final shouldBeFinal = message.content is sdk.UserInput || i < messages.length - 1;
      if (shouldBeFinal && !turn.isFinal) {
        _turnsById[message.id] = turn.copyWith(isFinal: true);
        changed = true;
      }
    }

    // Drop turns that disappeared after history restore/clear.
    final liveIds = messages.map((m) => m.id).toSet();
    final staleIds = _turnsById.keys.where((id) => !liveIds.contains(id) && !_knownClientSendIds.contains(id)).toList();
    for (final id in staleIds) {
      _turnsById.remove(id);
      _lastTextById.remove(id);
      changed = true;
    }

    if (changed) {
      _rebuildOrdered();
      notifyListeners();
    }

    _scheduleIdleFinalize();
  }

  void _scheduleIdleFinalize() {
    _finalizeTimer?.cancel();
    if (_ordered.isEmpty) return;
    final last = _ordered.last;
    if (last.isFinal) return;

    _finalizeTimer = Timer(partialIdle, () {
      final current = _turnsById[last.id];
      if (current == null || current.isFinal) return;
      if (_lastTextById[current.id] != current.text) return;
      _turnsById[current.id] = current.copyWith(isFinal: true);
      _rebuildOrdered();
      notifyListeners();
    });
  }

  void _upsert(ConversationTurn turn) {
    if (turn.text.isEmpty) return;
    _turnsById[turn.id] = turn;
    _lastTextById[turn.id] = turn.text;
  }

  final Set<String> _notifiedFinalTurnIds = {};

  void _rebuildOrdered() {
    final values = _turnsById.values.toList()
      ..sort((a, b) {
        final byTime = a.timestamp.compareTo(b.timestamp);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
    _ordered = List.unmodifiable(values);

    for (final turn in _ordered) {
      if (turn.isFinal && !_notifiedFinalTurnIds.contains(turn.id)) {
        _notifiedFinalTurnIds.add(turn.id);
        onFinalTurn?.call(turn);
      }
    }
  }

  @override
  void dispose() {
    _finalizeTimer?.cancel();
    session.removeListener(_handleSessionChange);
    super.dispose();
  }
}
