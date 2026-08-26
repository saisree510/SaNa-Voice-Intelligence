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
    this.architectureId,
    this.preferredProjectId,
    this.autoLoadLatest = false,
    this.requireExplicitArchitecture = false,
    this.isFullscreen = false,
    this.isReadOnly = false,
  });

  final VoidCallback? onCollapse;
  final VoidCallback? onFullscreen;
  final String? architectureId;
  final String? preferredProjectId;
  final bool autoLoadLatest;
  final bool requireExplicitArchitecture;
  final bool isFullscreen;
  final bool isReadOnly;

  @override
  State<ArchitectureCanvasPanel> createState() => _ArchitectureCanvasPanelState();
}

class _ArchitectureCanvasPanelState extends State<ArchitectureCanvasPanel> {
  late final ArchitectureCanvasController _controller = ArchitectureCanvasController();
  String? _loadedArchitectureKey;

  @override
  void initState() {
    super.initState();
    _controller.setReadOnly(widget.isReadOnly);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadRequestedArchitecture();
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
    if (!_canDisplayArchitecture(architecture)) return;
    final architectureKey = architecture == null
        ? null
        : '${architecture.architectureId}:${architecture.operations.length}:${architecture.componentCount}:${architecture.connectionCount}';
    if (architecture == null || architectureKey == _loadedArchitectureKey) return;
    _loadedArchitectureKey = architectureKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.loadArchitecture(architecture);
    });
  }

  @override
  void didUpdateWidget(ArchitectureCanvasPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isReadOnly != widget.isReadOnly) {
      _controller.setReadOnly(widget.isReadOnly);
    }
    if (oldWidget.architectureId != widget.architectureId ||
        oldWidget.preferredProjectId != widget.preferredProjectId ||
        oldWidget.autoLoadLatest != widget.autoLoadLatest) {
      _loadedArchitectureKey = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadRequestedArchitecture();
      });
    }
  }

  void _loadRequestedArchitecture() {
    final service = context.read<ArchitectureService>();
    final architectureId = widget.architectureId;
    if (architectureId != null && architectureId.isNotEmpty) {
      unawaited(service.fetchArchitectureById(architectureId));
    } else if (widget.autoLoadLatest) {
      unawaited(service.fetchLatestArchitecture(preferredProjectId: widget.preferredProjectId));
    }
  }

  bool _canDisplayArchitecture(ArchitectureCanvasData? architecture) {
    if (architecture == null) return false;
    final requestedArchitectureId = widget.architectureId;
    if (requestedArchitectureId != null && requestedArchitectureId.isNotEmpty) {
      return architecture.architectureId == requestedArchitectureId;
    }
    if (widget.requireExplicitArchitecture) return false;
    final preferredProjectId = widget.preferredProjectId;
    if (preferredProjectId != null && preferredProjectId.isNotEmpty) {
      return architecture.projectId == preferredProjectId;
    }
    return widget.autoLoadLatest;
  }

  @override
  Widget build(BuildContext context) {
    final architecture = context.watch<ArchitectureService>().latestArchitecture;
    final canDisplayArchitecture = _canDisplayArchitecture(architecture);

    return DecoratedBox(
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
              child: canDisplayArchitecture
                  ? ArchitectureCanvasView(controller: _controller)
                  : _EmptyCanvasState(
                      isLoading: context.watch<ArchitectureService>().isLoading,
                      errorMessage: context.watch<ArchitectureService>().errorMessage,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCanvasState extends StatelessWidget {
  const _EmptyCanvasState({
    required this.isLoading,
    this.errorMessage,
  });

  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final message = errorMessage ??
        (isLoading
            ? 'Loading the active architecture...'
            : 'No live architecture is linked to this conversation yet. Ask Soul to design the architecture first.');

    return CustomPaint(
      painter: const _DottedWorkspacePainter(),
      child: SizedBox.expand(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading) ...[
                    const CircularProgressIndicator(color: SanaColors.lavender),
                    const SizedBox(height: 18),
                  ] else ...[
                    const Icon(Icons.account_tree_outlined, color: SanaColors.lavender, size: 36),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: SanaColors.fgSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DottedWorkspacePainter extends CustomPainter {
  const _DottedWorkspacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SanaColors.lavenderDeep.withValues(alpha: 0.17);
    for (var x = 12.0; x < size.width; x += 24) {
      for (var y = 12.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedWorkspacePainter oldDelegate) => false;
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
