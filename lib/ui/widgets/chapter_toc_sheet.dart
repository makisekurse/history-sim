import 'package:flutter/material.dart';

import '../../models/chapter_node.dart';
import '../../services/text_layout.dart';
import '../themes/app_theme.dart';

/// 幕次目录底栏弹层。
///
/// 展示所有幕次、日期、所做抉择及正文首句缩略，支持点击快速跳转。
class ChapterTocSheet extends StatelessWidget {
  final List<ChapterNode> history;
  final ValueChanged<int> onSelectChapter;

  const ChapterTocSheet({
    super.key,
    required this.history,
    required this.onSelectChapter,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ChapterNode> history,
    required ValueChanged<int> onSelectChapter,
  }) {
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ChapterTocSheet(
        history: history,
        onSelectChapter: onSelectChapter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.readingOf(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(
                children: <Widget>[
                  Text(
                    '幕次目录',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '共 ${history.length} 幕',
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: history.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '尚无推演幕次',
                          style: TextStyle(color: palette.muted, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: history.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                        color: palette.rule.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (ctx, i) {
                        final node = history[i];
                        final paras = TextLayout.paragraphs(node.content);
                        final preview = paras.isNotEmpty ? paras.first : '';
                        final shortPreview = preview.length > 45
                            ? '${preview.substring(0, 45)}…'
                            : preview;

                        return InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            onSelectChapter(i);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 11,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.accent
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '第 ${node.chapterIndex} 幕',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: palette.accent,
                                        ),
                                      ),
                                    ),
                                    if (node.date.isNotEmpty) ...<Widget>[
                                      const SizedBox(width: 8),
                                      Text(
                                        node.date,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: palette.muted,
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: palette.muted,
                                    ),
                                  ],
                                ),
                                if (node.playerAction != null &&
                                    node.playerAction!.trim().isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 5),
                                  Text(
                                    '【抉择】${node.playerAction!.trim()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: palette.accent.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ],
                                if (shortPreview.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Text(
                                    shortPreview,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: palette.ink.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
