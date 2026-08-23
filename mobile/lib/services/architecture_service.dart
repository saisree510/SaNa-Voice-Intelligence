import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'auth_service.dart';
import 'token_service.dart';

class ArchitectureCanvasData {
  ArchitectureCanvasData({
    required this.architectureId,
    required this.title,
    required this.blueprint,
    required this.operations,
  });

  final String architectureId;
  final String title;
  final Map<String, dynamic> blueprint;
  final List<Map<String, dynamic>> operations;

  Map<String, Object?> toCanvasPayload() => {
        'architectureId': architectureId,
        'title': title,
        'blueprint': blueprint,
        'operations': operations,
      };

  factory ArchitectureCanvasData.fromJson(Map<String, dynamic> json) {
    final blueprint = Map<String, dynamic>.from(
      json['current_blueprint'] as Map? ?? const {},
    );
    return ArchitectureCanvasData(
      architectureId: json['architecture_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Architecture Blueprint',
      blueprint: blueprint,
      operations: _operationsFromBlueprint(blueprint),
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

  ArchitectureCanvasData? get latestArchitecture => _latestArchitecture;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void _handleAuthChanged() {
    final nextOwnerId = _authService.userId;
    if (nextOwnerId == _activeOwnerId) return;
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

  Future<void> fetchLatestArchitecture() async {
    if (_activeOwnerId == null || _authService.accessToken == null) {
      _latestArchitecture = null;
      _errorMessage = 'A valid Supabase session is required to load architecture.';
      notifyListeners();
      return;
    }

    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) {
      _latestArchitecture = null;
      _errorMessage = 'Backend URL is not configured for this build.';
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
        return;
      }

      records.sort((a, b) {
        final aDate = DateTime.tryParse(a['updated_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['updated_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      _latestArchitecture = ArchitectureCanvasData.fromJson(records.first);
    } catch (error, stackTrace) {
      _logger.warning('Failed to fetch latest architecture: $error', error, stackTrace);
      _latestArchitecture = null;
      _errorMessage = 'Failed to load architecture.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
