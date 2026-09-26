import 'package:flutter/material.dart';

import '../../models/annotation.dart';

/// 词条与人物志的底部弹出层。
///
/// 数据全部来自模型每幕随文附带的 `<glossary>` / `<cast>` 结构块，
/// 应用本身不维护任何本地词表 —— 换任何题材的世界书都能直接用。
class AnnotationSheet {
  AnnotationSheet._();

  static Future<void> showGlossary(
    BuildContext context,
    List<GlossaryEntry> entries,
  ) {
    return _show(
      context,
      title: '本幕词条',
      emptyHint: '本幕没有新词条。',
      children: entries
          .map(
            (e) => _Row(title: e.term, body: e.explanation),
          )
          .toList(),
    );
  }

  static Future<void> showCast(
    BuildContext context,
    List<CastEntry> entries,
  ) {
    return _show(
      context,
      title: '本幕人物',
      emptyHint: '本幕没有新人物。',
      children: entries
          .map(
            (e) => _Row(
              title: e.name,
              body: <String>[
                if (e.role.isNotEmpty) e.role,
                if (e.stance.isNotEmpty) '立场：${e.stance}',
              ].join(' · '),
            ),
          )
          .toList(),
    );
  }

  static Future<void> _show(
    BuildContext context, {
    required String title,
    required String emptyHint,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: children.isEmpty
                      ? Text(
                          emptyHint,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          children: children,
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

class _Row extends StatelessWidget {
  final String title;
  final String body;

  const _Row({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          if (body.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
