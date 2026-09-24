import 'package:flutter/material.dart';

import '../../data/prefs_store.dart';
import '../../data/secure_store.dart';
import '../../models/app_config.dart';
import '../../services/llm_client.dart';
import '../../services/providers.dart';
import '../themes/app_theme.dart';
import 'about_screen.dart';

/// 设置页。
///
/// 注意：这里**没有「剧本进度管理」** —— 那部分已由「世界书」取代，
/// 世界书的增删改在首页的「世界书」标签页里。
class SettingsScreen extends StatefulWidget {
  final AppConfig config;
  final ValueChanged<AppConfig> onConfigChanged;

  const SettingsScreen({
    super.key,
    required this.config,
    required this.onConfigChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppConfig _config;

  late TextEditingController _keyCtrl;
  late TextEditingController _wsCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _baseUrlCtrl;

  bool _obscure = true;
  bool _testing = false;
  String _testResult = '';

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _keyCtrl = TextEditingController();
    _wsCtrl = TextEditingController();
    _modelCtrl = TextEditingController(text: _config.modelName);
    _baseUrlCtrl = TextEditingController(text: _config.baseUrl);
    _loadKey();
    _loadWorkspaceId();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _wsCtrl.dispose();
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final k = await SecureStore.readApiKey();
    if (!mounted) return;
    setState(() => _keyCtrl.text = k);
  }

  Future<void> _loadWorkspaceId() async {
    final ws = await PrefsStore.getString(_kWorkspace) ?? '';
    if (!mounted) return;
    setState(() => _wsCtrl.text = ws);
  }

  static const String _kWorkspace = 'nijing_workspace_id';

  /// 当前所选主题的一句话说明。
  String _themeDesc() {
    for (final p in AppTheme.presets) {
      if (p.id == _config.themeMode) return p.desc;
    }
    return '';
  }

  /// 写入配置。
  ///
  /// [immediate] 用于**离散选择**（主题、字号、开关、选模型）——
  /// 这类操作点一下就定了，必须立刻落盘。
  ///
  /// ⚠️ 2026-09-25 修：以前一律走 700ms 防抖，用户改完主题马上退出应用，
  /// 改动就丢了 —— 表现为「设置没生效」。输入框与滑杆继续用防抖。
  void _apply(
    AppConfig next, {
    bool persistKey = false,
    bool immediate = false,
  }) {
    setState(() => _config = next);
    widget.onConfigChanged(next);

    final raw = next.encode();
    if (immediate) {
      PrefsStore.setString('nijing_config_v1', raw);
    } else {
      PrefsStore.setStringDebounced('nijing_config_v1', raw);
    }

    if (persistKey) {
      SecureStore.writeApiKey(_keyCtrl.text.trim());
    }
    PrefsStore.setStringDebounced(_kWorkspace, _wsCtrl.text.trim());
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = '';
    });
    final err = await LlmClient().testConnection(
      config: _config,
      apiKey: _keyCtrl.text.trim(),
      workspaceId: _wsCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = err == null ? '✅ 连接成功，模型可用。' : '❌ $err';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Providers.byId(_config.apiProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: <Widget>[
          _section(theme, 'AI 算力与模型接口'),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            initialValue: _config.apiProvider,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '服务提供商'),
            items: Providers.options
                .map(
                  (p) => DropdownMenuItem<String>(
                    value: p.id,
                    child: Text(
                      p.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              final p = Providers.byId(v);
              _modelCtrl.text = p.defaultModel;
              _baseUrlCtrl.text = '';
              _apply(
                _config.copyWith(
                  apiProvider: v,
                  modelName: p.defaultModel,
                  baseUrl: '',
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _keyCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-xxxx',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (_) => _apply(_config, persistKey: true),
          ),
          const SizedBox(height: 6),
          Text(
            SecureStore.isDegraded
                ? '⚠️ 当前设备不支持加密存储，Key 仅保存在本次运行的内存中。'
                : 'Key 以密文保存在本机，不会上传到任何服务器。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 14),

          if (_config.apiProvider == 'bailian') ...<Widget>[
            TextField(
              controller: _wsCtrl,
              decoration: const InputDecoration(
                labelText: '业务空间 ID（选填）',
                hintText: '华北2（北京）填了会改用专属域名，更稳定',
              ),
              onChanged: (_) => _apply(_config),
            ),
            const SizedBox(height: 14),
          ],

          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: '模型代码',
              hintText: '例如 qwen3.8-flash',
            ),
            onChanged: (v) => _apply(_config.copyWith(modelName: v)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (_config.apiProvider == 'deepseek'
                    ? Providers.deepseekModels
                    : Providers.bailianModels)
                .map(
                  (m) => ActionChip(
                    label: Text(m, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      _modelCtrl.text = m;
                      _apply(_config.copyWith(modelName: m), immediate: true);
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),

          if (_config.apiProvider == 'custom') ...<Widget>[
            TextField(
              controller: _baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.example.com/v1',
              ),
              onChanged: (v) => _apply(_config.copyWith(baseUrl: v)),
            ),
            const SizedBox(height: 14),
          ],

          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: Text(_testing ? '测试中…' : '测试连接'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: theme.dividerColor),
                  ),
                ),
              ),
            ],
          ),
          if (_testResult.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            SelectableText(
              _testResult,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            provider.hint,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),

          const Divider(height: 40),
          _section(theme, '推演参数'),
          const SizedBox(height: 6),
          _slider(
            theme,
            label: '发散程度（temperature）',
            value: _config.temperature,
            min: 0.1,
            max: 1.4,
            display: _config.temperature.toStringAsFixed(2),
            onChanged: (v) => _apply(_config.copyWith(temperature: v)),
          ),
          _slider(
            theme,
            label: '单幕目标字数',
            value: _config.maxWords.toDouble(),
            min: 200,
            max: 1200,
            divisions: 20,
            display: '${_config.maxWords} 字',
            onChanged: (v) =>
                _apply(_config.copyWith(maxWords: v.round())),
          ),

          const Divider(height: 40),
          _section(theme, '阅读体验'),
          const SizedBox(height: 12),
          // 四套皮肤用 Wrap 排 —— 用 Row+Expanded 的话每个只有 70dp 宽，
          // 「时代报章」这种四字标签会被挤到省略号。
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppTheme.presets
                .map(
                  (p) => _chip(
                    theme,
                    label: p.label,
                    swatch: AppTheme.paletteOfId(p.id).page,
                    selected: _config.themeMode == p.id,
                    onTap: () => _apply(
                      _config.copyWith(themeMode: p.id),
                      immediate: true,
                    ),
                  ),
                )
                .toList(),
          ),
          if (_themeDesc().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _themeDesc(),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _switchRow(
            theme,
            '竖排阅读',
            '正文改竖排，古典小说的读感',
            _config.verticalText,
            (v) => _apply(_config.copyWith(verticalText: v), immediate: true),
          ),
          _switchRow(
            theme,
            '顶栏自动隐藏',
            '轻触屏幕唤出，3 秒后自动淡出',
            _config.autoHideHeader,
            (v) => _apply(_config.copyWith(autoHideHeader: v), immediate: true),
          ),
          _switchRow(
            theme,
            '打字机效果',
            '逐字渐现；生成中轻触屏幕可跳过',
            _config.typewriter,
            (v) => _apply(_config.copyWith(typewriter: v), immediate: true),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Text(
                '字号',
                style: TextStyle(
                  fontSize: 13.5,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              for (final opt in <List<String>>[
                <String>['sm', '小'],
                <String>['md', '中'],
                <String>['lg', '大'],
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _chip(
                    theme,
                    label: opt[1],
                    selected: _config.fontSize == opt[0],
                    onTap: () =>
                        _apply(_config.copyWith(fontSize: opt[0]), immediate: true),
                    compact: true,
                  ),
                ),
            ],
          ),
          _slider(
            theme,
            label: '行距',
            value: _config.lineHeight,
            min: 1.4,
            max: 2.6,
            display: _config.lineHeight.toStringAsFixed(1),
            onChanged: (v) => _apply(_config.copyWith(lineHeight: v)),
          ),

          const Divider(height: 40),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('关于本应用', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title) => Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: theme.colorScheme.primary,
        ),
      );

  Widget _chip(
    ThemeData theme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool compact = false,
    /// 可选预览色 —— 主题选择用它显示这套皮肤的实际观感
    Color? swatch,
  }) {
    final primary = theme.colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 8,
          vertical: compact ? 6 : 9,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.12) : theme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? primary : theme.dividerColor,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (swatch != null) ...<Widget>[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.25),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? primary : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(
    ThemeData theme,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5)),
        activeThumbColor: theme.colorScheme.primary,
      );

  Widget _slider(
    ThemeData theme, {
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                display,
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: theme.colorScheme.primary,
            onChanged: onChanged,
          ),
        ],
      );
}
