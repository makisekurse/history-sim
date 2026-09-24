import 'package:flutter/material.dart';

/// 阅读面专用色板。
///
/// 挂在 [ThemeData.extensions] 上，阅读页通过 [AppTheme.readingOf] 取。
/// 单独抽出来是因为阅读页要的颜色比 Material 语义色更细：
/// 页面底色、正文墨色、极淡分隔线、幕首标记色、选项卡底色。
class ReadingPalette extends ThemeExtension<ReadingPalette> {
  /// 阅读页底
  final Color page;

  /// 正文墨色
  final Color ink;

  /// 次要文字（日期、署名、提示）
  final Color muted;

  /// 极淡分隔线 —— 只用来分隔幕，不能抢正文
  final Color rule;

  /// 强调色（幕首标记、你的行动、进行中）
  final Color accent;

  /// 选项卡底色
  final Color chip;

  /// 选项卡描边
  final Color chipBorder;

  /// 顶栏遮罩
  final Color scrim;

  const ReadingPalette({
    required this.page,
    required this.ink,
    required this.muted,
    required this.rule,
    required this.accent,
    required this.chip,
    required this.chipBorder,
    required this.scrim,
  });

  @override
  ReadingPalette copyWith({
    Color? page,
    Color? ink,
    Color? muted,
    Color? rule,
    Color? accent,
    Color? chip,
    Color? chipBorder,
    Color? scrim,
  }) =>
      ReadingPalette(
        page: page ?? this.page,
        ink: ink ?? this.ink,
        muted: muted ?? this.muted,
        rule: rule ?? this.rule,
        accent: accent ?? this.accent,
        chip: chip ?? this.chip,
        chipBorder: chipBorder ?? this.chipBorder,
        scrim: scrim ?? this.scrim,
      );

