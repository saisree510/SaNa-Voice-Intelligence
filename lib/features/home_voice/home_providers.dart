import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'orb_state.dart';

/// Placeholder display name until auth/onboarding lands.
final previewUserNameProvider = Provider<String>((ref) => 'there');

final orbStateProvider =
    StateProvider<SanaOrbState>((ref) => SanaOrbState.idle);

enum ConversationModePreview { general, debate, brainstorm, build }

final selectedModeProvider =
    StateProvider<ConversationModePreview>((ref) => ConversationModePreview.general);
