import 'package:flutter/material.dart';

import '../../models/world_book.dart';

/// 「世界」标签页 —— 我创造什么。
///
/// 列表是用户自己建的/导入的世界书；应用不内置任何剧本。
class WorldsTab extends StatelessWidget {
  final List<WorldBook> books;
  final VoidCallback onCreate;
  final VoidCallback onImport;
  final ValueChanged<WorldBook> onEdit;
  final ValueChanged<WorldBook> onMenu;
  final ValueChanged<WorldBook> onStartSession;

  const WorldsTab({
    super.key,
    required this.books,
    required this.onCreate,
    required this.onImport,
    required this.onEdit,
    required this.onMenu,
    required this.onStartSession,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '我的世界',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '一个世界书 = 一段设定。你演谁、身处什么时代、用什么文风，全在这里决定。',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.7,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onImport,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('导入'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onCreate,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('创建世界'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (books.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    '还没有世界',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '点上面的「创建世界」写一个，\n或从别处导入一段提示词。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.8,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            sliver: SliverList.builder(
              itemCount: books.length,
              itemBuilder: (_, i) {
                final b = books[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onEdit(b),
                    onLongPress: () => onMenu(b),
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (!b.isPlayable)
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 17,
                                  color: theme.colorScheme.primary,
                                ),
                            ],
                          ),
                          if (b.era.trim().isNotEmpty) ...<Widget>[
                            const SizedBox(height: 5),
                            Text(
                              b.era,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                          if (b.playerRole.trim().isNotEmpty) ...<Widget>[
                            const SizedBox(height: 5),
                            Text(
                              '扮演：${b.playerRole}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: b.isPlayable
                                  ? () => onStartSession(b)
                                  : null,
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                side: BorderSide(color: theme.dividerColor),
                              ),
                              child: Text(
                                b.isPlayable ? '进入这个世界' : '还缺必填项，点开补全',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
