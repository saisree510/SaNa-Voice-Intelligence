import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_assistant/models/conversation_model.dart';
import 'package:voice_assistant/services/conversation_memory.dart';

void main() {
  test('restore payload keeps the newest complete turns within the byte limit', () {
    final messages = List.generate(
      8,
      (index) => PersistedMessage(
        id: 'message-$index',
        conversationId: 'conversation-1',
        sender: index.isEven ? 'user' : 'assistant',
        content: 'turn $index ${'x' * 120}',
        source: 'text',
        createdAt: DateTime.utc(2026, 8, 11, 12, index),
      ),
    );

    final payload = buildConversationRestorePayload(
      conversationId: 'conversation-1',
      messages: messages,
      mode: 'debate',
      maxPayloadBytes: 700,
    );
    final encoded = utf8.encode(jsonEncode(payload));
    final restored = payload['messages'] as List<dynamic>;

    expect(payload['type'], 'conversation_restore');
    expect(payload['mode'], 'debate');
    expect(encoded.length, lessThanOrEqualTo(700));
    expect(restored, isNotEmpty);
    expect((restored.last as Map<String, dynamic>)['id'], 'message-7');
    expect(
      restored.map((item) => (item as Map<String, dynamic>)['id']),
      orderedEquals(
        List.generate(restored.length, (i) => 'message-${8 - restored.length + i}'),
      ),
    );
  });
}
