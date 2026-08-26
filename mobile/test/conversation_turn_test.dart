import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:voice_assistant/models/conversation_turn.dart';

void main() {
  group('ConversationTurn', () {
    test('maps typed user input as text source', () {
      final message = sdk.ReceivedMessage(
        id: 't1',
        timestamp: DateTime.utc(2026, 8, 9),
        content: const sdk.UserInput('hello'),
      );
      expect(ConversationTurn.roleFor(message), ConversationRole.user);
      expect(ConversationTurn.sourceFor(message), ConversationSource.text);
    });

    test('maps spoken transcripts as voice source', () {
      final user = sdk.ReceivedMessage(
        id: 'u1',
        timestamp: DateTime.utc(2026, 8, 9),
        content: const sdk.UserTranscript('spoken'),
      );
      final agent = sdk.ReceivedMessage(
        id: 'a1',
        timestamp: DateTime.utc(2026, 8, 9),
        content: const sdk.AgentTranscript('reply'),
      );
      expect(ConversationTurn.roleFor(user), ConversationRole.user);
      expect(ConversationTurn.sourceFor(user), ConversationSource.voice);
      expect(ConversationTurn.roleFor(agent), ConversationRole.agent);
      expect(ConversationTurn.sourceFor(agent), ConversationSource.voice);
    });

    test('copyWith keeps id for idempotent upserts', () {
      final base = ConversationTurn(
        id: 'seg-1',
        timestamp: DateTime.utc(2026, 8, 9, 12),
        role: ConversationRole.agent,
        source: ConversationSource.voice,
        text: 'hel',
        isFinal: false,
      );
      final updated = base.copyWith(text: 'hello', isFinal: true);
      expect(updated.id, 'seg-1');
      expect(updated.text, 'hello');
      expect(updated.isFinal, isTrue);
      expect(updated.role, ConversationRole.agent);
    });
  });
}
