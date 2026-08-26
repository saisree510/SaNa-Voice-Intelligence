enum ChatRole { user, sana }

/// One turn in a conversation. Kept mode-agnostic — the same model is
/// used by Debate, Brainstorm, and Build, since it's the mode's system
/// prompt (not the message shape) that differs between them.
class ChatMessage {
  ChatMessage({required this.id, required this.role, required this.text, required this.timestamp});

  factory ChatMessage.user(String text) => ChatMessage(
        id: _newId(),
        role: ChatRole.user,
        text: text,
        timestamp: DateTime.now(),
      );

  factory ChatMessage.sana(String text) => ChatMessage(
        id: _newId(),
        role: ChatRole.sana,
        text: text,
        timestamp: DateTime.now(),
      );

  final String id;
  final ChatRole role;
  final String text;
  final DateTime timestamp;

  static String _newId() => '${DateTime.now().microsecondsSinceEpoch}';

  /// For [ConversationHistoryService] persistence.
  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        role: ChatRole.values.byName(json['role'] as String),
        text: json['text'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}
