import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/architecture_service.dart';
import '../ui/sana_theme.dart';
import 'architecture_canvas_controller.dart';
import 'architecture_canvas_view.dart';

class ArchitectureCanvasPanel extends StatefulWidget {
  const ArchitectureCanvasPanel({
    super.key,
    this.onCollapse,
    this.onFullscreen,
    this.isFullscreen = false,
  });

  final VoidCallback? onCollapse;
  final VoidCallback? onFullscreen;
  final bool isFullscreen;

  @override
  State<ArchitectureCanvasPanel> createState() => _ArchitectureCanvasPanelState();
}

class _ArchitectureCanvasPanelState extends State<ArchitectureCanvasPanel> {
  late final ArchitectureCanvasController _controller = ArchitectureCanvasController();
  ArchitectureCanvasData? _loadedArchitecture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<ArchitectureService>().fetchLatestArchitecture());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final architecture = context.watch<ArchitectureService>().latestArchitecture;
    if (architecture == null || identical(architecture, _loadedArchitecture)) return;
    _loadedArchitecture = architecture;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.loadArchitecture(architecture);
    });
  }

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
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          child: Column(
            children: [
              _CanvasHeader(
                controller: _controller,
                onCollapse: widget.onCollapse,
                onFullscreen: widget.onFullscreen,
                isFullscreen: widget.isFullscreen,
              ),
              Expanded(
                child: ArchitectureCanvasView(controller: _controller),
              ),
            ],
          ),
        ),
      );
}

class _CanvasHeader extends StatelessWidget {
  const _CanvasHeader({
    required this.controller,
    required this.isFullscreen,
    this.onCollapse,
    this.onFullscreen,
  });

  final ArchitectureCanvasController controller;
  final VoidCallback? onCollapse;
  final VoidCallback? onFullscreen;
  final bool isFullscreen;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: SanaColors.pureWhite,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _CanvasStatusChip(controller: controller),
                ),
              ),
              const SizedBox(width: 10),
              _CanvasCommandBar(
                controller: controller,
                onCollapse: onCollapse,
                onFullscreen: onFullscreen,
                isFullscreen: isFullscreen,
              ),
            ],
          ),
        ),
      );
}

class _CanvasStatusChip extends StatelessWidget {
  const _CanvasStatusChip({required this.controller});

  final ArchitectureCanvasController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final progress =
              controller.totalOperations > 0 ? '${controller.appliedOperations}/${controller.totalOperations}' : '';
          final statusText = progress.isEmpty ? controller.status : '${controller.status} $progress';
          final label = controller.lastError != null
              ? 'Canvas needs attention'
              : controller.isReady
                  ? 'Canvas $statusText'
                  : 'Canvas loading';

          return DecoratedBox(
            decoration: BoxDecoration(
              color: SanaColors.surface.withValues(alpha: 0.84),
              border: Border.all(color: SanaColors.outline),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: controller.lastError != null ? SanaColors.danger : SanaColors.fgSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          );
        },
      );
}

class _CanvasCommandBar extends StatelessWidget {
  const _CanvasCommandBar({
    required this.controller,
    required this.isFullscreen,
    this.onCollapse,
    this.onFullscreen,
  });

  final ArchitectureCanvasController controller;
  final VoidCallback? onCollapse;
  final VoidCallback? onFullscreen;
  final bool isFullscreen;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: SanaColors.surface.withValues(alpha: 0.88),
          border: Border.all(color: SanaColors.outline),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CanvasIconButton(
                tooltip: 'Fit diagram',
                icon: Icons.fit_screen_rounded,
                onPressed: () => controller.sendCommand('fit'),
              ),
              _CanvasIconButton(
                tooltip: 'Replay',
                icon: Icons.replay_rounded,
                onPressed: () => controller.sendCommand('replay'),
              ),
              _CanvasIconButton(
                tooltip: 'Pause',
                icon: Icons.pause_rounded,
                onPressed: () => controller.sendCommand('pause'),
              ),
              _CanvasIconButton(
                tooltip: 'Play',
                icon: Icons.play_arrow_rounded,
                onPressed: () => controller.sendCommand('play'),
              ),
              if (onCollapse != null)
                _CanvasIconButton(
                  tooltip: 'Collapse canvas',
                  icon: Icons.keyboard_double_arrow_right_rounded,
                  onPressed: onCollapse,
                ),
              if (onFullscreen != null)
                _CanvasIconButton(
                  tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen canvas',
                  icon: isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  onPressed: onFullscreen,
                ),
            ],
          ),
        ),
      );
}

class _CanvasIconButton extends StatelessWidget {
  const _CanvasIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: IconButton(
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 19),
          color: SanaColors.fgSecondary,
          onPressed: onPressed,
        ),
      );
}
