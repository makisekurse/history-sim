import 'package:flutter/material.dart';

import 'settings_screen.dart';

/// 「我的」标签页 —— App 设置。
///
/// 三个设置入口**各自打开独立分区**，不再都跳同一个混杂长页。
class ProfileTab extends StatelessWidget {
  final ValueChanged<SettingsSection> onOpenSection;
  final VoidCallback onOpenAbout;
  final VoidCallback onDataManage;
  final String versionLabel;
  final String worldCountLabel;
  final String slotCountLabel;

  const ProfileTab({
    super.key,
    required this.onOpenSection,
    required this.onOpenAbout,
    required this.onDataManage,
    required this.versionLabel,
    required this.worldCountLabel,
    required this.slotCountLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: <Widget>[
        Text(
          '我的',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        _tile(
          theme,
          icon: Icons.hub_outlined,
          title: '模型设置',
          subtitle: '服务商 / API Key / 模型代码 / 测试连接',
          onTap: () => onOpenSection(SettingsSection.model),
        ),
        _tile(
          theme,
          icon: Icons.auto_stories_outlined,
          title: '阅读设置',
          subtitle: '主题 / 字号 / 行距 / 首行缩进 / 顶栏',
          onTap: () => onOpenSection(SettingsSection.reading),
        ),
        _tile(
          theme,
          icon: Icons.tune_rounded,
          title: '推演参数',
          subtitle: '发散程度 / 单幕目标字数',
          onTap: () => onOpenSection(SettingsSection.advanced),
        ),
        const Divider(height: 32),
        _tile(
          theme,
          icon: Icons.folder_outlined,
          title: '数据管理',
          subtitle: '$worldCountLabel · $slotCountLabel',
          onTap: onDataManage,
        ),
        _tile(
          theme,
          icon: Icons.info_outline_rounded,
          title: '关于',
          subtitle: '版本 $versionLabel',
          onTap: onOpenAbout,
        ),
      ],
    );
  }

  Widget _tile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      );
}
