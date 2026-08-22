import 'package:flutter/material.dart';

import '../ui/sana_theme.dart';
import 'architecture_canvas_view.dart';

class ArchitectureCanvasPanel extends StatelessWidget {
  const ArchitectureCanvasPanel({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: SanaColors.pureWhite,
          border: Border.all(color: SanaColors.outline),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: SanaColors.lavenderDeep.withValues(alpha: 0.10),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(22)),
          child: ArchitectureCanvasView(),
        ),
      );
}
