import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_assistant/services/auth_service.dart';
import 'package:voice_assistant/services/conversation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local conversation cache is isolated when accounts change', () async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(isOptional: true);

    final auth = AuthService();
    await auth.initialize();
    await auth.signIn(email: 'user-a@example.com', password: 'unused');

    final conversations = ConversationService(authService: auth);
    final userAConversation = await conversations.createConversation(
      title: 'User A private idea',
    );
    await conversations.saveMessage(
      conversationId: userAConversation.id,
      sender: 'user',
      content: 'User A secret',
      source: 'text',
    );

    await auth.signIn(email: 'user-b@example.com', password: 'unused');
    expect(conversations.conversations, isEmpty);
    expect(await conversations.fetchUserConversations(), isEmpty);
    expect(await conversations.fetchMessages(userAConversation.id), isEmpty);

    final userBConversation = await conversations.createConversation(
      title: 'User B private idea',
    );
    expect(userBConversation.userId, auth.userId);

    await auth.signIn(email: 'user-a@example.com', password: 'unused');
    final restoredForUserA = await conversations.fetchUserConversations();
    expect(restoredForUserA.map((item) => item.id), [userAConversation.id]);
    expect(
      (await conversations.fetchMessages(userAConversation.id)).single.content,
      'User A secret',
    );

    conversations.dispose();
    auth.dispose();
  });
}
