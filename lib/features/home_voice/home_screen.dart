import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/sana_colors.dart';
import '../../core/design/sana_spacing.dart';
import 'home_providers.dart';
import 'mode_cards.dart';
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final orbSize = (constraints.maxHeight * 0.28).clamp(140.0, 220.0);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                SanaSpacing.lg,
                SanaSpacing.md,
                SanaSpacing.lg,
                SanaSpacing.sm,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'SaNa',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: SanaSpacing.xs),
                    Text(
                      'Hey $userName, what are we working on today?',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: SanaColors.textSecondary,
                          ),
                    ),
                    SizedBox(height: constraints.maxHeight * 0.06),
                    Center(
                      child: SanaOrb(
                        size: orbSize,
                        state: orbState,
                        onTap: () {
                          final next = switch (orbState) {
                            SanaOrbState.idle => SanaOrbState.listening,
                            SanaOrbState.listening => SanaOrbState.thinking,
                            SanaOrbState.thinking => SanaOrbState.speaking,
                            SanaOrbState.speaking => SanaOrbState.idle,
                            _ => SanaOrbState.idle,
                          };
                          ref.read(orbStateProvider.notifier).state = next;
                        },
                      ),
                    ),
                    const SizedBox(height: SanaSpacing.md),
                    Text(
                      orbState.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: SanaColors.accentCyan.withValues(alpha: 0.9),
                          ),
                    ),
                    const SizedBox(height: SanaSpacing.sm),
                    Text(
                      'Tap the orb to preview states. Voice arrives in a later phase.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    SizedBox(height: constraints.maxHeight * 0.05),
                    ModeCards(
                      selected: mode,
                      onSelected: (value) {
                        ref.read(selectedModeProvider.notifier).state = value;
                      },
                    ),
                    const SizedBox(height: SanaSpacing.sm),
                    Text(
                      mode == ConversationModePreview.general
                          ? 'General conversation is always available — modes are optional.'
                          : '${mode.name[0].toUpperCase()}${mode.name.substring(1)} selected (UI preview).',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
