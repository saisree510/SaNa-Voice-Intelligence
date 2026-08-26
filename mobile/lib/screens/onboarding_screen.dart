import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:provider/provider.dart';

import '../controllers/app_ctrl.dart';
import '../models/conversation_turn.dart';
import '../models/sana_orb_state.dart';
import '../services/auth_service.dart';
import '../ui/sana_theme.dart';
import '../widgets/sana_orb_view.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userNameCtrl = TextEditingController();
  final _assistantNameCtrl = TextEditingController(text: 'Soul');

  bool _isSaving = false;
  StreamSubscription? _timelineSub;

  @override
  void initState() {
    super.initState();
    // Listen to voice timeline to auto-fill spoken user name
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appCtrl = context.read<AppCtrl>();
      appCtrl.conversationTimeline.addListener(_onTimelineChanged);
    });
  }

  void _onTimelineChanged() {
    if (!mounted) return;
    final appCtrl = context.read<AppCtrl>();
    final turns = appCtrl.conversationTimeline.turns;

    // Find the latest user spoken turn
    final userTurns = turns.where((t) => t.role == ConversationRole.user);
    if (userTurns.isNotEmpty) {
      final lastUserText = userTurns.last.text.trim();
      // Clean up common phrases if spoken like "My name is Sai" or "Call me Sai"
      String extractedName = lastUserText;
      final lower = extractedName.toLowerCase();
      if (lower.startsWith('my name is ')) {
        extractedName = extractedName.substring(11);
      } else if (lower.startsWith("i'm ")) {
        extractedName = extractedName.substring(4);
      } else if (lower.startsWith('i am ')) {
        extractedName = extractedName.substring(5);
      } else if (lower.startsWith('call me ')) {
        extractedName = extractedName.substring(8);
      }

      // Remove trailing punctuation
      extractedName = extractedName.replaceAll(RegExp(r'[^\w\s]'), '').trim();

      if (extractedName.isNotEmpty && extractedName != _userNameCtrl.text) {
        setState(() {
          _userNameCtrl.text = extractedName;
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_timelineSub?.cancel());
    _userNameCtrl.dispose();
    _assistantNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    final authService = context.read<AuthService>();
    final appCtrl = context.read<AppCtrl>();
    final userName = _userNameCtrl.text.trim();
    final assistantName = _assistantNameCtrl.text.trim().isEmpty ? 'Soul' : _assistantNameCtrl.text.trim();

    try {
      // Disconnect voice session if still connected from onboarding
      if (appCtrl.canCancelConnect) {
        await appCtrl.disconnect();
      }

      await authService.saveProfile(
        userName: userName,
        assistantName: assistantName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: SanaColors.nearBlack,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Soul',
                      textAlign: TextAlign.center,
                      style: textTheme.displaySmall?.copyWith(
                        color: SanaColors.lavender,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'What should I call you?',
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        color: SanaColors.fgPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap the orb to speak, or type your name below',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: SanaColors.fgMuted,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Interactive Voice Orb
                    Center(
                      child: Consumer2<AppCtrl, sdk.Session>(
                        builder: (context, ctrl, session, _) {
                          final connecting = ctrl.isConnecting;
                          final live = session.connectionState == sdk.ConnectionState.connected ||
                              session.connectionState == sdk.ConnectionState.reconnecting;

                          return Column(
                            children: [
                              SanaOrbView(
                                size: 140,
                                forceState: connecting
                                    ? SanaOrbState.connecting
                                    : live
                                        ? null
                                        : SanaOrbState.idle,
                                onTap: () {
                                  if (connecting) {
                                    unawaited(ctrl.cancelConnect());
                                  } else {
                                    unawaited(ctrl.connect());
                                  }
                                },
                              ),
                              const SizedBox(height: 8),
                              Text(
                                connecting
                                    ? 'Connecting to Soul...'
                                    : live
                                        ? 'Listening... say your name!'
                                        : 'Tap orb to speak your name',
                                style: TextStyle(
                                  color: live ? SanaColors.lavender : SanaColors.fgMuted,
                                  fontSize: 12,
                                  fontWeight: live ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Name Input (Typed or Spoken)
                    TextFormField(
                      controller: _userNameCtrl,
                      autofocus: false,
                      style: const TextStyle(color: SanaColors.fgPrimary, fontSize: 16),
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Your Name',
                        hintText: 'e.g. Sai',
                        prefixIcon: const Icon(Icons.person_outline_rounded, color: SanaColors.lavender),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.mic_rounded, color: SanaColors.lavender),
                          tooltip: 'Speak your name',
                          onPressed: () {
                            final ctrl = context.read<AppCtrl>();
                            if (!ctrl.canCancelConnect) {
                              unawaited(ctrl.connect());
                            }
                          },
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter or speak your name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Assistant Name Input
                    TextFormField(
                      controller: _assistantNameCtrl,
                      style: const TextStyle(color: SanaColors.fgPrimary, fontSize: 16),
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Assistant Name',
                        hintText: 'Default: Soul',
                        prefixIcon: Icon(Icons.psychology_outlined, color: SanaColors.lavender),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Submit Button
                    FilledButton(
                      onPressed: _isSaving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: SanaColors.lavender,
                        foregroundColor: SanaColors.nearBlack,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: SanaColors.nearBlack,
                              ),
                            )
                          : const Text(
                              'Continue to Soul',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
