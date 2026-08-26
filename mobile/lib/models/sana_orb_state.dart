import 'package:livekit_client/livekit_client.dart' as sdk;

/// Visual states for the SaNa voice orb (PRD mapping; refinable).
enum SanaOrbState {
  idle,
  connecting,
  listening,
  thinking,
  speaking,
  userSpeaking,
  reconnecting,
  error,
}

/// Maps LiveKit session + agent attributes onto [SanaOrbState].
///
/// Prefer agent participant `lk.agent.state` when present; fall back to
/// session connection / agent readiness flags so the orb stays honest
/// before attributes arrive.
SanaOrbState resolveSanaOrbState({
  required sdk.ConnectionState connectionState,
  required bool sessionHasError,
  required bool agentHasError,
  required bool agentIsPending,
  required bool agentIsBuffering,
  required bool agentIsConnected,
  sdk.AgentState? agentState,
  bool localParticipantSpeaking = false,
}) {
  if (sessionHasError || agentHasError) {
    return SanaOrbState.error;
  }

  switch (connectionState) {
    case sdk.ConnectionState.disconnected:
      return SanaOrbState.idle;
    case sdk.ConnectionState.connecting:
      return SanaOrbState.connecting;
    case sdk.ConnectionState.reconnecting:
      return SanaOrbState.reconnecting;
    case sdk.ConnectionState.connected:
      break;
  }

  if (!agentIsConnected || agentIsPending) {
    return SanaOrbState.connecting;
  }

  if (localParticipantSpeaking) {
    return SanaOrbState.userSpeaking;
  }

  if (agentState != null) {
    switch (agentState) {
      case sdk.AgentState.speaking:
        return SanaOrbState.speaking;
      case sdk.AgentState.thinking:
        return SanaOrbState.thinking;
      case sdk.AgentState.listening:
        return SanaOrbState.listening;
      case sdk.AgentState.initializing:
        return SanaOrbState.connecting;
      case sdk.AgentState.idle:
        return SanaOrbState.listening;
    }
  }

  if (agentIsBuffering) {
    return SanaOrbState.thinking;
  }

  return SanaOrbState.listening;
}

extension SanaOrbStateLabel on SanaOrbState {
  String get statusLabel => switch (this) {
        SanaOrbState.idle => 'Ready when you are',
        SanaOrbState.connecting => 'Connecting…',
        SanaOrbState.listening => 'Listening',
        SanaOrbState.thinking => 'Thinking…',
        SanaOrbState.speaking => 'Speaking',
        SanaOrbState.userSpeaking => 'Hearing you',
        SanaOrbState.reconnecting => 'Reconnecting…',
        SanaOrbState.error => 'Something went wrong',
      };
}
