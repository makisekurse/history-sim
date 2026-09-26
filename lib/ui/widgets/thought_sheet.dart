import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../themes/app_theme.dart';

/// 推演思考（思维链）展示弹层与面板。
class ThoughtSheet extends StatelessWidget {
  final String title;
  final String thought;

  const ThoughtSheet({
    super.key,
    required this.title,
    required this.thought,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String thought,
  }) {
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ThoughtSheet(
        title: title,
        thought: thought,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.readingOf(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.psychology_outlined, size: 20, color: palette.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '推演思考 · $title',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: thought));
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('思考链内容已复制')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('复制'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.scrim,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.rule),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      thought.trim(),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.65,
                        color: palette.ink.withValues(alpha: 0.88),
                      ),
                    ),
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
