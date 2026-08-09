import 'dart:math';

import '../core/errors/app_exception.dart';
import '../features/conversation/models/chat_message.dart';
import 'conversation_service.dart';

/// Local, offline, template-based stand-in for the real AI backend.
///
/// This is NOT an LLM — it picks from a small set of mode-appropriate
/// response templates so the conversation screen is fully clickable and
/// demonstrates each mode's distinct *behavior* (Debate challenges,
/// Brainstorm expands, Build asks/structures) before a real backend +
/// LLM exists. Replace with a real [ConversationService] implementation
/// that calls your backend — no UI or provider code changes required.
class MockConversationService implements ConversationService {
  final _random = Random();

  @override
  Future<String> sendMessage({
    required String modeId,
    required List<ChatMessage> history,
    required String userText,
  }) async {
    // Simulate thinking time so the UI's thinking indicator is visible
    // and honest about "this takes a moment", same as a real API call would.
    await Future.delayed(Duration(milliseconds: 700 + _random.nextInt(600)));

    switch (modeId) {
      case 'debate':
        return _pick(_debateTemplates, userText);
      case 'brainstorm':
        return _pick(_brainstormTemplates, userText);
      case 'build':
        return _pick(_buildTemplates, userText);
      default:
        throw const AiException("SANA doesn't recognize that mode.");
    }
  }

  String _pick(List<String Function(String)> templates, String userText) {
    return templates[_random.nextInt(templates.length)](userText);
  }

  // The mock has no server-side conversation to track — history is
  // whatever ConversationProvider already holds locally.
  @override
  void startNewConversation() {}

  @override
  void resumeConversation(String conversationId) {}

  static final List<String Function(String)> _debateTemplates = [
    (t) => "I'd push back on that. What's the strongest evidence for \"$t\" — and have you considered the case against it?",
    (t) => "That's one view, but it skips a real counterpoint. What happens if the opposite of \"$t\" is true?",
    (t) => "I'll grant part of that, but it sounds stronger than the evidence supports. What would actually change your mind here?",
    (t) => 'Interesting position. What\'s the weakest part of your own argument — the part you\'re least sure about?',
    (t) => "Before I agree, walk me through why \"$t\" holds up better than the most obvious objection to it.",
  ];

  static final List<String Function(String)> _brainstormTemplates = [
    (t) => "Good starting point. A few directions from \"$t\": go narrower and pick one audience, go broader and combine it with something adjacent, or flip the assumption entirely. Which pulls at you?",
    (t) => 'I like that. What\'s the version of this that\'s 10x simpler — and what would you cut to get there?',
    (t) => "That opens up a few paths. What's the constraint you're least willing to compromise on here?",
    (t) => "Let's build on that. If this worked perfectly, who's the first person that would use it — and why them?",
    (t) => 'Noted. What\'s an adjacent idea this reminds you of? Sometimes the useful version is the mashup.',
  ];

  static final List<String Function(String)> _buildTemplates = [
    (t) => "Got it. Before I structure this — who is this actually for, and what's the one thing it must do well on day one?",
    (t) => 'Makes sense. Is this mobile, web, or both — and does it need accounts/login, or can it start anonymous?',
    (t) => "That's a clear core. What's the smallest version of \"$t\" you could actually ship first?",
    (t) => 'Understood. Does this need to talk to any AI/voice features, or is it a more traditional app for V1?',
    (t) => "Good — I have enough to sketch a first plan. Anything else it must include, or should I structure what we've covered?",
  ];
}
