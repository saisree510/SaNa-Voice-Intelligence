// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/architecture_service.dart';
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
    widget.controller?.bindMessageSender(_sendMessage);
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
    widget.controller?.unbindMessageSender(_sendMessage);
    unawaited(_messageSubscription?.cancel());
    _messageSubscription = null;
    _iframe = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ArchitectureCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.unbindMessageSender(_sendMessage);
    widget.controller?.bindMessageSender(_sendMessage);
  }

  static String _canvasUrl() {
    final baseHref = html.document.querySelector('base')?.getAttribute('href') ?? '/';
    final canvasPath = Uri.parse(baseHref).resolve('canvas/index.html?embed=1').toString();
    return Uri.base.resolve(canvasPath).toString();
  }

  void _handleCanvasMessage(html.MessageEvent event) {
    final rawData = event.data;
    if (_iframe == null) return;
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
        widget.controller?.resendArchitecture();
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
      case 'soul.canvas.node_moved':
        final payload = data['payload'];
        if (payload is Map) {
          final componentId = payload['componentId'] as String?;
          final x = payload['x'] as num?;
          final y = payload['y'] as num?;
          if (componentId != null && x != null && y != null) {
            unawaited(Provider.of<ArchitectureService>(context, listen: false).submitCanvasOperation('update_node', {
              'component_id': componentId,
              'metadata': {
                'position': {'x': x.toDouble(), 'y': y.toDouble()}
              }
            }));
          }
        }
        break;
      case 'soul.canvas.node_edited':
        final payload = data['payload'];
        if (payload is Map) {
          final componentId = payload['componentId'] as String?;
          final name = payload['name'] as String?;
          final technology = payload['technology'] as String?;
          if (componentId != null && name != null) {
            unawaited(Provider.of<ArchitectureService>(context, listen: false).submitCanvasOperation('update_node', {
              'component_id': componentId,
              'name': name,
              'technology': technology,
            }));
          }
        }
        break;
      case 'soul.canvas.node_deleted':
        final payload = data['payload'];
        if (payload is Map) {
          final componentId = payload['componentId'] as String?;
          final name = payload['name'] as String? ?? 'this component';
          if (componentId != null) {
            unawaited(showDialog<bool>(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                title: const Text('Delete Component'),
                content: Text('Are you sure you want to delete component "$name"? This cannot be undone.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ).then((confirmed) {
              if (confirmed == true) {
                unawaited(
                    Provider.of<ArchitectureService>(context, listen: false).submitCanvasOperation('delete_node', {
                  'component_id': componentId,
                }));
              } else {
                widget.controller?.resendArchitecture();
              }
            }));
          }
        }
        break;
      case 'soul.canvas.snapshot_ready':
        final payload = data['payload'];
        if (payload is Map) {
          final seq = payload['sequenceNumber'] as int?;
          final scene = payload['scene'] as Map<dynamic, dynamic>?;
          final service = Provider.of<ArchitectureService>(context, listen: false);
          final activeArch = service.latestArchitecture;
          if (seq != null && scene != null && activeArch != null) {
            unawaited(service.createCanvasSnapshot(
              activeArch.architectureId,
              seq,
              Map<String, dynamic>.from(scene),
            ));
          }
        }
        break;
      default:
        _postToCanvas('soul.canvas.rejected', {'reason': 'unsupported_type', 'type': data['type']});
    }
  }

  void _sendMessage(String type, Map<String, Object?> payload) {
    _postToCanvas(type, payload);
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
