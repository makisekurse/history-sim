import 'package:flutter/material.dart';

import '../../models/save_slot.dart';

/// 「继续」标签页 —— 我正在经历什么。
///
/// 首屏是「继续你的故事」大卡片（最近打开的那一局），
/// 下面才是全部推演列表。
class ContinueTab extends StatelessWidget {
  final List<SaveSlot> slots;
  final String? activeSlotId;
  final ValueChanged<SaveSlot> onOpen;
  final ValueChanged<SaveSlot> onMenu;
  final VoidCallback onNewSession;

  const ContinueTab({
    super.key,
    required this.slots,
    required this.activeSlotId,
    required this.onOpen,
    required this.onMenu,
    required this.onNewSession,
  });

  SaveSlot? get _active {
    if (slots.isEmpty) return null;
    if (activeSlotId != null) {
      for (final s in slots) {
        if (s.id == activeSlotId) return s;
      }
    }
    return slots.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _active;

    if (slots.isEmpty) {
      return _empty(theme);
    }

    final others = slots.where((s) => s.id != active?.id).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: <Widget>[
        Text(
          '继续你的故事',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 14),
        if (active != null) _activeCard(theme, active),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onNewSession,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('开始一段新的推演'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              side: BorderSide(color: theme.dividerColor),
            ),
          ),
        ),
        if (others.isNotEmpty) ...<Widget>[
          const SizedBox(height: 28),
          Text(
            '最近推演',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          for (final s in others) _slotRow(theme, s),
        ],
      ],
    );
  }

  Widget _activeCard(ThemeData theme, SaveSlot slot) {
    final ws = slot.worldState;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpen(slot),
      onLongPress: () => onMenu(slot),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.45),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              slot.worldBook.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              <String>[
                '第 ${slot.chapterCount} 幕',
                // 有多条世界线时，把当前所在的那条也标出来
                if (slot.lines.length > 1) slot.activeLine.name,
              ].join(' · '),
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
            if (ws.inlineSummary.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                ws.inlineSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text(
                  '继续进入',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotRow(ThemeData theme, SaveSlot slot) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onOpen(slot),
          onLongPress: () => onMenu(slot),
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
                Text(
                  slot.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  slot.summaryLine,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _empty(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '还没有进行中的推演',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '先到「世界」里准备一段设定，\n然后就能进入它。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.8,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onNewSession,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('开始一段新的推演'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                ),
              ),
            ],
          ),
        ),
      );
}
