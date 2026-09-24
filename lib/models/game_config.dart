/// 游戏与大模型接口配置模型
class GameConfig {
  String apiProvider; // 'custom_doc', 'deepseek', 'bailian', 'offline_demo'
  String apiKey;
  String baseUrl;
  String modelName;
  String themeMode; // 'vintage', 'dark', 'parchment'
  String fontSize;  // 'sm', 'md', 'lg'
  String customHeadersJson; // 预留自定义请求头配置（适配后续技术文档）
  String customBodyJson;    // 预留自定义请求体模板（适配后续技术文档）

  GameConfig({
    this.apiProvider = 'offline_demo',
    this.apiKey = '',
    this.baseUrl = '',
    this.modelName = 'deepseek-chat',
    this.themeMode = 'vintage',
    this.fontSize = 'md',
    this.customHeadersJson = '{}',
    this.customBodyJson = '{}',
  });

  Map<String, dynamic> toJson() => {
    'apiProvider': apiProvider,
    'apiKey': apiKey,
    'baseUrl': baseUrl,
    'modelName': modelName,
    'themeMode': themeMode,
    'fontSize': fontSize,
    'customHeadersJson': customHeadersJson,
    'customBodyJson': customBodyJson,
  };

  factory GameConfig.fromJson(Map<String, dynamic> json) => GameConfig(
    apiProvider: json['apiProvider'] as String? ?? 'offline_demo',
    apiKey: json['apiKey'] as String? ?? '',
    baseUrl: json['baseUrl'] as String? ?? '',
    modelName: json['modelName'] as String? ?? 'deepseek-chat',
    themeMode: json['themeMode'] as String? ?? 'vintage',
    fontSize: json['fontSize'] as String? ?? 'md',
    customHeadersJson: json['customHeadersJson'] as String? ?? '{}',
    customBodyJson: json['customBodyJson'] as String? ?? '{}',
  );
}
