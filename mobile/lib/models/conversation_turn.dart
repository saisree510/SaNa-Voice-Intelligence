import 'package:livekit_client/livekit_client.dart' as sdk;

/// Role of a turn in the unified SaNa conversation timeline.
enum ConversationRole { user, agent }

/// How the turn entered the LiveKit session.
enum ConversationSource { voice, text }

/// One item in the unified voice+text timeline for the active session.
///
/// Partials are display-only and must not be treated as durable finals.
/// Persistence / Conversation Service is Phase 7; this model is session-scoped.
class ConversationTurn {
  const ConversationTurn({
    required this.id,
    required this.timestamp,
    required this.role,
    required this.source,
    required this.text,
    required this.isFinal,
  });

  /// LiveKit / client message id (segment id or send id). Used for idempotency.
  final String id;
  final DateTime timestamp;
  final ConversationRole role;
  final ConversationSource source;
  final String text;

  /// False while STT/TTS transcript text is still streaming for this id.
  final bool isFinal;

  bool get isUser => role == ConversationRole.user;

  ConversationTurn copyWith({
    String? id,
    DateTime? timestamp,
    ConversationRole? role,
    ConversationSource? source,
    String? text,
    bool? isFinal,
  }) {
    return ConversationTurn(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      role: role ?? this.role,
      source: source ?? this.source,
      text: text ?? this.text,
      isFinal: isFinal ?? this.isFinal,
    );
  }

  static ConversationRole roleFor(sdk.ReceivedMessage message) {
    if (message.content is sdk.UserInput || message.content is sdk.UserTranscript) {
      return ConversationRole.user;
    }
    return ConversationRole.agent;
  }

  static ConversationSource sourceFor(sdk.ReceivedMessage message) {
    if (message.content is sdk.UserInput) {
      return ConversationSource.text;
    }
    return ConversationSource.voice;
  }
}
