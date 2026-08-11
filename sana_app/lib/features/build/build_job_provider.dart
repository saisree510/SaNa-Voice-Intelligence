import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/error_display.dart';
import '../../services/build_service.dart';
import 'models/build_job.dart';

/// Drives the Build Workspace panel for one Build-mode conversation.
///
/// The actual build is triggered conversationally — SANA's LLM calls
/// the build_project tool mid-reply (see sana_backend's build_tools.py),
/// not a button in this panel. So this provider's job is to notice
/// that happened: after every message sent in Build mode,
/// [refreshForConversation] asks the backend "what's the latest build
/// job for this conversation now" and, if it's new or still running,
/// starts polling it until it reaches a terminal state — that's what
/// turns into the panel's live progress checklist.
class BuildJobProvider extends ChangeNotifier {
  BuildJobProvider({required BuildService buildService}) : _service = buildService;

  final BuildService _service;
  Timer? _pollTimer;

  BuildJob? job;
  List<String> files = [];
  bool isLoadingFiles = false;
  String? selectedFilePath;
  String? selectedFileContent;
  bool isLoadingFileContent = false;
  String? errorMessage;

  // A completed build's ZIP downloads itself automatically — no manual
  // click needed (see BuildWorkspacePanel, which still shows a manual
  // button too, as a fallback for whenever a browser's popup blocker
  // silently swallows the automatic one — best-effort, not guaranteed).
  // Tracked per job id, not per provider lifetime, so revisiting a
  // conversation whose build already auto-downloaded earlier this
  // session doesn't trigger it again.
  final Set<String> _autoDownloadedJobIds = {};

  /// Whether the current [job]'s ZIP has already been auto-downloaded
  /// this session — lets the panel say "downloaded automatically"
  /// instead of just silently re-showing an unexplained button.
  bool get artifactAutoDownloaded => job != null && _autoDownloadedJobIds.contains(job!.id);

  /// Checks for a build tied to [conversationId] and starts tracking it
  /// if there is one — safe to call after every message in Build mode;
  /// a no-op (network-wise, cheap) if nothing has ever been built in
  /// this conversation, and does nothing new if the job we're already
  /// tracking is still the latest one.
  Future<void> refreshForConversation(String? conversationId) async {
    if (conversationId == null) return;
    try {
      final latest = await _service.getLatestJobForConversation(conversationId);
      if (latest == null) return;
      if (job?.id == latest.id && job?.status == latest.status) return; // nothing new
      job = latest;
      files = [];
      selectedFilePath = null;
      selectedFileContent = null;
      notifyListeners();
      if (!latest.isTerminal) {
        _startPolling();
      } else if (latest.isCompleted) {
        unawaited(_loadFiles());
        unawaited(_maybeAutoDownload(latest));
      }
    } catch (_) {
      // A background "did a build start" check — don't surface an
      // error banner for it, the next chat turn will just try again.
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    final current = job;
    if (current == null || current.isTerminal) {
      _pollTimer?.cancel();
      return;
    }
    try {
      final updated = await _service.getJob(current.id);
      job = updated;
      notifyListeners();
      if (updated.isTerminal) {
        _pollTimer?.cancel();
        if (updated.isCompleted) {
          unawaited(_loadFiles());
          unawaited(_maybeAutoDownload(updated));
        }
      }
    } catch (_) {
      // Transient poll failure -- try again next tick instead of
      // flashing an error banner during a normal build.
    }
  }

  /// Triggers the ZIP download the moment a build is found complete —
  /// at most once per job id per app session (see _autoDownloadedJobIds).
  /// Opening a new tab from a timer callback (not a direct click) is
  /// exactly what browser popup blockers exist to catch, so this is
  /// best-effort: if it's blocked, it fails silently here rather than
  /// showing an error banner for something the user didn't click —
  /// the panel's manual Download ZIP button always still works.
  Future<void> _maybeAutoDownload(BuildJob completedJob) async {
    if (!completedJob.hasArtifact) return;
    if (!_autoDownloadedJobIds.add(completedJob.id)) return; // already done this session

    final url = _service.artifactDownloadUrl(completedJob.id);
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault, webOnlyWindowName: '_blank');
    } catch (_) {
      // Silent -- see docstring above.
    }
  }

  Future<void> _loadFiles() async {
    final current = job;
    if (current == null) return;
    isLoadingFiles = true;
    notifyListeners();
    try {
      files = await _service.listFiles(current.id);
    } catch (e) {
      errorMessage = errorMessageFor(e);
    } finally {
      isLoadingFiles = false;
      notifyListeners();
    }
  }

  Future<void> selectFile(String path) async {
    final current = job;
    if (current == null) return;
    selectedFilePath = path;
    selectedFileContent = null;
    isLoadingFileContent = true;
    errorMessage = null;
    notifyListeners();
    try {
      selectedFileContent = await _service.getFileContent(current.id, path);
    } catch (e) {
      errorMessage = errorMessageFor(e);
    } finally {
      isLoadingFileContent = false;
      notifyListeners();
    }
  }

  void clearSelectedFile() {
    selectedFilePath = null;
    selectedFileContent = null;
    notifyListeners();
  }

  /// Null until there's a real ZIP to download (see [BuildJob.hasArtifact]).
  String? artifactDownloadUrl() {
    final current = job;
    if (current == null || !current.hasArtifact) return null;
    return _service.artifactDownloadUrl(current.id);
  }

  /// Called when switching to a different conversation/starting a new
  /// one, so this panel doesn't keep showing a build from another thread.
  void reset() {
    _pollTimer?.cancel();
    job = null;
    files = [];
    selectedFilePath = null;
    selectedFileContent = null;
    errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
