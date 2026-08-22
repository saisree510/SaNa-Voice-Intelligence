// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

import 'architecture_canvas_controller.dart';

class ArchitectureCanvasView extends StatefulWidget {
  const ArchitectureCanvasView({super.key, this.controller});

  final ArchitectureCanvasController? controller;

  @override
  State<ArchitectureCanvasView> createState() => _ArchitectureCanvasViewState();
}

class _ArchitectureCanvasViewState extends State<ArchitectureCanvasView> {
  static const int _protocolVersion = 1;
  static const String _flutterSource = 'soul-flutter';
  static const String _canvasSource = 'soul-canvas';

  late final String _viewType = 'soul-architecture-canvas-${identityHashCode(this)}';
  html.IFrameElement? _iframe;
  StreamSubscription<html.MessageEvent>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    widget.controller?.bindCommandSender(_sendCommand);
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final frame = html.IFrameElement()
          ..src = _canvasUrl()
          ..title = 'Soul Architecture Blueprint'
          ..allow = 'clipboard-read; clipboard-write'
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%';

        frame.onLoad.listen((_) => _postToCanvas('soul.canvas.parent_ready'));
        _iframe = frame;
        return frame;
      },
    );
    _messageSubscription = html.window.onMessage.listen(_handleCanvasMessage);
  }

  @override
  void dispose() {
    widget.controller?.unbindCommandSender(_sendCommand);
    unawaited(_messageSubscription?.cancel());
    _messageSubscription = null;
    _iframe = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ArchitectureCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.unbindCommandSender(_sendCommand);
    widget.controller?.bindCommandSender(_sendCommand);
  }

  static String _canvasUrl() {
    final baseHref = html.document.querySelector('base')?.getAttribute('href') ?? '/';
    final canvasPath = Uri.parse(baseHref).resolve('canvas/index.html?embed=1').toString();
    return Uri.base.resolve(canvasPath).toString();
  }

  void _handleCanvasMessage(html.MessageEvent event) {
    final frameWindow = _iframe?.contentWindow;
    final rawData = event.data;
    if (frameWindow == null || event.source != frameWindow) return;
    if (event.origin != html.window.location.origin) return;
    if (rawData is! String) return;

    final Object? data;
    try {
      data = jsonDecode(rawData);
    } catch (_) {
      return;
    }
    if (data is! Map) return;
    if (data['protocolVersion'] != _protocolVersion || data['source'] != _canvasSource) return;

    switch (data['type']) {
      case 'soul.canvas.ready':
        final payload = data['payload'];
        widget.controller?.markReady(
          totalOperations: payload is Map ? payload['operationCount'] as int? ?? 0 : 0,
        );
        _postToCanvas('soul.canvas.parent_ready');
        break;
      case 'soul.canvas.state':
        final payload = data['payload'];
        if (payload is Map) {
          widget.controller?.updateState(
            status: payload['status'] as String? ?? 'unknown',
            appliedOperations: payload['appliedOperations'] as int? ?? 0,
            totalOperations: payload['totalOperations'] as int? ?? 0,
          );
        }
        break;
      case 'soul.canvas.ack':
        break;
      case 'soul.canvas.rejected':
        final payload = data['payload'];
        widget.controller?.reject(payload is Map ? payload['reason'] as String? ?? 'rejected' : 'rejected');
        break;
      default:
        _postToCanvas('soul.canvas.rejected', {'reason': 'unsupported_type', 'type': data['type']});
    }
  }

  void _sendCommand(String command) {
    _postToCanvas('soul.canvas.command', {'command': command});
  }

  void _postToCanvas(String type, [Map<String, Object?> payload = const {}]) {
    final target = _iframe?.contentWindow;
    if (target == null) return;
    target.postMessage(
      jsonEncode({
        'protocolVersion': _protocolVersion,
        'source': _flutterSource,
        'type': type,
        'payload': payload,
      }),
      html.window.location.origin,
    );
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
