import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'auth_service.dart';
import 'token_service.dart';
import 'architecture_websocket_client.dart';
import 'package:uuid/uuid.dart';

class ArchitectureCanvasData {
  ArchitectureCanvasData({
    required this.architectureId,
    required this.title,
    required this.blueprint,
    required this.operations,
    this.projectId,
  });

  final String architectureId;
  final String title;
  final Map<String, dynamic> blueprint;
  final List<Map<String, dynamic>> operations;
  final String? projectId;

  int get componentCount => (blueprint['components'] as List? ?? const []).length;
  int get connectionCount => (blueprint['connections'] as List? ?? const []).length;
  bool get isDisplayable => componentCount >= 1 || connectionCount >= 1;

  Map<String, Object?> toCanvasPayload() => {
        'architectureId': architectureId,
        'title': title,
        'blueprint': blueprint,
        'operations': operations,
        'projectId': projectId,
      };

  factory ArchitectureCanvasData.fromJson(Map<String, dynamic> json) {
    final blueprintRaw = json['current_blueprint'] as Map? ?? const {};
    final blueprint = {
      ...Map<String, dynamic>.from(blueprintRaw),
      'components': List<Map<String, dynamic>>.from(
        (blueprintRaw['components'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
      ),
      'connections': List<Map<String, dynamic>>.from(
        (blueprintRaw['connections'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
      ),
    };
    return ArchitectureCanvasData(
      architectureId: json['architecture_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Architecture Blueprint',
      blueprint: blueprint,
      operations: _operationsFromBlueprint(blueprint),
      projectId: json['project_id'] as String?,
    );
  }

  static List<Map<String, dynamic>> _operationsFromBlueprint(Map<String, dynamic> blueprint) {
    final components = (blueprint['components'] as List? ?? const []).whereType<Map>().toList();
    final connections = (blueprint['connections'] as List? ?? const []).whereType<Map>().toList();

    return [
      for (final component in components)
        if ((component['id'] as String? ?? '').isNotEmpty)
          {
            'type': 'add_node',
            'componentId': component['id'],
          },
      for (final connection in connections)
        if ((connection['id'] as String? ?? '').isNotEmpty)
          {
            'type': 'connect_nodes',
            'connectionId': connection['id'],
          },
    ];
  }

  void applyCanvasEvent(Map<String, dynamic> eventData) {
    final operation = eventData['operation'] as Map<String, dynamic>?;
    if (operation == null) return;

    final operationType = operation['operation_type'] as String?;
    final payload = operation['payload'] as Map<String, dynamic>?;
    if (operationType == null || payload == null) return;

    if (operationType == 'add_node') {
      final component = payload['component'] as Map<String, dynamic>?;
      if (component != null && component['id'] != null) {
        final currentComponents = List<Map<String, dynamic>>.from(
          (blueprint['components'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        if (!currentComponents.any((c) => c['id'] == component['id'])) {
          currentComponents.add(component);
          blueprint['components'] = currentComponents;
          operations.add({
            'type': 'add_node',
            'componentId': component['id'],
          });
        }
      }
    } else if (operationType == 'update_node') {
      final componentId = payload['component_id'] as String?;
      if (componentId != null) {
        final currentComponents = List<Map<String, dynamic>>.from(
          (blueprint['components'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        blueprint['components'] = [
          for (final component in currentComponents)
            if (component['id'] == componentId)
              {
                ...component,
                if (payload['name'] != null) 'name': payload['name'],
                if (payload['type'] != null) 'type': payload['type'],
                if (payload['type'] != null) 'component_type': payload['type'],
                if (payload['technology'] != null) 'technology': payload['technology'],
                if (payload['metadata'] != null) 'metadata': payload['metadata'],
              }
            else
              component,
        ];
      }
    } else if (operationType == 'delete_node') {
      final componentId = payload['component_id'] as String?;
      if (componentId != null) {
        final currentComponents = List<Map<String, dynamic>>.from(
          (blueprint['components'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        final currentConnections = List<Map<String, dynamic>>.from(
          (blueprint['connections'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        blueprint['components'] = currentComponents.where((component) => component['id'] != componentId).toList();
        blueprint['connections'] = currentConnections
            .where((connection) =>
                connection['source_id'] != componentId &&
                connection['target_id'] != componentId &&
                connection['sourceId'] != componentId &&
                connection['targetId'] != componentId)
            .toList();
        operations.removeWhere(
            (operation) => operation['componentId'] == componentId || operation['component_id'] == componentId);
      }
    } else if (operationType == 'connect_nodes') {
      final connection = payload['connection'] as Map<String, dynamic>?;
      if (connection != null && connection['id'] != null) {
        final currentConnections = List<Map<String, dynamic>>.from(
          (blueprint['connections'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        if (!currentConnections.any((c) => c['id'] == connection['id'])) {
          currentConnections.add(connection);
          blueprint['connections'] = currentConnections;
          operations.add({
            'type': 'connect_nodes',
            'connectionId': connection['id'],
          });
        }
      }
    } else if (operationType == 'disconnect_nodes') {
      final connectionId = payload['connection_id'] as String?;
      if (connectionId != null) {
        final currentConnections = List<Map<String, dynamic>>.from(
          (blueprint['connections'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        blueprint['connections'] = currentConnections.where((connection) => connection['id'] != connectionId).toList();
        operations.removeWhere(
            (operation) => operation['connectionId'] == connectionId || operation['connection_id'] == connectionId);
      }
    }
  }
}

class ArchitectureService extends ChangeNotifier {
  ArchitectureService({required AuthService authService})
      : _authService = authService,
        _activeOwnerId = authService.userId {
    _authService.addListener(_handleAuthChanged);
  }

  static final _logger = Logger('ArchitectureService');

  final AuthService _authService;
  String? _activeOwnerId;
  ArchitectureCanvasData? _latestArchitecture;
  bool _isLoading = false;
  String? _errorMessage;
  ArchitectureWebSocketClient? _wsClient;
  String? _connectedArchitectureId;

  ArchitectureCanvasData? get latestArchitecture => _latestArchitecture;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void _handleAuthChanged() {
    final nextOwnerId = _authService.userId;
    if (nextOwnerId == _activeOwnerId) return;
    disconnectFromCanvasStream();
    _activeOwnerId = nextOwnerId;
    _latestArchitecture = null;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final accessToken = _authService.accessToken;
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    return headers;
  }

  Future<void> fetchLatestArchitecture({String? preferredProjectId}) async {
    if (_activeOwnerId == null || _authService.accessToken == null) {
      _latestArchitecture = null;
      _errorMessage = 'A valid Supabase session is required to load architecture.';
      disconnectFromCanvasStream();
      notifyListeners();
      return;
    }

    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) {
      _latestArchitecture = null;
      _errorMessage = 'Backend URL is not configured for this build.';
      disconnectFromCanvasStream();
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$backendUrl/v1/architectures'),
        headers: _headers(),
      );

      if (response.statusCode != 200) {
        _latestArchitecture = null;
        _errorMessage = 'Failed to load architecture (${response.statusCode}).';
        return;
      }

      final decoded = jsonDecode(response.body) as List<dynamic>;
      final records = decoded.whereType<Map<String, dynamic>>().toList();
      if (records.isEmpty) {
        _latestArchitecture = null;
        disconnectFromCanvasStream();
        return;
      }

      final architectures = records.map(ArchitectureCanvasData.fromJson).where((item) => item.isDisplayable).toList();
      if (architectures.isEmpty) {
        _latestArchitecture = null;
        disconnectFromCanvasStream();
        return;
      }

      architectures.sort((a, b) {
        final projectCompare =
            _projectMatchScore(b, preferredProjectId).compareTo(_projectMatchScore(a, preferredProjectId));
        if (projectCompare != 0) return projectCompare;

        final aSource = records.firstWhere((record) => record['architecture_id'] == a.architectureId);
        final bSource = records.firstWhere((record) => record['architecture_id'] == b.architectureId);
        final aDate =
            DateTime.tryParse(aSource['updated_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            DateTime.tryParse(bSource['updated_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateCompare = bDate.compareTo(aDate);
        if (dateCompare != 0) return dateCompare;

        return _displayScore(b).compareTo(_displayScore(a));
      });
      _latestArchitecture = architectures.first;
      if (_latestArchitecture != null) {
        connectToCanvasStream(_latestArchitecture!.architectureId);
      }
    } catch (error, stackTrace) {
      _logger.warning('Failed to fetch latest architecture: $error', error, stackTrace);
      _latestArchitecture = null;
      _errorMessage = 'Failed to load architecture.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchArchitectureById(String architectureId) async {
    if (_activeOwnerId == null || _authService.accessToken == null) {
      _latestArchitecture = null;
      _errorMessage = 'A valid Supabase session is required to load architecture.';
      disconnectFromCanvasStream();
      notifyListeners();
      return;
    }

    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) {
      _latestArchitecture = null;
      _errorMessage = 'Backend URL is not configured for this build.';
      disconnectFromCanvasStream();
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$backendUrl/v1/architectures/$architectureId'),
        headers: _headers(),
      );

      if (response.statusCode != 200) {
        _latestArchitecture = null;
        _errorMessage = 'Failed to load architecture (${response.statusCode}).';
        disconnectFromCanvasStream();
        return;
      }

      final architecture = ArchitectureCanvasData.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      if (!architecture.isDisplayable) {
        _latestArchitecture = null;
        disconnectFromCanvasStream();
        return;
      }
      _latestArchitecture = architecture;
      connectToCanvasStream(architecture.architectureId);
    } catch (error, stackTrace) {
      _logger.warning('Failed to fetch architecture $architectureId: $error', error, stackTrace);
      _latestArchitecture = null;
      _errorMessage = 'Failed to load architecture.';
      disconnectFromCanvasStream();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _wsUrl(String architectureId) {
    final backendUrl = TokenService().backendUrl;
    final parsed = Uri.parse(backendUrl);
    final scheme = parsed.scheme == 'https' ? 'wss' : 'ws';
    final basePath = parsed.path.endsWith('/') ? parsed.path.substring(0, parsed.path.length - 1) : parsed.path;
    final token = _authService.accessToken ?? '';

    return Uri(
      scheme: scheme,
      host: parsed.host,
      port: parsed.port != 0 ? parsed.port : null,
      path: '$basePath/v1/architectures/$architectureId/ws',
      queryParameters: {'token': token},
    ).toString();
  }

  void connectToCanvasStream(String architectureId) {
    if (_wsClient != null && _connectedArchitectureId == architectureId) {
      return;
    }
    disconnectFromCanvasStream();
    if (_activeOwnerId == null || _authService.accessToken == null) return;

    final url = _wsUrl(architectureId);
    _logger.info('Connecting to canvas WebSocket stream at $url');
    try {
      _wsClient = ArchitectureWebSocketClient(
        url,
        onEvent: (event) {
          if (event['type'] == 'canvas_event') {
            final eventData = event['event'] as Map<String, dynamic>?;
            if (eventData != null && _latestArchitecture != null) {
              _logger.fine('Received canvas stream event: $eventData');
              _latestArchitecture!.applyCanvasEvent(eventData);
              notifyListeners();
            }
          }
        },
        onError: (err) {
          _logger.warning('Canvas WebSocket stream error: $err');
        },
      );
      _connectedArchitectureId = architectureId;
    } catch (e) {
      _logger.warning('Failed to establish canvas WebSocket connection: $e');
    }
  }

  void disconnectFromCanvasStream() {
    if (_wsClient != null) {
      _logger.info('Closing canvas WebSocket stream');
      _wsClient!.close();
      _wsClient = null;
    }
    _connectedArchitectureId = null;
  }

  @override
  void dispose() {
    disconnectFromCanvasStream();
    super.dispose();
  }

  Future<void> submitCanvasOperation(
    String operationType,
    Map<String, dynamic> operationPayload,
  ) async {
    final activeArch = _latestArchitecture;
    if (activeArch == null) return;

    final baseVersion = activeArch.blueprint['version'] as int? ?? 1;
    final nextSeq = baseVersion + 1;
    final idempotencyKey = const Uuid().v4();
    final operationId = 'op-${operationType.replaceAll('_', '-')}-${const Uuid().v4().substring(0, 8)}';

    final operation = {
      'operation_id': operationId,
      'architecture_id': activeArch.architectureId,
      'base_version': baseVersion,
      'operation_type': operationType,
      'actor': 'user',
      'payload': operationPayload,
    };

    final message = {
      'type': 'canvas_operation',
      'sequence_number': nextSeq,
      'idempotency_key': idempotencyKey,
      'operation': operation,
    };

    if (_wsClient != null) {
      _logger.info('Submitting canvas operation via WebSocket: $operationType');
      try {
        _wsClient!.send(message);
        return;
      } catch (e) {
        _logger.warning('Failed to send canvas operation via WebSocket: $e. Falling back to HTTP POST.');
      }
    }

    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) return;

    _logger.info('Submitting canvas operation via HTTP POST: $operationType');
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/v1/architectures/${activeArch.architectureId}/events'),
        headers: _headers(),
        body: jsonEncode({
          'sequence_number': nextSeq,
          'idempotency_key': idempotencyKey,
          'operation': operation,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        _logger.warning('Failed to append canvas event via HTTP POST (${response.statusCode}): ${response.body}');
      }
    } catch (e, st) {
      _logger.severe('Error appending canvas event via HTTP POST: $e', e, st);
    }
  }

  Future<void> createCanvasSnapshot(
    String architectureId,
    int sequenceNumber,
    Map<String, dynamic> scene,
  ) async {
    final activeArch = _latestArchitecture;
    if (activeArch == null) return;

    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) return;

    _logger.info('Creating canvas snapshot for sequence number: $sequenceNumber');
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/v1/architectures/$architectureId/snapshots'),
        headers: _headers(),
        body: jsonEncode({
          'sequence_number': sequenceNumber,
          'blueprint': activeArch.blueprint,
          'scene': scene,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        _logger.warning('Failed to create canvas snapshot (${response.statusCode}): ${response.body}');
      } else {
        _logger.info('Canvas snapshot created successfully.');
      }
    } catch (e, st) {
      _logger.severe('Error creating canvas snapshot: $e', e, st);
    }
  }

  Future<bool> approveArchitectureBlueprint(String projectId) async {
    final activeArch = _latestArchitecture;
    if (activeArch == null) {
      _errorMessage = 'No active architecture to approve.';
      notifyListeners();
      return false;
    }

    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) {
      _errorMessage = 'Backend URL is not configured.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final approvedBlueprint = Map<String, dynamic>.from(activeArch.blueprint);
      approvedBlueprint['status'] = 'approved';
      approvedBlueprint['approved_at'] = DateTime.now().toUtc().toIso8601String();

      final versionResponse = await http.post(
        Uri.parse('$backendUrl/v1/architectures/${activeArch.architectureId}/versions'),
        headers: _headers(),
        body: jsonEncode({
          'blueprint': approvedBlueprint,
        }),
      );

      if (versionResponse.statusCode != 200 && versionResponse.statusCode != 201) {
        _logger.warning('Failed to save blueprint version: ${versionResponse.body}');
      }

      final patchResponse = await http.patch(
        Uri.parse('$backendUrl/v1/architectures/${activeArch.architectureId}'),
        headers: _headers(),
        body: jsonEncode({
          'current_blueprint': approvedBlueprint,
          'project_id': projectId,
        }),
      );

      if (patchResponse.statusCode != 200 && patchResponse.statusCode != 201) {
        _errorMessage = 'Failed to update architecture: ${patchResponse.body}';
        return false;
      }

      await fetchLatestArchitecture();
      return true;
    } catch (e, st) {
      _logger.severe('Failed to approve architecture blueprint: $e', e, st);
      _errorMessage = 'Failed to approve architecture blueprint.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  int _displayScore(ArchitectureCanvasData architecture) =>
      architecture.componentCount + architecture.connectionCount * 2;

  int _projectMatchScore(ArchitectureCanvasData architecture, String? preferredProjectId) {
    if (preferredProjectId == null || preferredProjectId.isEmpty) return 0;
    return architecture.projectId == preferredProjectId ? 1 : 0;
  }
}
