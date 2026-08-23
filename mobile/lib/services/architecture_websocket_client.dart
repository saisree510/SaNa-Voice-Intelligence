import 'architecture_websocket_client_stub.dart' if (dart.library.html) 'architecture_websocket_client_web.dart';

abstract class ArchitectureWebSocketClient {
  factory ArchitectureWebSocketClient(
    String url, {
    required void Function(Map<String, dynamic> event) onEvent,
    required void Function(dynamic error) onError,
  }) =>
      createWebSocketClient(url, onEvent: onEvent, onError: onError);

  void close();
}
