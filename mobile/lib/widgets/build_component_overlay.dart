import 'package:flutter/material.dart';

import '../services/build_canvas_integration_service.dart';
import '../ui/sana_theme.dart';

/// Shows real-time build progress for each architecture component
class BuildComponentOverlay extends StatelessWidget {
  const BuildComponentOverlay({
    super.key,
    required this.componentStatuses,
    required this.isBuilding,
  });

  final Map<String, BuildComponentStatus> componentStatuses;
  final bool isBuilding;

  @override
  Widget build(BuildContext context) {
    if (componentStatuses.isEmpty) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: SanaColors.darkGray.withOpacity(0.95),
        border: Border.all(color: SanaColors.gray, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isBuilding ? Icons.hourglass_bottom_rounded : Icons.check_circle_outline,
                size: 18,
                color: isBuilding ? Colors.amber : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                isBuilding ? 'Building components...' : 'Build complete',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isBuilding ? Colors.amber : Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: componentStatuses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final status = componentStatuses.values.elementAt(index);
                return _ComponentStatusCard(status: status);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ComponentStatusCard extends StatelessWidget {
  const _ComponentStatusCard({required this.status});

  final BuildComponentStatus status;

  Color _getStatusColor() => switch (status.status) {
        'pending' => Colors.grey,
        'building' => Colors.blue,
        'completed' => Colors.green,
        'failed' => Colors.red,
        _ => Colors.grey,
      };

  IconData _getStatusIcon() => switch (status.status) {
        'pending' => Icons.schedule_outlined,
        'building' => Icons.sync_rounded,
        'completed' => Icons.check_circle_outline,
        'failed' => Icons.error_outline,
        _ => Icons.help_outline,
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = _getStatusColor();
    final progress = status.filesGenerated > 0 ? status.filesGenerated / 10.0 : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: SanaColors.nearBlack.withOpacity(0.5),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getStatusIcon(), size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.componentName,
                  style: textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                status.status.toUpperCase(),
                style: textTheme.labelSmall?.copyWith(
                  color: color.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (status.filesGenerated > 0 || status.testsRun > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${status.filesGenerated} file(s)'
                    '${status.testsRun > 0 ? ' • ${status.testsRun} test(s)' : ''}',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey[400],
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (status.errors.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                status.errors.first,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.red[300],
                  fontSize: 10,
                ),
              ),
            ),
          ],
          if (status.isActive) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Colors.grey[700],
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
