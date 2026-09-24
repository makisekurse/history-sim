import 'package:flutter/material.dart';

import '../../models/annotation.dart';
import '../../models/chapter_node.dart';

/// 人物志：把每一幕 `<cast>` 里出现过的人物累积起来。
///
/// 数据完全来自模型输出，应用不维护任何预设人物表。
class CastScreen extends StatelessWidget {
  final List<ChapterNode> history;

  const CastScreen({super.key, required this.history});

  /// 按姓名合并，后出现的信息覆盖先出现的（不覆盖成空）。
  List<CastEntry> _aggregate() {
    final map = <String, CastEntry>{};
    for (final node in history) {
      for (final e in node.cast) {
        final key = e.name.trim();
        if (key.isEmpty) continue;
        final prev = map[key];
        map[key] = prev == null ? e : prev.merge(e);
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _aggregate();

    return Scaffold(
      appBar: AppBar(title: const Text('人物志')),
      body: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  '还没有人物记录。\n推演几幕后，出场人物会自动积累到这里。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: entries.length,
              separatorBuilder: (_, __) => Divider(
                height: 24,
                color: theme.dividerColor,
              ),
              itemBuilder: (_, i) {
                final e = entries[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      e.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (e.role.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        e.role,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                    if (e.stance.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '立场：${e.stance}',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.55,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }
}
