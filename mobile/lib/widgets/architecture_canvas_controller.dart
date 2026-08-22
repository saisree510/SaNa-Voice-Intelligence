import 'package:flutter/foundation.dart';

typedef ArchitectureCanvasCommandSender = void Function(String command);

class ArchitectureCanvasController extends ChangeNotifier {
  ArchitectureCanvasCommandSender? _sendCommand;

  bool _isReady = false;
  String _status = 'loading';
  int _appliedOperations = 0;
  int _totalOperations = 0;
  String? _lastError;

  bool get isReady => _isReady;
  String get status => _status;
  int get appliedOperations => _appliedOperations;
  int get totalOperations => _totalOperations;
  String? get lastError => _lastError;

  void bindCommandSender(ArchitectureCanvasCommandSender sender) {
    _sendCommand = sender;
  }

  void unbindCommandSender(ArchitectureCanvasCommandSender sender) {
    if (_sendCommand == sender) {
      _sendCommand = null;
    }
  }

  void sendCommand(String command) {
    _sendCommand?.call(command);
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
}