  @override
  ReadingPalette lerp(ThemeExtension<ReadingPalette>? other, double t) {
    if (other is! ReadingPalette) return this;
    return ReadingPalette(
      page: Color.lerp(page, other.page, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      chipBorder: Color.lerp(chipBorder, other.chipBorder, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// 应用主题。
///
/// ## 2026-09-25 新增「拟境」
///
/// 原有的三套（时代报章 / 暗夜墨石 / 素雅宣纸）是按「1949 历史推演」
/// 那个定位设计的 —— 纸感、年代标记明显。应用改名「拟境」后，
/// 定位变成**世界书驱动的情境推演**：不限题材，可能是历史，也可能是
/// 架空江湖或近未来都市。
///
/// 所以**新增**一套「拟境」作为这套定位的旗舰皮肤，原三套**原样保留**
/// （老用户的选择不该被拿走）。
///
/// 「拟境」的视觉思路：不是"一页纸"，而是"另一个世界的空气" ——
/// 冷调深墨底 + 雾蓝强调色，长时间沉浸阅读不累眼。
/// 与「暗夜墨石」的区别：那套是暖黑 + 橘调（台灯下的旧书），
/// 这套是冷黑 + 雾蓝（入境时的微光）。
///
/// | id | 名称 | 定位 |
/// |---|---|---|
/// | `mirage` | 拟境 | 冷调深墨，旗舰皮肤 |
/// | `vintage` | 时代报章 | 暖纸 + 砖红，旧报纸质感 |
/// | `dark` | 暗夜墨石 | 暖黑 + 橘调，夜读护眼 |
/// | `parchment` | 素雅宣纸 | 亮白纸面，典雅白描 |
class AppTheme {
  AppTheme._();

  /// 拟境 —— 冷调深墨。为沉浸式推演设计的旗舰皮肤。
  static final ThemeData mirage = _build(
    brightness: Brightness.dark,
    bg: const Color(0xFF0E1218),
    surface: const Color(0xFF171D25),
    primary: const Color(0xFF7FA6C4),
    text: const Color(0xFFDAE1E8),
    divider: const Color(0xFF232B35),
    palette: const ReadingPalette(
      page: Color(0xFF0E1218),
      ink: Color(0xFFD6DEE6),
      muted: Color(0xFF7E8996),
      rule: Color(0xFF232B35),
      accent: Color(0xFF7FA6C4),
      chip: Color(0xFF161C24),
      chipBorder: Color(0xFF28313C),
      scrim: Color(0xF20E1218),
    ),
  );

  /// 时代报章 —— 50-70 年代公文档案与报章质感。
  static final ThemeData vintage = _build(
    brightness: Brightness.light,
    bg: const Color(0xFFF4EFE6),
    surface: const Color(0xFFFAF7F2),
    primary: const Color(0xFFA52A2A),
    text: const Color(0xFF22201D),
    divider: const Color(0xFFDDD6C9),
    palette: const ReadingPalette(
      page: Color(0xFFF4EFE6),
      ink: Color(0xFF22201D),
      muted: Color(0xFF8C8375),
      rule: Color(0xFFDDD6C9),
      accent: Color(0xFFA52A2A),
      chip: Color(0xFFFAF7F2),
      chipBorder: Color(0xFFDDD6C9),
      scrim: Color(0xF2F4EFE6),
    ),
  );

  /// 暗夜墨石 —— 夜读护眼。
  static final ThemeData dark = _build(
    brightness: Brightness.dark,
    bg: const Color(0xFF141416),
    surface: const Color(0xFF202024),
    primary: const Color(0xFFD48B54),
    text: const Color(0xFFE6E3DE),
    divider: const Color(0xFF2E2E33),
    palette: const ReadingPalette(
      page: Color(0xFF141416),
      ink: Color(0xFFE6E3DE),
      muted: Color(0xFF8E8B86),
      rule: Color(0xFF2E2E33),
      accent: Color(0xFFD48B54),
      chip: Color(0xFF202024),
      chipBorder: Color(0xFF2E2E33),
      scrim: Color(0xF2141416),
    ),
  );

  /// 素雅宣纸 —— 典雅白描。
  static final ThemeData parchment = _build(
    brightness: Brightness.light,
    bg: const Color(0xFFFAF6EE),
    surface: Colors.white,
    primary: const Color(0xFF5E503F),
    text: const Color(0xFF282522),
    divider: const Color(0xFFE4DEC8),
    palette: const ReadingPalette(
      page: Color(0xFFFAF6EE),
      ink: Color(0xFF282522),
      muted: Color(0xFF8E8778),
      rule: Color(0xFFE4DEC8),
      accent: Color(0xFF5E503F),
      chip: Color(0xFFFFFFFF),
      chipBorder: Color(0xFFE4DEC8),
      scrim: Color(0xF2FAF6EE),
    ),
  );

  /// 拟境排在最前 —— 它是这套定位的旗舰皮肤。
  static const List<ThemePreset> presets = <ThemePreset>[
    ThemePreset(id: 'mirage', label: '拟境', desc: '冷调深墨'),
    ThemePreset(id: 'vintage', label: '时代报章', desc: '暖纸砖红'),
    ThemePreset(id: 'dark', label: '暗夜墨石', desc: '暖黑夜读'),
    ThemePreset(id: 'parchment', label: '素雅宣纸', desc: '亮白典雅'),
  ];

  /// 新装用户默认用「拟境」；老用户存过的旧值原样生效。
  static const String defaultId = 'mirage';

  static ThemeData getTheme(String mode) {
    switch (mode) {
      case 'mirage':
        return mirage;
      case 'dark':
        return dark;
      case 'parchment':
        return parchment;
      case 'vintage':
      default:
        return vintage;
    }
  }

  /// 取当前主题的阅读面色板。
  static ReadingPalette readingOf(BuildContext context) =>
      Theme.of(context).extension<ReadingPalette>() ??
      vintage.extension<ReadingPalette>()!;

  /// 按主题 id 取色板 —— 设置页做主题预览用。
  static ReadingPalette paletteOfId(String id) =>
      getTheme(id).extension<ReadingPalette>() ??
      vintage.extension<ReadingPalette>()!;

  static double getFontSize(String size) {
    switch (size) {
      case 'sm':
        return 15.0;
      case 'lg':
        return 19.5;
      case 'md':
      default:
        return 17.0;
    }
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color primary,
    required Color text,
    required Color divider,
    required ReadingPalette palette,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardColor: surface,
      dividerColor: divider,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
      ).copyWith(
        primary: primary,
        surface: bg,
        onSurface: text,
        outline: divider,
      ),
      extensions: <ThemeExtension<dynamic>>[palette],
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        centerTitle: true,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: bg),
      dividerTheme: DividerThemeData(color: divider, thickness: 0.8, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        labelStyle: TextStyle(fontSize: 13, color: text.withValues(alpha: 0.75)),
        hintStyle: TextStyle(fontSize: 12, color: text.withValues(alpha: 0.38)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: text, fontSize: 13),
      ),
    );
  }
}

class ThemePreset {
  final String id;
  final String label;

  /// 设置页里的一句话说明
  final String desc;

  const ThemePreset({
    required this.id,
    required this.label,
    this.desc = '',
  });
}
