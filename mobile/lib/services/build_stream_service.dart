import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

class BuildStreamEvent {
  BuildStreamEvent({
    required this.eventType,
    required this.message,
    this.details = const {},
    this.timestamp,
    this.provider = 'prototype_scaffold',
    this.generatedFiles = const [],
  });

  final String eventType;
  final String message;
  final Map<String, dynamic> details;
  final DateTime? timestamp;
  final String provider;
  final List<String> generatedFiles;

  bool get isComplete => eventType == 'complete';
  bool get isError => eventType == 'error';
  bool get isStart => eventType == 'start';

  factory BuildStreamEvent.fromJson(Map<String, dynamic> json) {
    return BuildStreamEvent(
      eventType: json['event_type'] as String? ?? 'log',
      message: json['message'] as String? ?? '',
      details: (json['details'] as Map<String, dynamic>?) ?? {},
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
      provider: json['provider'] as String? ?? 'prototype_scaffold',
      generatedFiles:
          (json['generated_files'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

typedef BuildStreamCallback = void Function(BuildStreamEvent event);
typedef BuildStreamErrorCallback = void Function(String error);

class BuildStreamService {
  BuildStreamService();

  static final _logger = Logger('BuildStreamService');

  Future<void> streamBuild({
    required String backendUrl,
    required String projectId,
    required String token,
    required BuildStreamCallback onEvent,
    required BuildStreamErrorCallback onError,
  }) async {
    final uri = Uri.parse('$backendUrl/v1/build/projects/$projectId/stream');

    try {
      final request = http.Request('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'text/event-stream';

      final response = await request.send();

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        final error = 'Stream failed with status ${response.statusCode}: $errorBody';
        _logger.warning(error);
        onError(error);
        return;
      }

      // Parse SSE stream
      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            try {
              final jsonStr = line.substring(6);
              final json = jsonDecode(jsonStr) as Map<String, dynamic>;
              final event = BuildStreamEvent.fromJson(json);
              onEvent(event);
            } catch (e) {
              _logger.warning('Failed to parse SSE event: $e');
            }
          }
        },
        onError: (error, stackTrace) {
          _logger.warning('Stream error: $error', error, stackTrace);
          onError(error.toString());
        },
        onDone: () {
          _logger.info('Build stream completed');
        },
      );
    } catch (error, stackTrace) {
      _logger.warning('Failed to start build stream: $error', error, stackTrace);
      onError(error.toString());
    }
  }
}
