import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation_turn.dart';

/// Scrollable unified conversation sheet for voice + text turns.
class ConversationSheet extends StatefulWidget {
  const ConversationSheet({super.key, required this.turns});

  final List<ConversationTurn> turns;

  @override
  State<ConversationSheet> createState() => _ConversationSheetState();
}

class _ConversationSheetState extends State<ConversationSheet> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant ConversationSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.turns.length != oldWidget.turns.length ||
        (widget.turns.isNotEmpty &&
            oldWidget.turns.isNotEmpty &&
            widget.turns.last != oldWidget.turns.last)) {
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
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ConversationTurnBubble(turn: widget.turns[index]),
      ),
    );
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
    final roleLabel = isUser ? 'You' : 'Sana';

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
