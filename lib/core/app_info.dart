/// 应用级常量。
///
/// 版本号与 commit 由构建期 `--dart-define` 注入 ——
/// 这样「关于」页显示的就是真实的构建来源，且不需要额外引入 package_info_plus。
class AppInfo {
  AppInfo._();

  static const String appName = '历史推演模拟器';
  static const String appNameEn = 'histsim';
  static const String slogan = '世界书驱动的沉浸式大历史沙盘推演';

  static const String repoOwner = 'makisekurse';
  static const String repoName = 'history-sim';
  static const String repoUrl = 'https://github.com/makisekurse/history-sim';
  static const String releasesUrl = '$repoUrl/releases';
  static const String latestReleaseApi =
      'https://api.github.com/repos/makisekurse/history-sim/releases/latest';

  static const String version =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0-dev');
  static const String buildNumber =
      String.fromEnvironment('BUILD_NUMBER', defaultValue: '0');
  static const String gitSha =
      String.fromEnvironment('GIT_SHA', defaultValue: 'local');

  static String get versionLabel => '$version+$buildNumber';

  static String get shortSha =>
      gitSha.length > 7 ? gitSha.substring(0, 7) : gitSha;
}
