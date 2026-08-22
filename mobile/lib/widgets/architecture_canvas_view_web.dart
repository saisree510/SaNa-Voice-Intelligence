// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

class ArchitectureCanvasView extends StatefulWidget {
  const ArchitectureCanvasView({super.key});

  @override
  State<ArchitectureCanvasView> createState() => _ArchitectureCanvasViewState();
}

class _ArchitectureCanvasViewState extends State<ArchitectureCanvasView> {
  static const String _viewType = 'soul-architecture-canvas';
  static bool _registered = false;

  @override
  void initState() {
    super.initState();
    if (!_registered) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) => html.IFrameElement()
          ..src = _canvasUrl()
          ..title = 'Soul Architecture Blueprint'
          ..allow = 'clipboard-read; clipboard-write'
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%',
      );
      _registered = true;
    }
  }

  static String _canvasUrl() {
    final baseHref = html.document.querySelector('base')?.getAttribute('href') ?? '/';
    final canvasPath = Uri.parse(baseHref).resolve('canvas/index.html?embed=1').toString();
    return Uri.base.resolve(canvasPath).toString();
  }

  @override
  Widget build(BuildContext context) => const HtmlElementView(viewType: _viewType);
}
