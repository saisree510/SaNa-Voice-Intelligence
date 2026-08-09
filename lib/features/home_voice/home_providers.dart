import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'orb_state.dart';

/// Placeholder display name until auth/onboarding lands.
final previewUserNameProvider = Provider<String>((ref) => 'Sai');

/// Default matches approved voice-first visual reference.
final orbStateProvider = StateProvider<SanaOrbState>(
  (ref) => SanaOrbState.listening,
);

enum ConversationModePreview { general, debate, brainstorm, build }

final selectedModeProvider = StateProvider<ConversationModePreview>(
  (ref) => ConversationModePreview.general,
);
