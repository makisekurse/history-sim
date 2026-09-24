import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_info.dart';
import 'data/prefs_store.dart';
import 'models/app_config.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/themes/app_theme.dart';

const String kConfigKey = 'nijing_config_v1';
const String kFirstRunKey = 'nijing_first_run_done';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  final config = await _loadConfig();
  final firstRun = (await PrefsStore.getString(kFirstRunKey)) != 'done';

  runApp(HistSimApp(initialConfig: config, showOnboarding: firstRun));
}

Future<AppConfig> _loadConfig() async {
  final raw = await PrefsStore.getString(kConfigKey);
  if (raw == null || raw.isEmpty) return AppConfig();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return AppConfig.fromJson(Map<String, dynamic>.from(decoded));
    }
  } catch (_) {
    // 配置损坏时回落到默认值，不要让应用起不来。
  }
  return AppConfig();
}

class HistSimApp extends StatefulWidget {
  final AppConfig initialConfig;
  final bool showOnboarding;

  const HistSimApp({
    super.key,
    required this.initialConfig,
    required this.showOnboarding,
  });

  @override
  State<HistSimApp> createState() => _HistSimAppState();
}

class _HistSimAppState extends State<HistSimApp> {
  late AppConfig _config;
  late bool _onboarding;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _onboarding = widget.showOnboarding;
  }

  void _updateConfig(AppConfig c) {
    setState(() => _config = c);
  }

  Future<void> _finishOnboarding({required bool openSettings}) async {
    await PrefsStore.setString(kFirstRunKey, 'done');
    if (!mounted) return;
    setState(() => _onboarding = false);
    if (openSettings) {
      // 交给下一帧，确保 Navigator 已经挂上。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _navKey.currentContext;
        if (ctx == null) return;
        Navigator.of(ctx).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(
              config: _config,
              onConfigChanged: _updateConfig,
            ),
          ),
        );
      });
    }
  }

  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      theme: AppTheme.getTheme(_config.themeMode),
      home: _onboarding
          ? OnboardingScreen(
              onConfigure: () => _finishOnboarding(openSettings: true),
              onSkip: () => _finishOnboarding(openSettings: false),
            )
          : HomeShell(
              config: _config,
              onConfigChanged: _updateConfig,
            ),
    );
  }
}
