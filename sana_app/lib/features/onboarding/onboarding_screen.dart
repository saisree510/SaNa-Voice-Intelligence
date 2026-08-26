import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/error_display.dart';
import '../../services/voice_greeting_service.dart';
import '../auth/auth_provider.dart';
import '../auth/widgets/sana_brand_header.dart';

const _greeting = "Hi, this is SANA. May I know your name?";

enum _VoiceState { loading, ready, speaking, unavailable }

/// First-login-only screen: SANA asks what to call the user — out loud,
/// via [VoiceGreetingService] (the same Cartesia voice the live
/// voice-mode agent uses, not a generic device TTS voice), then in
/// writing underneath. Once submitted, [AuthProvider.completeOnboarding]
/// persists the name and the router's redirect takes over to send the
/// user to /home.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _greetingService = VoiceGreetingService();
  final _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;

  _VoiceState _voiceState = _VoiceState.loading;
  Uint8List? _cachedAudio;

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _voiceState = _VoiceState.ready);
    });
    // Speak automatically on first arrival; the 🔊 button lets the user
    // (re)trigger it any time afterward, instantly once cached.
    WidgetsBinding.instance.addPostFrameCallback((_) => _speak());
  }

  Future<void> _speak() async {
    final cached = _cachedAudio;
    if (cached != null) {
      setState(() => _voiceState = _VoiceState.speaking);
      await _player.play(BytesSource(cached));
      return;
    }

    setState(() => _voiceState = _VoiceState.loading);
    try {
      final token = context.read<AuthProvider>().authToken;
      if (token == null) throw StateError('Not logged in.');
      final audio = await _greetingService.synthesize(text: _greeting, authToken: token);
      if (!mounted) return;
      _cachedAudio = audio;
      setState(() => _voiceState = _VoiceState.speaking);
      await _player.play(BytesSource(audio));
    } catch (_) {
      // Voice synthesis unavailable (backend down, no network, etc.) —
      // the written greeting below still carries the same message, so
      // this fails silently rather than surfacing an error. Tapping the
      // 🔊 button again retries.
      if (mounted) setState(() => _voiceState = _VoiceState.unavailable);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthProvider auth) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await _player.stop();
    await auth.completeOnboarding(name);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canSubmit = _nameController.text.trim().isNotEmpty && !auth.isLoading;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SanaBrandHeader(),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Hi! I'm SANA.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(width: 6),
                  _SpeakerButton(state: _voiceState, onPressed: _speak),
                ],
              ),
              Text(
                'What should I call you?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _nameController,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                autofocus: true,
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(hintText: 'Your name'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => canSubmit ? _submit(auth) : null,
              ),
              if (auth.errorMessage != null) ...[
                const SizedBox(height: 16),
                ErrorBanner(message: auth.errorMessage!),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: canSubmit ? () => _submit(auth) : null,
                child: auth.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeakerButton extends StatelessWidget {
  const _SpeakerButton({required this.state, required this.onPressed});

  final _VoiceState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    if (state == _VoiceState.loading) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
      );
    }
    final speaking = state == _VoiceState.speaking;
    return IconButton(
      onPressed: onPressed,
      tooltip: speaking ? 'Speaking…' : 'Hear this again',
      icon: Icon(speaking ? Icons.volume_up_rounded : Icons.volume_up_outlined, color: color),
    );
  }
}
