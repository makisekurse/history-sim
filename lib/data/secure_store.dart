import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API Key 的加密存储。
///
/// Android 走 EncryptedSharedPreferences，落盘是密文。
/// 若当前平台不支持（例如桌面端调试），自动降级为「内存中保留」，
/// 保证功能不崩 —— 只是该次运行内有效，不落盘。
class SecureStore {
  SecureStore._();

  static const String _keyApiKey = 'histsim_api_key_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _memoryFallback = '';
  static bool _degraded = false;

  /// 是否退化成了内存存储（UI 可据此提示用户）。
  static bool get isDegraded => _degraded;

  static Future<String> readApiKey() async {
    try {
      final v = await _storage.read(key: _keyApiKey);
      if (v != null) return v;
    } catch (_) {
      _degraded = true;
    }
    return _memoryFallback;
  }

  static Future<void> writeApiKey(String value) async {
    _memoryFallback = value;
    try {
      await _storage.write(key: _keyApiKey, value: value);
      _degraded = false;
    } catch (_) {
      _degraded = true;
    }
  }

  static Future<void> clearApiKey() async {
    _memoryFallback = '';
    try {
      await _storage.delete(key: _keyApiKey);
    } catch (_) {
      _degraded = true;
    }
  }
}
