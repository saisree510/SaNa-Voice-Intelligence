import 'package:flutter/foundation.dart';

import '../services/architecture_service.dart';

typedef ArchitectureCanvasMessageSender = void Function(String type, Map<String, Object?> payload);

class ArchitectureCanvasController extends ChangeNotifier {
  ArchitectureCanvasMessageSender? _sendMessage;
  Map<String, Object?>? _pendingCanvasPayload;

  bool _isReady = false;
  String _status = 'loading';
  int _appliedOperations = 0;
  int _totalOperations = 0;
  String? _lastError;
  bool _isReadOnly = false;

  bool get isReady => _isReady;
  String get status => _status;
  int get appliedOperations => _appliedOperations;
  int get totalOperations => _totalOperations;
  String? get lastError => _lastError;
  bool get isReadOnly => _isReadOnly;

  void bindMessageSender(ArchitectureCanvasMessageSender sender) {
    _sendMessage = sender;
    _sendPendingBlueprint();
  }

  void unbindMessageSender(ArchitectureCanvasMessageSender sender) {
    if (_sendMessage == sender) {
      _sendMessage = null;
    }
  }

  void sendCommand(String command) {
    _sendMessage?.call('soul.canvas.command', {'command': command});
  }

  void loadArchitecture(ArchitectureCanvasData architecture) {
    _pendingCanvasPayload = architecture.toCanvasPayload();
    _status = architecture.operations.isEmpty ? 'ready' : 'drawing';
    _appliedOperations = 0;
    _totalOperations = architecture.operations.length;
    _lastError = null;
    _sendPendingBlueprint();
    notifyListeners();
  }

  void resendArchitecture() {
    _sendPendingBlueprint();
  }

  void _sendPendingBlueprint() {
    final payload = _pendingCanvasPayload;
    if (payload == null) return;
    _sendMessage?.call('soul.canvas.load_blueprint', payload);
  }

  void markReady({required int totalOperations}) {
    _isReady = true;
    _lastError = null;
    _totalOperations = totalOperations;
    notifyListeners();
  }

  void updateState({
    required String status,
    required int appliedOperations,
    required int totalOperations,
  }) {
    _status = status;
    _appliedOperations = appliedOperations;
    _totalOperations = totalOperations;
    _lastError = null;
    notifyListeners();
  }

  void reject(String reason) {
    _lastError = reason;
    notifyListeners();
  }

  void setReadOnly(bool readOnly) {
    _isReadOnly = readOnly;
    notifyListeners();
  }
}
