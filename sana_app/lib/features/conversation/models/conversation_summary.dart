/// One entry in the "past conversations" list for a mode — no message
/// content, just enough to show and pick from a list (spec-equivalent
/// of sana_backend's ConversationSummary schema).
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.mode,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String mode;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) => ConversationSummary(
        id: json['id'] as String,
        mode: json['mode'] as String,
        title: json['title'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
