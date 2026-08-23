import 'dart:convert';
import 'dart:html' as html;
import 'architecture_websocket_client.dart';

class ArchitectureWebSocketClientImpl implements ArchitectureWebSocketClient {
  ArchitectureWebSocketClientImpl(
    String url, {
    required this.onEvent,
    required this.onError,
  }) {
    _socket = html.WebSocket(url);
    _socket.onMessage.listen((event) {
      final data = event.data;
      if (data is String) {
        try {
          final parsed = jsonDecode(data);
          if (parsed is Map<String, dynamic>) {
            onEvent(parsed);
          }
        } catch (_) {}
      }
    });
    _socket.onError.listen(onError);
  }

  final void Function(Map<String, dynamic> event) onEvent;
  final void Function(dynamic error) onError;
  late final html.WebSocket _socket;

  @override
  void close() {
    _socket.close();
  }

  @override
  void send(Map<String, dynamic> data) {
    _socket.send(jsonEncode(data));
  }
}

ArchitectureWebSocketClient createWebSocketClient(
  String url, {
  required void Function(Map<String, dynamic> event) onEvent,
  required void Function(dynamic error) onError,
}) =>
    ArchitectureWebSocketClientImpl(url, onEvent: onEvent, onError: onError);
