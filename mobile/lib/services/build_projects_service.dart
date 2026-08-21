import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'token_service.dart';

class BuildProjectSummary {
  BuildProjectSummary({
    required this.projectId,
    required this.title,
    required this.status,
    required this.workspacePath,
    required this.updatedAt,
  });

  final String projectId;
  final String title;
  final String status;
  final String workspacePath;
  final DateTime updatedAt;

  bool get canDownload => status == 'completed';

  factory BuildProjectSummary.fromJson(Map<String, dynamic> json) {
    return BuildProjectSummary(
      projectId: json['project_id'] as String,
      title: json['title'] as String? ?? 'Untitled Project',
      status: json['status'] as String? ?? 'unknown',
      workspacePath: json['workspace_path'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class BuildProjectsService extends ChangeNotifier {
  BuildProjectsService({required AuthService authService})
      : _authService = authService,
        _activeOwnerId = authService.userId {
    _authService.addListener(_handleAuthChanged);
  }

  static final _logger = Logger('BuildProjectsService');

  final AuthService _authService;
  String? _activeOwnerId;

  List<BuildProjectSummary> _projects = const [];
  bool _isLoading = false;
  String? _activeDownloadProjectId;
  String? _errorMessage;

  List<BuildProjectSummary> get projects => _projects;
  bool get isLoading => _isLoading;
  String? get activeDownloadProjectId => _activeDownloadProjectId;
  String? get errorMessage => _errorMessage;
  bool get hasBackend => TokenService().backendUrl.isNotEmpty;

  void _handleAuthChanged() {
    final nextOwnerId = _authService.userId;
    if (nextOwnerId == _activeOwnerId) return;
    _activeOwnerId = nextOwnerId;
    _projects = const [];
    _isLoading = false;
    _activeDownloadProjectId = null;
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

  Future<void> fetchProjects() async {
    if (_activeOwnerId == null || _authService.accessToken == null) {
      _projects = const [];
      _errorMessage = 'A valid Supabase session is required to load projects.';
      notifyListeners();
      return;
    }
    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) {
      _projects = const [];
      _errorMessage = 'Backend URL is not configured for this build.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$backendUrl/v1/build/projects'),
        headers: _headers(),
      );

      if (response.statusCode != 200) {
        _errorMessage = 'Failed to load build projects (${response.statusCode}).';
        _projects = const [];
        return;
      }

      final decoded = jsonDecode(response.body) as List<dynamic>;
      _projects = decoded.whereType<Map<String, dynamic>>().map(BuildProjectSummary.fromJson).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (error, stackTrace) {
      _logger.warning('Failed to fetch build projects: $error', error, stackTrace);
      _errorMessage = 'Failed to load build projects.';
      _projects = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> downloadProject(BuildProjectSummary project) async {
    if (_activeOwnerId == null || _authService.accessToken == null) {
      _errorMessage = 'A valid Supabase session is required to download projects.';
      notifyListeners();
      return false;
    }
    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) {
      _errorMessage = 'Backend URL is not configured for downloads.';
      notifyListeners();
      return false;
    }

    _activeDownloadProjectId = project.projectId;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$backendUrl/v1/build/projects/${project.projectId}/download-link'),
        headers: _headers(),
      );

      if (response.statusCode != 200) {
        _errorMessage = 'Failed to create download link (${response.statusCode}).';
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final downloadUrl = data['download_url'] as String?;
      if (downloadUrl == null || downloadUrl.isEmpty) {
        _errorMessage = 'Backend returned an empty download link.';
        return false;
      }

      final launched = await launchUrl(
        Uri.parse(downloadUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _errorMessage = 'Could not open the download link.';
        return false;
      }
      return true;
    } catch (error, stackTrace) {
      _logger.warning('Failed to download project ${project.projectId}: $error', error, stackTrace);
      _errorMessage = 'Failed to open the download link.';
      return false;
    } finally {
      _activeDownloadProjectId = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
