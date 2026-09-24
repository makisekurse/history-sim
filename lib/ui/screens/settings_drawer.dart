import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/game_config.dart';
import '../../services/storage_service.dart';

/// 侧边设置抽屉 (深度适配阿里云百炼与主题切换)
class SettingsDrawer extends StatefulWidget {
  final GameConfig config;
  final Function(GameConfig newConfig) onConfigChanged;
  final VoidCallback onRestartStory;
  final String fullStoryText;

  const SettingsDrawer({
    super.key,
    required this.config,
    required this.onConfigChanged,
    required this.onRestartStory,
    required this.fullStoryText,
  });

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  late TextEditingController _apiKeyController;
  late TextEditingController _workspaceIdController;
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late String _selectedProvider;
  late String _selectedTheme;
  late String _selectedFontSize;

  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.config.apiProvider;
    _selectedTheme = widget.config.themeMode;
    _selectedFontSize = widget.config.fontSize;

    _apiKeyController = TextEditingController(text: widget.config.apiKey);
    _workspaceIdController = TextEditingController();
    _baseUrlController = TextEditingController(text: widget.config.baseUrl);
    _modelController = TextEditingController(text: widget.config.modelName);

    // 尝试从 BaseUrl 提取 WorkspaceId
    if (widget.config.baseUrl.contains('.cn-beijing.maas.aliyuncs.com')) {
      final reg = RegExp(r'https:\/\/([a-zA-Z0-9_\-]+)\.cn-beijing');
      final match = reg.firstMatch(widget.config.baseUrl);
      if (match != null) {
        _workspaceIdController.text = match.group(1) ?? '';
      }
    }
  }

  void _saveSettings() {
    String computedBaseUrl = _baseUrlController.text.trim();
    final wsId = _workspaceIdController.text.trim();

    if (_selectedProvider == 'bailian') {
      if (wsId.isNotEmpty) {
        computedBaseUrl = 'https://$wsId.cn-beijing.maas.aliyuncs.com/compatible-mode/v1';
      } else if (computedBaseUrl.isEmpty) {
        computedBaseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
      }
    } else if (_selectedProvider == 'deepseek' && computedBaseUrl.isEmpty) {
      computedBaseUrl = 'https://api.deepseek.com/v1';
    }

    final newConfig = GameConfig(
      apiProvider: _selectedProvider,
      apiKey: _apiKeyController.text.trim(),
      baseUrl: computedBaseUrl,
      modelName: _modelController.text.trim().isNotEmpty 
          ? _modelController.text.trim() 
          : (_selectedProvider == 'bailian' ? 'qwen3.8-max' : 'deepseek-chat'),
      themeMode: _selectedTheme,
      fontSize: _selectedFontSize,
    );

    StorageService.saveConfig(newConfig);
    widget.onConfigChanged(newConfig);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _workspaceIdController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // 抽屉头部
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "推演沙盘与模型配置",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 配置表单列表
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  // 1. 算力厂商设置
                  _buildSectionTitle("AI 算力与模型接口"),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _selectedProvider,
                    // isExpanded 必须为 true：默认 false 时选中项那一行不会收缩，
                    // 长文案会撑破抽屉宽度，debug 构建下画出
                    // "RIGHT OVERFLOWED BY x PIXELS" 的黄黑条纹。
                    isExpanded: true,
                    decoration: _inputDecoration("服务提供商"),
                    items: const [
                      DropdownMenuItem(
                        value: "bailian",
                        child: Text(
                          "阿里云百炼 (DashScope OpenAI 兼容)",
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: "deepseek",
                        child: Text(
                          "DeepSeek 官方 API",
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: "offline_demo",
                        child: Text(
                          "离线推演沙盘 (无需联网 Key)",
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: "custom",
                        child: Text(
                          "自定义 OpenAI 兼容接口",
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedProvider = val;
                          if (val == 'bailian') {
                            _modelController.text = 'qwen3.8-max';
                          } else if (val == 'deepseek') {
                            _modelController.text = 'deepseek-chat';
                          }
                        });
                        _saveSettings();
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  if (_selectedProvider != 'offline_demo') ...[
                    // API Key
                    TextFormField(
                      controller: _apiKeyController,
                      obscureText: _obscureApiKey,
                      decoration: _inputDecoration(
                        "API Key (Bearer Token)",
                        hintText: "填入阿里云百炼获得的 sk-xxxx",
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() => _obscureApiKey = !_obscureApiKey);
                          },
                        ),
                      ),
                      onChanged: (_) => _saveSettings(),
                    ),
                    const SizedBox(height: 14),

                    // 阿里云特有业务空间 ID (北京地域 maas)
                    if (_selectedProvider == 'bailian') ...[
                      TextFormField(
                        controller: _workspaceIdController,
                        decoration: _inputDecoration(
                          "业务空间 ID (WorkspaceId, 选填)",
                          hintText: "华北2北京地域填入，普通空间可留空",
                        ),
                        onChanged: (_) => _saveSettings(),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 模型名称
                    TextFormField(
                      controller: _modelController,
                      decoration: _inputDecoration(
                        "推演模型代码",
                        hintText: "例如：qwen3.8-max, qwen-plus, deepseek-chat",
                      ),
                      onChanged: (_) => _saveSettings(),
                    ),
                    const SizedBox(height: 14),

                    if (_selectedProvider == 'custom') ...[
                      TextFormField(
                        controller: _baseUrlController,
                        decoration: _inputDecoration(
                          "自定义 Base URL",
                          hintText: "https://api.example.com/v1",
                        ),
                        onChanged: (_) => _saveSettings(),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],

                  const Divider(height: 32),

                  // 2. 纸质排版风格
                  _buildSectionTitle("纸质排版与视觉质感"),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildThemeChip("时代报章", "vintage"),
                      const SizedBox(width: 8),
                      _buildThemeChip("暗夜墨石", "dark"),
                      const SizedBox(width: 8),
                      _buildThemeChip("素雅宣纸", "parchment"),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 字号调节
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "正文字号大小",
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Row(
                        children: [
                          _buildFontSizeBtn("小", "sm"),
                          const SizedBox(width: 6),
                          _buildFontSizeBtn("中", "md"),
                          const SizedBox(width: 6),
                          _buildFontSizeBtn("大", "lg"),
                        ],
                      ),
                    ],
                  ),

                  const Divider(height: 32),

                  // 3. 剧情历程管理
                  _buildSectionTitle("剧本进度管理"),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.fullStoryText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("已将当前推演长文复制到剪贴板！")),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text("导出整部推演小说到剪贴板"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onRestartStory();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text("重启《决胜西南1949》第一幕"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor.withOpacity(0.12),
                      foregroundColor: primaryColor,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildThemeChip(String label, String code) {
    final isSelected = _selectedTheme == code;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          setState(() => _selectedTheme = code);
          _saveSettings();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? primaryColor.withOpacity(0.12) : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? primaryColor : Theme.of(context).dividerColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? primaryColor : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFontSizeBtn(String label, String code) {
    final isSelected = _selectedFontSize == code;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        setState(() => _selectedFontSize = code);
        _saveSettings();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hintText, Widget? suffixIcon}) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      hintStyle: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.4)),
      labelStyle: const TextStyle(fontSize: 13),
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
    );
  }
}
