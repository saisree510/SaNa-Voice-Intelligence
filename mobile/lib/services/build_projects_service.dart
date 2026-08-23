import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'build_stream_service.dart';
import 'token_service.dart';
import 'download_file.dart';

class BuildProjectSummary {
  BuildProjectSummary({
    required this.projectId,
    required this.title,
    required this.status,
    required this.workspacePath,
    required this.updatedAt,
    this.planSummary,
    this.latestResult,
    this.provider = 'prototype_scaffold',
  });

  final String projectId;
  final String title;
  final String status;
  final String workspacePath;
  final DateTime updatedAt;
  final String? planSummary;
  final String? latestResult;

  /// "deepcode" | "prototype_scaffold" — which coding agent produced this project.
  final String provider;

  bool get isDeepCode => provider == 'deepcode';

  bool get canDownload => status == 'completed';

  String get currentPhase => switch (status) {
        'plan_generated' => 'Plan ready',
        'approved' => 'Approved',
        'executing' => 'Building',
        'completed' => 'Completed',
        'failed' => 'Needs attention',
        _ => 'Drafting',
      };

  factory BuildProjectSummary.fromJson(Map<String, dynamic> json) {
    return BuildProjectSummary(
      projectId: json['project_id'] as String,
      title: json['title'] as String? ?? 'Untitled Project',
      status: json['status'] as String? ?? 'unknown',
      workspacePath: json['workspace_path'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      planSummary: json['plan_summary'] as String?,
      latestResult: json['result_summary'] as String?,
      provider: json['provider'] as String? ?? 'prototype_scaffold',
    );
  }
}

class BuildProjectRun {
  BuildProjectRun({
    required this.runId,
    required this.prompt,
    required this.status,
    required this.createdAt,
    required this.eventCount,
    this.provider = 'prototype_scaffold',
  });

  final String runId;
  final String prompt;
  final String status;
  final DateTime createdAt;
  final int eventCount;

  /// "deepcode" | "prototype_scaffold" — which coding agent executed this run.
  final String provider;

  bool get isDeepCode => provider == 'deepcode';

  factory BuildProjectRun.fromJson(Map<String, dynamic> json) {
    final events = json['events'] as List<dynamic>? ?? const [];
    return BuildProjectRun(
      runId: json['turn_id'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      eventCount: events.length,
      provider: json['provider'] as String? ?? 'prototype_scaffold',
    );
  }
}

class BuildProjectDetail extends BuildProjectSummary {
  BuildProjectDetail({
    required super.projectId,
    required super.title,
    required super.status,
    required super.workspacePath,
    required super.updatedAt,
    super.planSummary,
    super.latestResult,
    super.provider,
    required this.specification,
    required this.generatedFiles,
    required this.runs,
  });

  final String specification;
  final List<String> generatedFiles;
  final List<BuildProjectRun> runs;

  factory BuildProjectDetail.fromJson(Map<String, dynamic> json) {
    final files = json['generated_files'] as List<dynamic>? ?? const [];
    final history = json['history'] as List<dynamic>? ?? const [];
    return BuildProjectDetail(
      projectId: json['project_id'] as String,
      title: json['title'] as String? ?? 'Untitled Project',
      status: json['status'] as String? ?? 'unknown',
      workspacePath: json['workspace_path'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      planSummary: json['plan_summary'] as String?,
      provider: json['provider'] as String? ?? 'prototype_scaffold',
      specification: json['specification'] as String? ?? '',
      generatedFiles: files
          .whereType<Map<String, dynamic>>()
          .map((file) => file['path'] as String? ?? '')
          .where((path) => path.isNotEmpty)
          .toList(),
      runs: history.whereType<Map<String, dynamic>>().map(BuildProjectRun.fromJson).toList(),
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
  final BuildStreamService _streamService = BuildStreamService();
  String? _activeOwnerId;

  List<BuildProjectSummary> _projects = const [];
  bool _isLoading = false;
  String? _activeDownloadProjectId;
  String? _activeResumeProjectId;
  String? _activeBuildProjectId;
  List<BuildStreamEvent> _buildStreamEvents = const [];
  String? _errorMessage;

  List<BuildProjectSummary> get projects => _projects;
  bool get isLoading => _isLoading;
  String? get activeDownloadProjectId => _activeDownloadProjectId;
  String? get activeResumeProjectId => _activeResumeProjectId;
  String? get activeBuildProjectId => _activeBuildProjectId;
  List<BuildStreamEvent> get buildStreamEvents => _buildStreamEvents;
  String? get errorMessage => _errorMessage;
  bool get hasBackend => TokenService().backendUrl.isNotEmpty;
  bool get isStreaming => _activeBuildProjectId != null;

  void _handleAuthChanged() {
    final nextOwnerId = _authService.userId;
    if (nextOwnerId == _activeOwnerId) return;
    _activeOwnerId = nextOwnerId;
    _projects = const [];
    _isLoading = false;
    _activeDownloadProjectId = null;
    _activeResumeProjectId = null;
    _activeBuildProjectId = null;
    _buildStreamEvents = const [];
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

      final signedUri = Uri.parse(downloadUrl);
      final backendUri = Uri.parse(backendUrl);
      final resolvedDownloadUri = backendUri.replace(
        path: signedUri.path,
        query: signedUri.query,
      );
      final filename = '${project.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')}.zip';

      if (kIsWeb) {
        final downloaded = await downloadFile(resolvedDownloadUri, filename);
        if (!downloaded) {
          _errorMessage = 'The secure project archive could not be downloaded.';
        }
        return downloaded;
      }

      final launched = await launchUrl(
        resolvedDownloadUri,
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

  Future<BuildProjectDetail?> fetchProject(String projectId) async {
    if (_activeOwnerId == null || _authService.accessToken == null) {
      _errorMessage = 'A valid Supabase session is required to load this project.';
      notifyListeners();
      return null;
    }
    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) {
      _errorMessage = 'Backend URL is not configured for this build.';
      notifyListeners();
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$backendUrl/v1/build/projects/$projectId'),
        headers: _headers(),
      );
      if (response.statusCode != 200) {
        _errorMessage = 'Failed to load project details (${response.statusCode}).';
        notifyListeners();
        return null;
      }
      return BuildProjectDetail.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (error, stackTrace) {
      _logger.warning('Failed to load project $projectId: $error', error, stackTrace);
      _errorMessage = 'Failed to load project details.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> resumeProject(BuildProjectSummary project, String prompt) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) {
      _errorMessage = 'Enter the next change before resuming this project.';
      notifyListeners();
      return false;
    }
    if (_activeOwnerId == null || _authService.accessToken == null) {
      _errorMessage = 'A valid Supabase session is required to resume this project.';
      notifyListeners();
      return false;
    }
    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) {
      _errorMessage = 'Backend URL is not configured for this build.';
      notifyListeners();
      return false;
    }

    _activeResumeProjectId = project.projectId;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/v1/build/projects/${project.projectId}/turns'),
        headers: _headers(),
        body: jsonEncode({'prompt': cleanPrompt}),
      );
      if (response.statusCode != 200) {
        _errorMessage = 'Failed to resume project (${response.statusCode}).';
        return false;
      }
      await fetchProjects();
      return true;
    } catch (error, stackTrace) {
      _logger.warning('Failed to resume project ${project.projectId}: $error', error, stackTrace);
      _errorMessage = 'Failed to resume project.';
      return false;
    } finally {
      _activeResumeProjectId = null;
      notifyListeners();
    }
  }

