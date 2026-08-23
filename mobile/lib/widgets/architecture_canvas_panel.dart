import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/architecture_service.dart';
import '../services/build_projects_service.dart';
import '../screens/home_shell.dart';
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
  Widget build(BuildContext context) {
    final activeArch = context.watch<ArchitectureService>().latestArchitecture;
    final isDraft = activeArch != null && activeArch.blueprint['status'] == 'draft';
    final isApproved = activeArch != null && activeArch.projectId != null;

    return ColoredBox(
      color: SanaColors.pureWhite,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Row(
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    _CanvasStatusChip(controller: controller),
                    if (isDraft) ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () => _approveAndBuild(context, activeArch),
                        icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: Size.zero,
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        label: const Text('Approve & Build'),
                      ),
                    ] else if (isApproved) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => _navigateToProject(context, activeArch.projectId!),
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: Size.zero,
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        label: const Text('Open Build'),
                      ),
                    ],
                  ],
                ),
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

  void _navigateToProject(BuildContext context, String projectId) {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(const SnackBar(content: Text('Opening project details...')));
    unawaited(context.read<BuildProjectsService>().fetchProject(projectId).then((detail) {
      if (detail != null && context.mounted) {
        unawaited(Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProjectDetailScreen(project: detail),
          ),
        ));
      } else {
        scaffold.showSnackBar(const SnackBar(content: Text('Could not load project details.')));
      }
    }));
  }

  Future<void> _approveAndBuild(BuildContext context, ArchitectureCanvasData architecture) async {
    final spec = StringBuffer();
    spec.writeln('Build an application based on the approved architecture blueprint:');
    spec.writeln('Title: ${architecture.title}');
    spec.writeln('Components:');
    final components = architecture.blueprint['components'] as List? ?? const [];
    for (var comp in components) {
      final name = comp['name'] ?? 'Untitled';
      final type = comp['type'] ?? 'Component';
      final tech = comp['technology'] ?? 'Unspecified';
      spec.writeln('- Name: $name (Type: $type, Technology: $tech)');
    }
    spec.writeln('Connections:');
    final connections = architecture.blueprint['connections'] as List? ?? const [];
    for (var conn in connections) {
      final source = conn['source_id'] ?? '';
      final target = conn['target_id'] ?? '';
      final protocol = conn['protocol'] ?? 'HTTP';
      spec.writeln('- Connection from $source to $target using protocol $protocol');
    }

    final scaffold = ScaffoldMessenger.of(context);
    final buildService = Provider.of<BuildProjectsService>(context, listen: false);
    final archService = Provider.of<ArchitectureService>(context, listen: false);

    scaffold.showSnackBar(const SnackBar(content: Text('Generating build project plan...')));
    final project = await buildService.createProject(architecture.title, spec.toString());
    if (project == null) {
      scaffold.showSnackBar(SnackBar(content: Text(buildService.errorMessage ?? 'Failed to create build project')));
      return;
    }

    scaffold.showSnackBar(const SnackBar(content: Text('Approving and locking architecture blueprint...')));
    final success = await archService.approveArchitectureBlueprint(project.projectId);
    if (!success) {
      scaffold
          .showSnackBar(SnackBar(content: Text(archService.errorMessage ?? 'Failed to lock architecture blueprint')));
      return;
    }

    scaffold.showSnackBar(const SnackBar(content: Text('Starting build execution...')));
    final runStarted = await buildService.approveProject(project.projectId);
    if (!runStarted) {
      scaffold.showSnackBar(SnackBar(content: Text(buildService.errorMessage ?? 'Failed to start build execution')));
      return;
    }

    scaffold.showSnackBar(const SnackBar(content: Text('Build successfully started! Redirecting to build details...')));
    _navigateToProject(context, project.projectId);
  }
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
