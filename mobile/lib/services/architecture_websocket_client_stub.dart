import 'architecture_websocket_client.dart';

ArchitectureWebSocketClient createWebSocketClient(
  String url, {
  required void Function(Map<String, dynamic> event) onEvent,
  required void Function(dynamic error) onError,
}) =>
    throw UnsupportedError('Cannot create a WebSocket client without HTML library');
