import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/errors/app_exception.dart';
import '../features/build/models/build_job.dart';
import 'backend_error.dart';

/// REST client for sana_backend's build-job API (app/api/build.py) —
/// the BuildAgent-backed endpoints under /api/build/jobs..., separate
/// from the older /api/build/run (DeepCode) route this app never
/// calls directly. Same shape as [RealConversationService]: token
/// supplied lazily (it can change/expire between calls), throws
/// [AppException] subtypes instead of leaking raw http/format errors.
class BuildService {
  BuildService({required String? Function() getAuthToken, http.Client? httpClient})
      : _getAuthToken = getAuthToken,
        _http = httpClient ?? http.Client();

  final String? Function() _getAuthToken;
  final http.Client _http;

  String _requireToken() {
    final token = _getAuthToken();
    if (token == null) {
      throw const AuthException('You need to be logged in to build a project.');
    }
    return token;
  }

  Map<String, String> _authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// Starts a new build (or a new step on an existing project — pass
  /// the same [projectName] again and describe the change in [task]).
  /// Returns immediately with the job in PENDING; poll [getJob] to
  /// watch it progress.
  Future<BuildJob> createJob({
    required String task,
    required String projectName,
    required String projectType,
    String? conversationId,
  }) async {
    final token = _requireToken();
    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/api/build/jobs'),
        headers: _authHeaders(token),
        body: jsonEncode({
          'task': task,
          'project_name': projectName,
          'project_type': projectType,
          'conversation_id': conversationId,
        }),
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's servers. Check your connection and try again.", e);
    }
    if (response.statusCode == 202) {
      return BuildJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    if (response.statusCode == 401) throw const AuthException('Your session has expired. Please log in again.');
    throw BuildException(extractBackendErrorDetail(response) ?? "Couldn't start the build. Please try again.");
  }

  Future<BuildJob> getJob(String jobId) async {
    final token = _requireToken();
    final http.Response response;
    try {
      response = await _http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/api/build/jobs/$jobId'),
        headers: _authHeaders(token),
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's servers. Check your connection and try again.", e);
    }
    if (response.statusCode == 200) {
      return BuildJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    if (response.statusCode == 401) throw const AuthException('Your session has expired. Please log in again.');
    if (response.statusCode == 404) throw const BuildException('That build could not be found.');
    throw BuildException(extractBackendErrorDetail(response) ?? "Couldn't check the build's status.");
  }

  /// The most recent build tied to [conversationId], or null if this
  /// conversation has never triggered one — lets the Build Workspace
  /// panel restore itself when a Build-mode conversation is reopened.
  Future<BuildJob?> getLatestJobForConversation(String conversationId) async {
    final token = _requireToken();
    final http.Response response;
    try {
      response = await _http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/api/build/jobs/by-conversation/$conversationId'),
        headers: _authHeaders(token),
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's servers. Check your connection and try again.", e);
    }
    if (response.statusCode == 200) {
      if (response.body.trim() == 'null') return null;
      return BuildJob.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    if (response.statusCode == 401) throw const AuthException('Your session has expired. Please log in again.');
    throw BuildException(extractBackendErrorDetail(response) ?? "Couldn't check for an existing build.");
  }

  Future<List<String>> listFiles(String jobId) async {
    final token = _requireToken();
    final http.Response response;
    try {
      response = await _http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/api/build/jobs/$jobId/files'),
        headers: _authHeaders(token),
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's servers. Check your connection and try again.", e);
    }
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['files'] as List).cast<String>();
    }
    if (response.statusCode == 401) throw const AuthException('Your session has expired. Please log in again.');
    throw BuildException(extractBackendErrorDetail(response) ?? "Couldn't list the build's files.");
  }

  Future<String> getFileContent(String jobId, String path) async {
    final token = _requireToken();
    final http.Response response;
    try {
      response = await _http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/api/build/jobs/$jobId/file').replace(
          queryParameters: {'path': path},
        ),
        headers: _authHeaders(token),
      );
    } catch (e) {
      throw NetworkException("Couldn't reach SANA's servers. Check your connection and try again.", e);
    }
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['content'] as String;
    }
    if (response.statusCode == 401) throw const AuthException('Your session has expired. Please log in again.');
    if (response.statusCode == 415) throw const BuildException("That file can't be displayed (it's binary).");
    throw BuildException(extractBackendErrorDetail(response) ?? "Couldn't open that file.");
  }

  /// A browser-navigable URL (auth token as a query param — see
  /// get_current_user_allow_query_token's docstring on the backend)
  /// for downloading the packaged ZIP directly, e.g. via url_launcher.
  String artifactDownloadUrl(String jobId) {
    final token = _requireToken();
    return '${AppConfig.backendBaseUrl}/api/build/jobs/$jobId/artifact?token=$token';
  }
}
