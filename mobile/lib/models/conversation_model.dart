import 'dart:convert';

class ConversationSession {
  final String id;
  final String userId;
  final String title;
  final String mode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? previewText;

  const ConversationSession({
    required this.id,
    required this.userId,
    required this.title,
    this.mode = 'general',
    required this.createdAt,
    required this.updatedAt,
    this.previewText,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'mode': mode,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'preview_text': previewText,
    };
  }

  factory ConversationSession.fromMap(Map<String, dynamic> map) {
    return ConversationSession(
      id: map['id'] as String,
      userId: map['user_id'] as String? ?? 'local_user',
      title: map['title'] as String? ?? 'Conversation',
      mode: map['mode'] as String? ?? 'general',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now(),
      previewText: map['preview_text'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory ConversationSession.fromJson(String source) =>
      ConversationSession.fromMap(json.decode(source) as Map<String, dynamic>);
}

class PersistedMessage {
  final String id;
  final String conversationId;
  final String sender; // 'user' | 'assistant' | 'system'
  final String content;
  final String source; // 'voice' | 'text'
  final String? idempotencyKey;
  final DateTime createdAt;

  const PersistedMessage({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    required this.source,
    this.idempotencyKey,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender': sender,
      'content': content,
      'source': source,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PersistedMessage.fromMap(Map<String, dynamic> map) {
    return PersistedMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      sender: map['sender'] as String? ?? 'user',
      content: map['content'] as String? ?? '',
      source: map['source'] as String? ?? 'text',
      idempotencyKey: map['idempotency_key'] as String?,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory PersistedMessage.fromJson(String source) =>
      PersistedMessage.fromMap(json.decode(source) as Map<String, dynamic>);
}
