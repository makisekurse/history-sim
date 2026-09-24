import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../services/update_service.dart';

/// 关于页：版本号 + 构建来源 + 检查更新。
///
/// 版本号与 commit 由构建期注入，所以这里显示的永远是真实的构建来源 ——
/// 交付时对得上「这包是从哪个提交出来的」。
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
        _result = '检查失败：无法访问 GitHub（可能是网络或仓库为私有）。';
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
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                Text(
                  AppInfo.appName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppInfo.slogan,
                  style: TextStyle(fontSize: 12.5, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          _row(theme, '版本号', AppInfo.version),
          _row(theme, '构建号', AppInfo.buildNumber),
          _row(theme, '提交', AppInfo.shortSha),
          _row(theme, '包名', 'io.github.makisekurse.histsim'),
          const SizedBox(height: 20),
          Text(
            '世界书、存档、API Key 全部只保存在本机。'
            '推演内容由你配置的大模型生成，应用本身不内置任何剧本。',
            style: TextStyle(fontSize: 12.5, height: 1.7, color: muted),
          ),
          const SizedBox(height: 24),
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
              padding: const EdgeInsets.symmetric(vertical: 12),
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
          const SizedBox(height: 26),
          Center(
            child: Text(
              AppInfo.repoUrl,
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
