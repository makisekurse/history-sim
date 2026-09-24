import 'package:flutter/material.dart';

/// 自由意志输入栏。
///
/// 生成中时变成「中止」按钮 —— 旧版生成期间只能干等，没有任何退路。
class FreeInputBar extends StatefulWidget {
  final bool busy;
  final ValueChanged<String> onSend;
  final VoidCallback onCancel;

  const FreeInputBar({
    super.key,
    required this.busy,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<FreeInputBar> createState() => _FreeInputBarState();
}

class _FreeInputBarState extends State<FreeInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _focusNode.unfocus();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    if (widget.busy) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: widget.onCancel,
          icon: const Icon(Icons.stop_rounded, size: 18),
          label: const Text('中止本次推演'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: theme.dividerColor),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: '也可以自己写一句行动，例如「密电刘文辉，陈明大势」',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _submit,
            icon: const Icon(Icons.arrow_upward_rounded),
            style: IconButton.styleFrom(
              backgroundColor: primary.withValues(alpha: 0.12),
              foregroundColor: primary,
            ),
            tooltip: '执行',
          ),
        ],
      ),
    );
  }
}
