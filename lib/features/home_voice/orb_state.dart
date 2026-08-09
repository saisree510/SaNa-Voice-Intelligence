/// Visual / connection states for the SaNa voice orb.
/// Structured for later LiveKit binding; UI-only for now.
enum SanaOrbState {
  idle,
  connecting,
  listening,
  userSpeaking,
  thinking,
  speaking,
  reconnecting,
  error,
}

extension SanaOrbStateX on SanaOrbState {
  String get label => switch (this) {
    SanaOrbState.idle => 'Ready',
    SanaOrbState.connecting => 'Connecting…',
    SanaOrbState.listening => 'Listening…',
    SanaOrbState.userSpeaking => 'Hearing you…',
    SanaOrbState.thinking => 'Thinking…',
    SanaOrbState.speaking => 'Speaking…',
    SanaOrbState.reconnecting => 'Reconnecting…',
    SanaOrbState.error => 'Something went wrong',
  };
}
