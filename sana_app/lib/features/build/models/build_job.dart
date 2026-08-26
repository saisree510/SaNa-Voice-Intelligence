/// Mirrors sana_backend's BuildJobOut schema (app/schemas/build.py) and
/// BuildJob status enum (app/services/build_job_service.py) — kept as
/// the same raw strings rather than re-encoded, so a status this app
/// doesn't recognize yet still displays as itself instead of crashing.
class BuildJob {
  const BuildJob({
    required this.id,
    required this.conversationId,
    required this.projectName,
    required this.projectType,
    required this.request,
    required this.status,
    required this.error,
    required this.hasArtifact,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BuildJob.fromJson(Map<String, dynamic> json) {
    return BuildJob(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String?,
      projectName: json['project_name'] as String,
      projectType: json['project_type'] as String,
      request: json['request'] as String,
      status: json['status'] as String,
      error: json['error'] as String?,
      hasArtifact: json['has_artifact'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final String id;
  final String? conversationId;
  final String projectName;
  final String projectType; // 'chrome_extension' | 'web_app'
  final String request;
  final String status;
  final String? error;
  final bool hasArtifact;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const _terminalStatuses = {'COMPLETED', 'FAILED'};
  static const _orderedSteps = [
    'PENDING',
    'PLANNING',
    'CREATING_WORKSPACE',
    'GENERATING_FILES',
    'VALIDATING',
    'FIXING',
    'PACKAGING',
    'COMPLETED',
  ];

  bool get isTerminal => _terminalStatuses.contains(status);
  bool get isCompleted => status == 'COMPLETED';
  bool get isFailed => status == 'FAILED';

  /// Index into [_orderedSteps] for a progress checklist — -1 if the
  /// status isn't a normal forward step (only really possible for
  /// 'FAILED', which the UI shows separately rather than as a step).
  int get stepIndex => _orderedSteps.indexOf(status);

  static const List<String> progressSteps = _orderedSteps;

  /// Human-readable label for a raw status string — used for both the
  /// current-step highlight and the checklist's own step labels.
  static String label(String status) {
    switch (status) {
      case 'PENDING':
        return 'Queued';
      case 'PLANNING':
        return 'Planning';
      case 'CREATING_WORKSPACE':
        return 'Creating workspace';
      case 'GENERATING_FILES':
        return 'Generating files';
      case 'VALIDATING':
        return 'Validating';
      case 'FIXING':
        return 'Fixing issues';
      case 'PACKAGING':
        return 'Packaging';
      case 'COMPLETED':
        return 'Completed';
      case 'FAILED':
        return 'Failed';
      default:
        return status;
    }
  }
}
