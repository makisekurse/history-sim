import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../services/update_service.dart';

/// 关于页。
///
/// 刻意保持极简：只显示**开发者**与**版本号**，外加一个检查更新。
/// 构建号 / commit / 包名这些是排障用的，属于内部信息，不摆在用户面前
/// —— 真需要排查时，它们已经打在 Release 说明与 CI 日志里了。
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _checking = false;
  String _result = '';

  Future<void> _checkUpdate() async {
    setState(() {
      _checking = true;
      _result = '';
    });
    final info = await UpdateService.checkLatest();
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _checking = false;
        _result = '检查失败：无法访问更新服务（可能是网络问题）。';
      });
      return;
    }
    final newer = UpdateService.isNewer(info.tag, AppInfo.version);
    setState(() {
      _checking = false;
      _result = newer
          ? '发现新版本 ${info.tag}'
              '${info.apkSizeLabel.isEmpty ? '' : '（${info.apkSizeLabel}）'}'
              '\n下载：${info.apkUrl.isEmpty ? info.pageUrl : info.apkUrl}'
          : '已是最新版本（远端 ${info.tag}）。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        children: <Widget>[
          Center(
            child: Text(
              AppInfo.appName,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 32),
          _row(theme, '开发者', AppInfo.developer),
          _row(theme, '版本号', AppInfo.version),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: _checking ? null : _checkUpdate,
            icon: _checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt_rounded, size: 18),
            label: Text(_checking ? '正在检查…' : '检查更新'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              side: BorderSide(color: theme.dividerColor),
            ),
          ),
          if (_result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: SelectableText(
                _result,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.65,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Center(
            child: Text(
              '世界书与存档只保存在本机。',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
