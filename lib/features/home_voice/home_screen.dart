import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/sana_colors.dart';
import '../../core/design/sana_spacing.dart';
import 'conversation_handle.dart';
import 'greeting_section.dart';
import 'home_providers.dart';
import 'mode_selector.dart';
import 'orb_state.dart';
import 'sana_orb.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userName = ref.watch(previewUserNameProvider);
    final orbState = ref.watch(orbStateProvider);
    final mode = ref.watch(selectedModeProvider);

    return DecoratedBox(
      decoration: const BoxDecoration(gradient: SanaColors.atmosphere),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 720.0;
            final orbSize = (maxHeight * 0.36).clamp(170.0, 260.0);

            return Padding(
              padding: const EdgeInsets.fromLTRB(
                SanaSpacing.lg,
                SanaSpacing.md,
                SanaSpacing.lg,
                0,
              ),
              child: Column(
                children: [
                  GreetingSection(userName: userName),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SanaOrb(
                          size: orbSize,
                          state: orbState,
                          onTap: () {
                            final next = switch (orbState) {
                              SanaOrbState.idle => SanaOrbState.listening,
                              SanaOrbState.listening =>
                                SanaOrbState.userSpeaking,
                              SanaOrbState.userSpeaking =>
                                SanaOrbState.thinking,
                              SanaOrbState.thinking => SanaOrbState.speaking,
                              SanaOrbState.speaking => SanaOrbState.idle,
                              _ => SanaOrbState.listening,
                            };
                            ref.read(orbStateProvider.notifier).state = next;
                          },
                        ),
                        const SizedBox(height: SanaSpacing.md),
                        Text(
                          orbState.label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: SanaColors.lavender,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                        ),
                        const SizedBox(height: SanaSpacing.sm),
                        _StateDots(state: orbState),
                      ],
                    ),
                  ),
                  ModeSelector(
                    selected: mode,
                    onSelected: (value) {
                      final next = mode == value
                          ? ConversationModePreview.general
                          : value;
                      ref.read(selectedModeProvider.notifier).state = next;
                    },
                  ),
                  SizedBox(height: (maxHeight * 0.018).clamp(8.0, 16.0)),
                  ConversationHandle(
                    onTap: () {
                      // Visual structure only; transcript sheet later.
                    },
                  ),
                  SizedBox(height: (maxHeight * 0.01).clamp(4.0, 10.0)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StateDots extends StatelessWidget {
  const _StateDots({required this.state});

  final SanaOrbState state;

  @override
  Widget build(BuildContext context) {
    final activeIndex = switch (state) {
      SanaOrbState.listening || SanaOrbState.userSpeaking => 1,
      SanaOrbState.thinking ||
      SanaOrbState.connecting ||
      SanaOrbState.reconnecting => 0,
      SanaOrbState.speaking => 2,
      _ => 1,
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 6 : 5,
          height: active ? 6 : 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? SanaColors.lavender
                : SanaColors.violetDeep.withValues(alpha: 0.55),
          ),
        );
      }),
    );
  }
}
