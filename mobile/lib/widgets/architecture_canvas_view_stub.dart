import 'package:flutter/material.dart';

import 'architecture_canvas_controller.dart';

class ArchitectureCanvasView extends StatelessWidget {
  const ArchitectureCanvasView({
    super.key,
    this.controller,
    this.isInteractive = true,
    this.emptyState = false,
  });

  final ArchitectureCanvasController? controller;
  final bool isInteractive;
  final bool emptyState;

  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Architecture canvas is available in Soul Web.'),
      );
}
