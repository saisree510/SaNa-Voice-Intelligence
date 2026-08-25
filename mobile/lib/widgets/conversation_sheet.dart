import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation_turn.dart';

/// Scrollable unified conversation sheet for voice + text turns.
class ConversationSheet extends StatefulWidget {
  const ConversationSheet({
    super.key,
    required this.turns,
    this.onViewCanvas,
    this.showCanvasActivityCards = false,
  });

  final List<ConversationTurn> turns;
  final VoidCallback? onViewCanvas;
  final bool showCanvasActivityCards;

  @override
  State<ConversationSheet> createState() => _ConversationSheetState();
}

class _ConversationSheetState extends State<ConversationSheet> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant ConversationSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasChanged = widget.turns.length != oldWidget.turns.length ||
        (widget.turns.isNotEmpty && oldWidget.turns.isNotEmpty && widget.turns.last != oldWidget.turns.last);
    if (hasChanged && _shouldAutoScroll(oldWidget)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        unawaited(
          _controller.animateTo(
            _controller.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          ),
        );
      });
    }
  }

  bool _shouldAutoScroll(ConversationSheet oldWidget) {
    if (oldWidget.turns.isEmpty || !_controller.hasClients) return true;
    final distanceFromBottom = _controller.position.maxScrollExtent - _controller.offset;
    return distanceFromBottom < 96;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      physics: const BouncingScrollPhysics(),
      itemCount: widget.turns.length,
      itemBuilder: (context, index) {
        final turn = widget.turns[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: turn.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              ConversationTurnBubble(turn: turn),
              if (widget.showCanvasActivityCards && _shouldShowCanvasActivity(turn)) ...[
                const SizedBox(height: 8),
                CanvasActivityCard(onViewCanvas: widget.onViewCanvas),
              ],
            ],
          ),
        );
      },
    );
  }

  bool _shouldShowCanvasActivity(ConversationTurn turn) {
    if (turn.isUser || !turn.isFinal) return false;
    final text = turn.text.toLowerCase();
    return text.contains('architecture') ||
        text.contains('blueprint') ||
        text.contains('canvas') ||
        text.contains('plan') ||
        text.contains('approve') ||
        text.contains('generated the files') ||
        text.contains('ready for download');
  }
}

class ConversationTurnBubble extends StatelessWidget {
  const ConversationTurnBubble({super.key, required this.turn});

  final ConversationTurn turn;

  @override
  Widget build(BuildContext context) {
    final text = turn.text.trim();
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final bool isUser = turn.isUser;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final colorScheme = Theme.of(context).colorScheme;
    final background = isUser ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final foreground = isUser ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;
    final labelColor = isUser ? foreground.withValues(alpha: 0.8) : colorScheme.outline;
    final displayText = turn.isFinal ? text : '$text …';
    final sourceLabel = turn.source == ConversationSource.text ? 'Typed' : 'Voice';
    final roleLabel = isUser ? 'You' : 'Soul';

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  '$roleLabel · $sourceLabel${turn.isFinal ? '' : ' · listening'}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: labelColor),
                ),
                const SizedBox(height: 4),
                Text(
                  displayText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontStyle: turn.isFinal ? FontStyle.normal : FontStyle.italic,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CanvasActivityCard extends StatelessWidget {
  const CanvasActivityCard({super.key, this.onViewCanvas});

  final VoidCallback? onViewCanvas;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.28)),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.account_tree_rounded,
                      color: colorScheme.primary,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Architecture updated',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Open the live canvas for the visual plan.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: onViewCanvas,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('View on canvas'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
