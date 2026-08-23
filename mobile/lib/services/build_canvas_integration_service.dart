import 'package:flutter/foundation.dart';

import 'build_stream_service.dart';

/// Tracks which components are being built based on file paths and events
class BuildComponentStatus {
  BuildComponentStatus({
    required this.componentId,
    required this.componentName,
    this.status = 'pending',
    this.filesGenerated = 0,
    this.filesEdited = 0,
    this.testsRun = 0,
    this.errors = const [],
  });

  final String componentId;
  final String componentName;
  String status; // pending, building, completed, failed
  int filesGenerated;
  int filesEdited;
  int testsRun;
  List<String> errors;

  bool get isActive => status == 'building';
  bool get isComplete => status == 'completed';
  bool get hasFailed => status == 'failed';

  Map<String, dynamic> toJson() => {
        'componentId': componentId,
        'componentName': componentName,
        'status': status,
        'filesGenerated': filesGenerated,
        'filesEdited': filesEdited,
        'testsRun': testsRun,
        'errors': errors,
      };
}

/// Maps build events to canvas components for real-time visualization
class BuildCanvasIntegrationService extends ChangeNotifier {
  BuildCanvasIntegrationService({required this.componentPatterns});

  // Map component names/IDs to file path patterns for detection
  // e.g., {'api-server': ['src/server/', 'src/api/']}
  final Map<String, List<String>> componentPatterns;

  Map<String, BuildComponentStatus> _componentStatus = {};
  int _totalFilesGenerated = 0;
  int _totalFilesEdited = 0;
  int _totalTestsRun = 0;
  List<String> _buildErrors = [];

  Map<String, BuildComponentStatus> get componentStatus => _componentStatus;
  int get totalFilesGenerated => _totalFilesGenerated;
  int get totalFilesEdited => _totalFilesEdited;
  int get totalTestsRun => _totalTestsRun;
  List<String> get buildErrors => _buildErrors;

  void initialize(List<String> componentIds) {
    _componentStatus = {
      for (final id in componentIds)
        id: BuildComponentStatus(
          componentId: id,
          componentName: componentPatterns.keys
                  .firstWhere((k) => k == id, orElse: () => id)
              ,
        )
    };
    _totalFilesGenerated = 0;
    _totalFilesEdited = 0;
    _totalTestsRun = 0;
    _buildErrors = [];
    notifyListeners();
  }

  String? _detectComponentFromPath(String filePath) {
    for (final componentId in componentPatterns.keys) {
      final patterns = componentPatterns[componentId] ?? [];
      for (final pattern in patterns) {
        if (filePath.contains(pattern)) {
          return componentId;
        }
      }
    }
    return null;
  }

  void processBuildEvent(BuildStreamEvent event) {
    switch (event.eventType) {
      case 'start':
        _markComponentsBuilding();

      case 'file_create' || 'file_edit':
        _totalFilesGenerated++;
        if (event.eventType == 'file_edit') _totalFilesEdited++;

        // Try to extract file path from details or message
        final filePath = event.details['path'] as String? ?? event.message;
        final componentId = _detectComponentFromPath(filePath);
        if (componentId != null && _componentStatus.containsKey(componentId)) {
          _componentStatus[componentId]!.filesGenerated++;
          _componentStatus[componentId]!.status = 'building';
        }

      case 'test_result':
        _totalTestsRun++;
        final filePath = event.details['path'] as String? ?? event.message;
        final componentId = _detectComponentFromPath(filePath);
        if (componentId != null && _componentStatus.containsKey(componentId)) {
          _componentStatus[componentId]!.testsRun++;
        }

      case 'complete':
        _markComponentsCompleted();

      case 'error':
        _buildErrors.add(event.message);
        _markComponentsFailed();
    }
    notifyListeners();
  }

  void _markComponentsBuilding() {
    for (final status in _componentStatus.values) {
      if (status.status == 'pending') {
        status.status = 'building';
      }
    }
  }

  void _markComponentsCompleted() {
    for (final status in _componentStatus.values) {
      if (status.status == 'building') {
        status.status = 'completed';
      }
    }
  }

  void _markComponentsFailed() {
    for (final status in _componentStatus.values) {
      if (status.status == 'building') {
        status.status = 'failed';
      }
    }
  }

  void reset() {
    _componentStatus.clear();
    _totalFilesGenerated = 0;
    _totalFilesEdited = 0;
    _totalTestsRun = 0;
    _buildErrors = [];
    notifyListeners();
  }
}
