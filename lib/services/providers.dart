import '../models/app_config.dart';

/// 一家算力提供商的预设。
class ProviderOption {
  final String id;
  final String label;
  final String defaultBaseUrl;
  final String defaultModel;
  final String hint;

  const ProviderOption({
    required this.id,
    required this.label,
    required this.defaultBaseUrl,
    required this.defaultModel,
    this.hint = '',
  });
}

class Providers {
  Providers._();

  static const List<ProviderOption> options = <ProviderOption>[
    ProviderOption(
      id: 'bailian',
      label: '阿里云百炼（DashScope OpenAI 兼容）',
      defaultBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      defaultModel: 'qwen3.8-flash',
      hint: 'Key 形如 sk-xxxx。华北2（北京）若填了业务空间 ID，会自动改用专属域名。',
    ),
    ProviderOption(
      id: 'deepseek',
      label: 'DeepSeek 官方 API',
      defaultBaseUrl: 'https://api.deepseek.com/v1',
      defaultModel: 'deepseek-chat',
      hint: 'Key 形如 sk-xxxx。',
    ),
    ProviderOption(
      id: 'custom',
      label: '自定义 OpenAI 兼容接口',
      defaultBaseUrl: '',
      defaultModel: '',
      hint: '填完整的 Base URL，例如 https://api.example.com/v1',
    ),
  ];

  /// 百炼上常用的模型，做成快捷选项（仍可手填任意模型名）。
  static const List<String> bailianModels = <String>[
    'qwen3.8-flash',
    'qwen3.8-max',
    'qwen3.7-plus',
    'qwen3.7-flash',
    'qwen-plus',
  ];

  static const List<String> deepseekModels = <String>[
    'deepseek-chat',
    'deepseek-reasoner',
  ];

  static ProviderOption byId(String id) => options.firstWhere(
        (e) => e.id == id,
        orElse: () => options.first,
      );

  /// 解析出实际要请求的 Base URL。
  ///
  /// 百炼支持业务空间专属域名：`https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`，
  /// 稳定性更好，所以填了 WorkspaceId 就优先用它。
  static String resolveBaseUrl(AppConfig config, {String workspaceId = ''}) {
    final custom = config.baseUrl.trim();
    if (config.apiProvider == 'custom') return custom;

    final ws = workspaceId.trim();
    if (config.apiProvider == 'bailian' && ws.isNotEmpty) {
      return 'https://$ws.cn-beijing.maas.aliyuncs.com/compatible-mode/v1';
    }
    if (custom.isNotEmpty) return custom;
    return byId(config.apiProvider).defaultBaseUrl;
  }

  /// 拼成 `/chat/completions` 完整地址。
  static String chatCompletionsUrl(AppConfig config, {String workspaceId = ''}) {
    var base = resolveBaseUrl(config, workspaceId: workspaceId);
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (base.endsWith('/chat/completions')) return base;
    return '$base/chat/completions';
  }

  /// qwen3 系列默认开启思考模式 —— 会额外产出思维链 token，
  /// 既慢又贵，还会把思考过程混进正文。必须显式关掉。
  static bool supportsThinkingSwitch(String model) =>
      model.toLowerCase().startsWith('qwen3');
}
