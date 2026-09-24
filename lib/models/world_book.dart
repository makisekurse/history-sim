import 'dart:convert';

/// 世界书 —— 一套完整的世界观 / 扮演人物 / 叙事文风设定。
///
/// 应用本身**不内置任何世界书**，全部由用户新建或导入。
/// 现有《决胜西南1949》的内容已移出代码，作为仓库里的
/// `worldbooks/deng_1949.json` 示例文件，用户可一键导入。
class WorldBook {
  final String id;
  String name;
  String era;
  String worldview;
  String playerRole;
  String narrativeStyle;
  String extraRules;
  String openingScene;
  List<String> openingChoices;
  final bool builtin;
  final DateTime createdAt;

  WorldBook({
    required this.id,
    required this.name,
    this.era = '',
    this.worldview = '',
    this.playerRole = '',
    this.narrativeStyle = '',
    this.extraRules = '',
    this.openingScene = '',
    List<String>? openingChoices,
    this.builtin = false,
    DateTime? createdAt,
  })  : openingChoices = openingChoices ?? <String>[],
        createdAt = createdAt ?? DateTime.now();

  /// 新建一本空白世界书（只是脚手架，不含任何剧本内容）。
  factory WorldBook.blank({String name = '未命名世界书'}) => WorldBook(
        id: newId(),
        name: name,
      );

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// 至少要填这三项才能开始推演。
  bool get isPlayable =>
      name.trim().isNotEmpty &&
      worldview.trim().isNotEmpty &&
      playerRole.trim().isNotEmpty;

  /// 缺哪些必填项，用于提示文案。
  List<String> get missingFields => <String>[
        if (name.trim().isEmpty) '世界书名',
        if (worldview.trim().isEmpty) '世界观设定',
        if (playerRole.trim().isEmpty) '扮演人物',
      ];

  WorldBook copyWith({
    String? name,
    String? era,
    String? worldview,
    String? playerRole,
    String? narrativeStyle,
    String? extraRules,
    String? openingScene,
    List<String>? openingChoices,
  }) =>
      WorldBook(
        id: id,
        name: name ?? this.name,
        era: era ?? this.era,
        worldview: worldview ?? this.worldview,
        playerRole: playerRole ?? this.playerRole,
        narrativeStyle: narrativeStyle ?? this.narrativeStyle,
        extraRules: extraRules ?? this.extraRules,
        openingScene: openingScene ?? this.openingScene,
        openingChoices: openingChoices ?? List<String>.from(this.openingChoices),
        builtin: builtin,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'era': era,
        'worldview': worldview,
        'playerRole': playerRole,
        'narrativeStyle': narrativeStyle,
        'extraRules': extraRules,
        'openingScene': openingScene,
        'openingChoices': openingChoices,
        'builtin': builtin,
        'createdAt': createdAt.toIso8601String(),
      };

  factory WorldBook.fromJson(Map<String, dynamic> json) => WorldBook(
        id: _str(json['id']).isNotEmpty ? _str(json['id']) : newId(),
        name: _str(json['name']).isNotEmpty ? _str(json['name']) : '未命名世界书',
        era: _str(json['era']),
        worldview: _str(json['worldview']),
        playerRole: _str(json['playerRole']),
        narrativeStyle: _str(json['narrativeStyle']),
        extraRules: _str(json['extraRules']),
        openingScene: _str(json['openingScene']),
        openingChoices: _strList(json['openingChoices']),
        builtin: json['builtin'] == true,
        createdAt:
            DateTime.tryParse(_str(json['createdAt'])) ?? DateTime.now(),
      );

  /// 导出成可分享的 JSON 文本。
  String exportToJson({bool pretty = true}) =>
      pretty ? const JsonEncoder.withIndent('  ').convert(toJson()) : jsonEncode(toJson());

  /// 从外部文本导入。
  ///
  /// 支持两种形式：
  /// 1. JSON —— 完整世界书，字段自动填充（兼容少量常见别名）
  /// 2. 纯文本 —— 整段当作「世界观设定」，其余字段留空待补
  static WorldBook fromImportText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('导入内容为空');
    }

    final looksJson = text.startsWith('{') && text.endsWith('}');
    if (looksJson) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          return WorldBook.fromJson(_normalizeKeys(decoded));
        }
        if (decoded is Map) {
          return WorldBook.fromJson(
            _normalizeKeys(Map<String, dynamic>.from(decoded)),
          );
        }
      } on FormatException {
        // 落到下面的纯文本分支
      }
    }

    // 纯文本：整段进世界观，并从首个非空行猜一个名字
    final firstLine = text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '导入的世界书');
    return WorldBook(
      id: newId(),
      name: firstLine.length > 24 ? firstLine.substring(0, 24) : firstLine,
      worldview: text,
    );
  }

  /// 兼容常见别名写法，降低用户手写 JSON 的门槛。
  static Map<String, dynamic> _normalizeKeys(Map<String, dynamic> src) {
    const aliases = <String, String>{
      'title': 'name',
      'world': 'worldview',
      'setting': 'worldview',
      'background': 'worldview',
      'role': 'playerRole',
      'character': 'playerRole',
      'persona': 'playerRole',
      'style': 'narrativeStyle',
      'tone': 'narrativeStyle',
      'rules': 'extraRules',
      'constraints': 'extraRules',
      'opening': 'openingScene',
      'intro': 'openingScene',
      'choices': 'openingChoices',
    };
    final out = <String, dynamic>{};
    src.forEach((k, v) {
      out[aliases[k] ?? k] = v;
    });
    return out;
  }

  static String _str(Object? v) => v == null ? '' : v.toString();

  static List<String> _strList(Object? v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    if (v is String && v.trim().isNotEmpty) {
      return v
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[];
  }
}
