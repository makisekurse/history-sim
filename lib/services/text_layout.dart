/// 正文排版：分段、段首缩进、段间距。
///
/// 名字不叫 Typography —— 那个名字 Flutter 的 material.dart 里已经有了，
/// 一起 import 会报 ambiguous_import。
///
/// 抽成独立模块是为了**可单测**。
///
/// ⚠️ 2026-09-25：「首行缩进」开关加了没效果，根因就在分段逻辑 ——
/// 旧代码只按 `\n\n` 切段，而模型经常用单个 `\n`（甚至带 `\r`），
/// 结果整篇被当成一个段落，只在最开头缩进一次，看起来就像"没生效"。
class TextLayout {
  TextLayout._();

  /// 把正文切成段落。
  ///
  /// 用 `\r?\n+` 而不是 `\n\n`：模型输出的换行数并不稳定，
  /// 有的每段一个 `\n`，有的空一行，有的还带 `\r`。
  static List<String> paragraphs(String content) => content
      .split(RegExp(r'\r?\n+'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  /// 段首缩进串。
  ///
  /// 用**全角空格**（U+3000）而不是几个半角空格 ——
  /// 中文字体下只有全角空格才等于一个汉字的宽度。
  static String indent(int level) => '　' * level.clamp(0, 4);

  /// 段间距（逻辑像素）。
  static double spacing(String key) {
    switch (key) {
      case 'tight':
        return 8;
      case 'loose':
        return 28;
      case 'normal':
      default:
        return 16;
    }
  }

  /// 段首缩进的可选项：0 / 1 / 2 格。
  ///
  /// 标签刻意用短词 —— 三个选项挤在一行里，四字标签会换行。
  static const List<List<String>> indentOptions = <List<String>>[
    <String>['0', '顶格'],
    <String>['1', '一格'],
    <String>['2', '两格'],
  ];

  /// 段间距的可选项。
  static const List<List<String>> spacingOptions = <List<String>>[
    <String>['tight', '紧凑'],
    <String>['normal', '适中'],
    <String>['loose', '宽松'],
  ];
}
