import 'package:flutter/material.dart';

import 'architecture_canvas_controller.dart';

class ArchitectureCanvasView extends StatelessWidget {
  const ArchitectureCanvasView({super.key, this.controller});

  final ArchitectureCanvasController? controller;

  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Architecture canvas is available in Soul Web.'),
      );
}
