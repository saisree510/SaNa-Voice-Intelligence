/// Visual / connection states for the SaNa voice orb.
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
        SanaOrbState.connecting => 'Connecting',
        SanaOrbState.listening => 'Listening',
        SanaOrbState.userSpeaking => 'Hearing you',
        SanaOrbState.thinking => 'Thinking',
        SanaOrbState.speaking => 'Speaking',
        SanaOrbState.reconnecting => 'Reconnecting',
        SanaOrbState.error => 'Something went wrong',
      };
}
