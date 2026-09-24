import 'package:flutter/material.dart';

/// 自由意志行动输入栏
class CustomActionBar extends StatefulWidget {
  final Function(String action) onSend;
  final bool isEnabled;

  const CustomActionBar({
    super.key,
    required this.onSend,
    this.isEnabled = true,
  });

  @override
  State<CustomActionBar> createState() => _CustomActionBarState();
}

class _CustomActionBarState extends State<CustomActionBar> {
  final TextEditingController _controller = TextEditingController();

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && widget.isEnabled) {
      widget.onSend(text);
      _controller.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.7),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: widget.isEnabled,
              maxLines: 3,
              minLines: 1,
              style: TextStyle(
                fontSize: 14.5,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: "或者，由你决断行止（自由输入任何行动意图）...",
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: theme.colorScheme.onSurface.withOpacity(0.45),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (_) => _handleSubmit(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: widget.isEnabled ? _handleSubmit : null,
            icon: Icon(
              Icons.send_rounded,
              size: 20,
              color: widget.isEnabled ? primaryColor : Colors.grey,
            ),
            splashRadius: 22,
          ),
        ],
      ),
    );
  }
}