  Future<BuildProjectSummary?> createProject(String title, String specification) async {
    if (_activeOwnerId == null || _authService.accessToken == null) {
      _errorMessage = 'A valid Supabase session is required to create a project.';
      notifyListeners();
      return null;
    }
    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) {
      _errorMessage = 'Backend URL is not configured.';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/v1/build/projects'),
        headers: _headers(),
        body: jsonEncode({
          'title': title,
          'specification': specification,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        _errorMessage = 'Failed to create build project (${response.statusCode}): ${response.body}';
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final summary = BuildProjectSummary.fromJson(data);
      await fetchProjects();
      return summary;
    } catch (error, stackTrace) {
      _logger.warning('Failed to create build project: $error', error, stackTrace);
      _errorMessage = 'Failed to create build project.';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> approveProject(String projectId) async {
    if (_activeOwnerId == null || _authService.accessToken == null) {
      _errorMessage = 'A valid Supabase session is required to approve this project.';
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
      final response = await http.post(
        Uri.parse('$backendUrl/v1/build/projects/$projectId/approve'),
        headers: _headers(),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        _errorMessage = 'Failed to approve build project (${response.statusCode}): ${response.body}';
        return false;
      }

      await fetchProjects();
      return true;
    } catch (error, stackTrace) {
      _logger.warning('Failed to approve build project $projectId: $error', error, stackTrace);
      _errorMessage = 'Failed to approve build project.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> streamBuild(String projectId) async {
    if (_activeOwnerId == null || _authService.accessToken == null) {
      _errorMessage = 'A valid Supabase session is required to stream builds.';
      notifyListeners();
      return;
    }
    final backendUrl = TokenService().backendUrl;
    if (backendUrl.isEmpty) {
      _errorMessage = 'Backend URL is not configured.';
      notifyListeners();
      return;
    }

    _activeBuildProjectId = projectId;
    _buildStreamEvents = const [];
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      // First, approve the project
      final approveResponse = await http.post(
        Uri.parse('$backendUrl/v1/build/projects/$projectId/approve'),
        headers: _headers(),
      );

      if (approveResponse.statusCode != 200 && approveResponse.statusCode != 201) {
        _errorMessage = 'Failed to approve project (${approveResponse.statusCode}): ${approveResponse.body}';
        _activeBuildProjectId = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      _isLoading = false;
      notifyListeners();

      // Then stream the build
      await _streamService.streamBuild(
        backendUrl: backendUrl,
        projectId: projectId,
        token: _authService.accessToken!,
        onEvent: (event) {
          _buildStreamEvents = [..._buildStreamEvents, event];
          notifyListeners();
          if (event.isComplete || event.isError) {
            _activeBuildProjectId = null;
            Future.delayed(const Duration(seconds: 2), () {
              fetchProjects();
            });
          }
        },
        onError: (error) {
          _errorMessage = error;
          _activeBuildProjectId = null;
          notifyListeners();
        },
      );
    } catch (error, stackTrace) {
      _logger.warning('Failed to stream build for project $projectId: $error', error, stackTrace);
      _errorMessage = 'Failed to execute build stream.';
      _activeBuildProjectId = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
