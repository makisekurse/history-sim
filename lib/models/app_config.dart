import 'dart:convert';

/// 全局配置。
///
/// ⚠️ `apiKey` **不参与 JSON 序列化** —— 它单独存进系统加密存储
/// （`flutter_secure_storage`），落盘的是密文而不是明文。
class AppConfig {
  /// 'bailian' | 'deepseek' | 'custom'
  String apiProvider;

  /// 自定义端点（provider 为 custom 时必填；其余留空走默认端点）
  String baseUrl;

  /// 默认用 flash —— 便宜、快，长局推演不容易烧额度。
  String modelName;

  double temperature;

  /// 单幕目标字数，提示词里会带上。
  int maxWords;

  /// 'mirage'（拟境，默认）| 'vintage' | 'dark' | 'parchment'
  String themeMode;

  /// 'sm' | 'md' | 'lg'
  String fontSize;

  double lineHeight;

  /// 竖排阅读
  bool verticalText;

  /// 顶栏自动隐藏（零 HUD）
  bool autoHideHeader;

  /// 打字机逐字输出
  bool typewriter;

  AppConfig({
    this.apiProvider = 'bailian',
    this.baseUrl = '',
    this.modelName = 'qwen3.8-flash',
    this.temperature = 0.85,
    this.maxWords = 500,
    this.themeMode = 'mirage',
    this.fontSize = 'md',
    this.lineHeight = 1.9,
    this.verticalText = false,
    this.autoHideHeader = true,
    this.typewriter = true,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'apiProvider': apiProvider,
        'baseUrl': baseUrl,
        'modelName': modelName,
        'temperature': temperature,
        'maxWords': maxWords,
        'themeMode': themeMode,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'verticalText': verticalText,
        'autoHideHeader': autoHideHeader,
        'typewriter': typewriter,
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        apiProvider: (json['apiProvider'] ?? 'bailian').toString(),
        baseUrl: (json['baseUrl'] ?? '').toString(),
        modelName: (json['modelName'] ?? 'qwen3.8-flash').toString(),
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.85,
        maxWords: (json['maxWords'] as num?)?.toInt() ?? 500,
        themeMode: (json['themeMode'] ?? 'mirage').toString(),
        fontSize: (json['fontSize'] ?? 'md').toString(),
        lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.9,
        verticalText: json['verticalText'] == true,
        autoHideHeader: json['autoHideHeader'] != false,
        typewriter: json['typewriter'] != false,
      );

  AppConfig copyWith({
    String? apiProvider,
    String? baseUrl,
    String? modelName,
    double? temperature,
    int? maxWords,
    String? themeMode,
    String? fontSize,
    double? lineHeight,
    bool? verticalText,
    bool? autoHideHeader,
    bool? typewriter,
  }) =>
      AppConfig(
        apiProvider: apiProvider ?? this.apiProvider,
        baseUrl: baseUrl ?? this.baseUrl,
        modelName: modelName ?? this.modelName,
        temperature: temperature ?? this.temperature,
        maxWords: maxWords ?? this.maxWords,
        themeMode: themeMode ?? this.themeMode,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        verticalText: verticalText ?? this.verticalText,
        autoHideHeader: autoHideHeader ?? this.autoHideHeader,
        typewriter: typewriter ?? this.typewriter,
      );

  String encode() => jsonEncode(toJson());
}
