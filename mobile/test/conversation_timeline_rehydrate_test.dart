import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:voice_assistant/controllers/conversation_timeline.dart';
import 'package:voice_assistant/models/conversation_model.dart';

void main() {
  test('rehydration preserves source ids without persisting turns again', () async {
    final room = sdk.Room();
    final session = sdk.Session.fromFixedTokenSource(
      sdk.LiteralTokenSource(
        serverUrl: 'wss://example.invalid',
        participantToken: 'unused-test-token',
      ),
      options: sdk.SessionOptions(room: room),
    );
    final timeline = ConversationTimeline(session);
    final persistedAgain = <String>[];
    timeline.onFinalTurn = (turn) => persistedAgain.add(turn.id);

    timeline.rehydrateTurns([
      PersistedMessage(
        id: 'database-row-id',
        conversationId: 'conversation-1',
        sender: 'user',
        content: 'Continue from here',
        source: 'text',
        idempotencyKey: 'original-livekit-id',
        createdAt: DateTime.utc(2026, 8, 11),
      ),
    ]);

    expect(timeline.turns.single.id, 'original-livekit-id');
    expect(persistedAgain, isEmpty);

    timeline.dispose();
    await session.dispose();
    await room.dispose();
  });
}
