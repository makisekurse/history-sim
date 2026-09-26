import 'package:flutter/services.dart';

/// 屏幕常亮控制服务（用于沉浸推演阅读，防熄屏）。
///
/// 通过原生平台通道调度 Android 的 FLAG_KEEP_SCREEN_ON，
/// 零额外三方插件依赖，安全轻量，在离开阅读页或切后台时释放。
class WakelockService {
  WakelockService._();

  static const MethodChannel _channel =
      MethodChannel('io.github.makisekurse.nijing/wakelock');

  static bool _enabled = false;
  static bool get isEnabled => _enabled;

  /// 开启屏幕常亮
  static Future<void> enable() async {
    try {
      await _channel.invokeMethod<bool>('enable');
      _enabled = true;
    } catch (_) {
      // 容错处理：单测或未注册通道时不崩溃
    }
  }

  /// 释放屏幕常亮
  static Future<void> disable() async {
    try {
      await _channel.invokeMethod<bool>('disable');
      _enabled = false;
    } catch (_) {
      // 容错处理
    }
  }
}
