import 'package:flutter/material.dart';

/// 沉浸式阅读主题系统。
///
/// 全部走「零 HUD 阅读器」的思路：底色低饱和、正文高对比，
/// 装饰色只出现在分隔线与强调字上。配色沿用原有的三套纸质皮肤。
class AppTheme {
  AppTheme._();

  // 时代报章 (50-70年代公文档案与报章质感)
  static final ThemeData vintage = _build(
    brightness: Brightness.light,
    bg: const Color(0xFFF4EFE6),
    surface: const Color(0xFFFAF7F2),
    primary: const Color(0xFFA52A2A),
    text: const Color(0xFF22201D),
    divider: const Color(0xFFDDD6C9),
  );

  // 暗夜墨石 (夜读护眼)
  static final ThemeData dark = _build(
    brightness: Brightness.dark,
    bg: const Color(0xFF141416),
    surface: const Color(0xFF202024),
    primary: const Color(0xFFD48B54),
    text: const Color(0xFFE6E3DE),
    divider: const Color(0xFF2E2E33),
  );

  // 素雅宣纸 (典雅白描)
  static final ThemeData parchment = _build(
    brightness: Brightness.light,
    bg: const Color(0xFFFAF6EE),
    surface: Colors.white,
    primary: const Color(0xFF5E503F),
    text: const Color(0xFF282522),
    divider: const Color(0xFFE4DEC8),
  );

  static const List<ThemePreset> presets = <ThemePreset>[
    ThemePreset(id: 'vintage', label: '时代报章'),
    ThemePreset(id: 'dark', label: '暗夜墨石'),
    ThemePreset(id: 'parchment', label: '素雅宣纸'),
  ];

  static ThemeData getTheme(String mode) {
    switch (mode) {
      case 'dark':
        return dark;
      case 'parchment':
        return parchment;
      case 'vintage':
      default:
        return vintage;
    }
  }

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
  const ThemePreset({required this.id, required this.label});
}
