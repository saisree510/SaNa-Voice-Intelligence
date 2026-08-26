/// Where the SANA backend (sana_backend/) lives — it issues LiveKit
/// tokens for voice sessions (see VoiceService, added once the backend
/// has real LiveKit credentials).
///
/// Override per run target with `--dart-define=SANA_BACKEND_URL=...`:
/// - Web / iOS simulator / desktop Chrome: default `localhost` is correct.
/// - Android emulator: `localhost` means the emulator itself, not this
///   machine — use `http://10.0.2.2:8000` instead.
/// - Real device: use this machine's LAN IP, e.g. `http://192.168.1.23:8000`
///   (device and dev machine must be on the same network).
abstract final class AppConfig {
  static const String backendBaseUrl = String.fromEnvironment(
    'SANA_BACKEND_URL',
    defaultValue: 'http://localhost:8000',
  );
}
