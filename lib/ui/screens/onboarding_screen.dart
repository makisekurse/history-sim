import 'package:flutter/material.dart';

import '../../core/app_info.dart';

/// 首次启动引导。
///
/// 旧版没配 Key 时会**静默**掉进离线沙盘，用户完全不知道发生了什么。
/// 现在第一次打开就明确告诉他：这是个引擎，需要一本世界书和一个模型。
class OnboardingScreen extends StatelessWidget {
  final VoidCallback onConfigure;
  final VoidCallback onSkip;

  const OnboardingScreen({
    super.key,
    required this.onConfigure,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.62);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 1.1,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  AppInfo.appNameEn,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                AppInfo.appName,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                AppInfo.slogan,
                style: TextStyle(fontSize: 13.5, color: muted),
              ),
              const SizedBox(height: 32),
              _item(theme, '一本世界书', '决定你演谁、身处什么时代、用什么文风。可以自己写，也可以导入别人分享的提示词。'),
              _item(theme, '一个模型接口', '推演内容由你自己配置的大模型实时生成，应用不内置任何剧情。'),
              _item(theme, '一切只在本机', '世界书、存档、API Key 都不会上传到任何服务器。'),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onConfigure,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: const Text('配置模型接口'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onSkip,
                  child: const Text('先逛逛，稍后再配'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(ThemeData theme, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(top: 8, right: 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
              ),
            ),
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
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.7,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
