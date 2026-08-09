import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:voice_assistant/models/sana_orb_state.dart';

void main() {
  group('resolveSanaOrbState', () {
    test('disconnected is idle', () {
      expect(
        resolveSanaOrbState(
          connectionState: sdk.ConnectionState.disconnected,
          sessionHasError: false,
          agentHasError: false,
          agentIsPending: false,
          agentIsBuffering: false,
          agentIsConnected: false,
        ),
        SanaOrbState.idle,
      );
    });

    test('connecting maps to connecting', () {
      expect(
        resolveSanaOrbState(
          connectionState: sdk.ConnectionState.connecting,
          sessionHasError: false,
          agentHasError: false,
          agentIsPending: false,
          agentIsBuffering: false,
          agentIsConnected: false,
        ),
        SanaOrbState.connecting,
      );
    });

    test('reconnecting maps to reconnecting', () {
      expect(
        resolveSanaOrbState(
          connectionState: sdk.ConnectionState.reconnecting,
          sessionHasError: false,
          agentHasError: false,
          agentIsPending: false,
          agentIsBuffering: false,
          agentIsConnected: true,
        ),
        SanaOrbState.reconnecting,
      );
    });

    test('errors win over other states', () {
      expect(
        resolveSanaOrbState(
          connectionState: sdk.ConnectionState.connected,
          sessionHasError: true,
          agentHasError: false,
          agentIsPending: false,
          agentIsBuffering: false,
          agentIsConnected: true,
          agentState: sdk.AgentState.listening,
        ),
        SanaOrbState.error,
      );
    });

    test('agent speaking / thinking / listening map through', () {
      expect(
        resolveSanaOrbState(
          connectionState: sdk.ConnectionState.connected,
          sessionHasError: false,
          agentHasError: false,
          agentIsPending: false,
          agentIsBuffering: false,
          agentIsConnected: true,
          agentState: sdk.AgentState.speaking,
        ),
        SanaOrbState.speaking,
      );
      expect(
        resolveSanaOrbState(
          connectionState: sdk.ConnectionState.connected,
          sessionHasError: false,
          agentHasError: false,
          agentIsPending: false,
          agentIsBuffering: false,
          agentIsConnected: true,
          agentState: sdk.AgentState.thinking,
        ),
        SanaOrbState.thinking,
      );
      expect(
        resolveSanaOrbState(
          connectionState: sdk.ConnectionState.connected,
          sessionHasError: false,
          agentHasError: false,
          agentIsPending: false,
          agentIsBuffering: false,
          agentIsConnected: true,
          agentState: sdk.AgentState.listening,
        ),
        SanaOrbState.listening,
      );
    });

    test('local speaking overrides agent listening', () {
      expect(
        resolveSanaOrbState(
          connectionState: sdk.ConnectionState.connected,
          sessionHasError: false,
          agentHasError: false,
          agentIsPending: false,
          agentIsBuffering: false,
          agentIsConnected: true,
          agentState: sdk.AgentState.listening,
          localParticipantSpeaking: true,
        ),
        SanaOrbState.userSpeaking,
      );
    });

    test('connected without agent attributes defaults to listening', () {
      expect(
        resolveSanaOrbState(
          connectionState: sdk.ConnectionState.connected,
          sessionHasError: false,
          agentHasError: false,
          agentIsPending: false,
          agentIsBuffering: false,
          agentIsConnected: true,
        ),
        SanaOrbState.listening,
      );
    });
  });
}
