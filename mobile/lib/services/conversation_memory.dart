import 'dart:convert';

import '../models/conversation_model.dart';

const int conversationRestoreMaxPayloadBytes = 12 * 1024;
const int conversationRestoreMaxMessages = 40;
const int conversationRestoreMaxMessageCharacters = 4000;

Map<String, dynamic> buildConversationRestorePayload({
  required String conversationId,
  required List<PersistedMessage> messages,
  required String mode,
  int maxPayloadBytes = conversationRestoreMaxPayloadBytes,
}) {
  final selected = <Map<String, dynamic>>[];
  final candidates = messages.where(
      (message) => (message.sender == 'user' || message.sender == 'assistant') && message.content.trim().isNotEmpty);

  for (final message in candidates.toList().reversed) {
    if (selected.length >= conversationRestoreMaxMessages) break;
    final content = message.content.trim();
    final boundedContent = content.length > conversationRestoreMaxMessageCharacters
        ? content.substring(content.length - conversationRestoreMaxMessageCharacters)
        : content;
    final restoredMessage = <String, dynamic>{
      'id': message.idempotencyKey ?? message.id,
      'role': message.sender,
      'content': boundedContent,
    };
    final candidateMessages = [restoredMessage, ...selected];
    final candidatePayload = <String, dynamic>{
      'type': 'conversation_restore',
      'conversation_id': conversationId,
      'mode': mode,
      'messages': candidateMessages,
    };
    if (utf8.encode(jsonEncode(candidatePayload)).length > maxPayloadBytes) break;
    selected.insert(0, restoredMessage);
  }

  return <String, dynamic>{
    'type': 'conversation_restore',
    'conversation_id': conversationId,
    'mode': mode,
    'messages': selected,
  };
}
