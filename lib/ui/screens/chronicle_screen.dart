import 'package:flutter/material.dart';

import '../../models/chapter_node.dart';

/// 编年史时间线：把每一幕的日期、决断、结果串成大事记。
class ChronicleScreen extends StatelessWidget {
  final List<ChapterNode> history;

  const ChronicleScreen({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('编年史')),
      body: history.isEmpty
          ? Center(
              child: Text(
                '还没有推演记录。',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: history.length,
              itemBuilder: (_, i) {
                final node = history[i];
                final excerpt = node.content.length > 90
                    ? '${node.content.substring(0, 90)}…'
                    : node.content;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: 24,
                        child: Column(
                          children: <Widget>[
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(top: 5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Expanded(
                              child: Container(
                                width: 1,
                                color: theme.dividerColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                node.date.trim().isEmpty
                                    ? '第 ${node.chapterIndex} 幕'
                                    : node.date.trim(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              if (node.playerAction != null &&
                                  node.playerAction!.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '决定：${node.playerAction!.trim()}',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.55,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                              if (excerpt.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  excerpt.trim(),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.6,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
