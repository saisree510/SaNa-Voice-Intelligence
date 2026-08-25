import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/build_stream_service.dart';
import '../ui/sana_theme.dart';

class BuildStreamViewer extends StatelessWidget {
  const BuildStreamViewer({
    super.key,
    required this.events,
    required this.isStreaming,
    this.onClose,
  });

  final List<BuildStreamEvent> events;
  final bool isStreaming;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty && !isStreaming) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: SanaColors.surfaceElevated,
        border: Border.all(color: SanaColors.outline, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isStreaming ? 'Building...' : 'Build Complete',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isStreaming ? Colors.amber : Colors.green,
                        ),
                  ),
                ),
                if (!isStreaming && onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: events.length,
              itemBuilder: (context, index) => _BuildEventTile(
                event: events[index],
                index: index,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildEventTile extends StatelessWidget {
  const _BuildEventTile({
    required this.event,
    required this.index,
  });

  final BuildStreamEvent event;
  final int index;

  Color _getEventColor() => switch (event.eventType) {
        'start' => Colors.blue,
        'complete' => Colors.green,
        'error' => Colors.red,
        'file_create' || 'file_edit' || 'file_delete' => Colors.cyan,
        'tool_start' || 'tool_complete' => Colors.purple,
        'test_result' => Colors.orange,
        _ => Colors.grey,
      };

  IconData _getEventIcon() => switch (event.eventType) {
        'start' => Icons.play_circle_outline,
        'complete' => Icons.check_circle_outline,
        'error' => Icons.error_outline,
        'file_create' => Icons.note_add_outlined,
        'file_edit' => Icons.edit_note_outlined,
        'file_delete' => Icons.delete_outline,
        'tool_start' => Icons.miscellaneous_services_outlined,
        'tool_complete' => Icons.done_all_outlined,
        'test_result' => Icons.assessment_outlined,
        _ => Icons.info_outline,
      };

  String _formatTime(DateTime? timestamp) {
    if (timestamp == null) return '';
    return DateFormat('HH:mm:ss').format(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    final color = _getEventColor();
    final time = _formatTime(event.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SanaColors.surface.withValues(alpha: 0.7),
          border: Border(
            left: BorderSide(
              color: color,
              width: 3,
            ),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getEventIcon(),
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event.eventType.replaceAll('_', ' ').toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (time.isNotEmpty)
                    Text(
                      time,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: SanaColors.fgMuted,
                          ),
                    ),
                ],
              ),
              if (event.message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    event.message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SanaColors.fgSecondary,
                        ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (event.generatedFiles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Generated: ${event.generatedFiles.length} file(s)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green[400],
                          fontSize: 11,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
