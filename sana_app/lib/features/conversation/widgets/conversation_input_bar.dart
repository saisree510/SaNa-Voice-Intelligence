import 'package:flutter/material.dart';

/// The pill-shaped input bar pinned to the bottom of the conversation
/// screen: [+] · text field · mic · send. The send circle lights up
/// (primary color) only once there's text to send.
///
/// Only shown while idle — [ConversationScreen] swaps this out for
/// [VoiceActiveBar] while a call is active, rather than this widget
/// changing its own mic icon into a call/hang-up affordance.
class ConversationInputBar extends StatefulWidget {
  const ConversationInputBar({
    super.key,
    required this.controller,
    required this.modeTitle,
    required this.onSend,
    required this.onMic,
    required this.onMore,
  });

  final TextEditingController controller;
  final String modeTitle;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final VoidCallback onMore;

  @override
  State<ConversationInputBar> createState() => _ConversationInputBarState();
}

class _ConversationInputBarState extends State<ConversationInputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onMore,
            icon: const Icon(Icons.add_rounded),
            tooltip: 'More',
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => widget.onSend(),
              decoration: InputDecoration(
                hintText: 'Message ${widget.modeTitle}...',
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          IconButton(
            onPressed: widget.onMic,
            icon: const Icon(Icons.mic_none_rounded),
            tooltip: 'Talk to SANA',
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: _hasText ? theme.colorScheme.primary : theme.disabledColor.withValues(alpha: 0.25),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _hasText ? widget.onSend : null,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
