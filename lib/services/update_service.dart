import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_info.dart';

class ReleaseInfo {
  final String tag;
  final String name;
  final String pageUrl;
  final String notes;
  final String apkUrl;
  final int apkSizeBytes;
  final DateTime? publishedAt;

  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.pageUrl,
    required this.notes,
    required this.apkUrl,
    this.apkSizeBytes = 0,
    this.publishedAt,
  });

  String get apkSizeLabel {
    if (apkSizeBytes <= 0) return '';
    final mb = apkSizeBytes / 1024 / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// 检查 GitHub Release 是否有新版本。
class UpdateService {
  UpdateService._();

  static Future<ReleaseInfo?> checkLatest() async {
    final client = http.Client();
    try {
      final resp = await client.get(
        Uri.parse(AppInfo.latestReleaseApi),
        headers: <String, String>{'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;

      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) return null;

      final assets = decoded['assets'];
      String apkUrl = '';
      int apkSize = 0;
      if (assets is List) {
        for (final a in assets) {
          if (a is Map && (a['name'] ?? '').toString().endsWith('.apk')) {
            apkUrl = (a['browser_download_url'] ?? '').toString();
            apkSize = (a['size'] as num?)?.toInt() ?? 0;
            break;
          }
        }
      }

      return ReleaseInfo(
        tag: (decoded['tag_name'] ?? '').toString(),
        name: (decoded['name'] ?? '').toString(),
        pageUrl: (decoded['html_url'] ?? AppInfo.releasesUrl).toString(),
        notes: (decoded['body'] ?? '').toString(),
        apkUrl: apkUrl,
        apkSizeBytes: apkSize,
        publishedAt: DateTime.tryParse((decoded['published_at'] ?? '').toString()),
      );
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// 简单比较 `v1.2.3` 与 `1.0.0` 这类标签，返回远端是否更新。
  static bool isNewer(String remoteTag, String localVersion) {
    final r = _parse(remoteTag);
    final l = _parse(localVersion);
    for (var i = 0; i < 3; i++) {
      if (r[i] != l[i]) return r[i] > l[i];
    }
    return false;
  }

  static List<int> _parse(String v) {
    final cleaned = v.replaceAll(RegExp(r'[^0-9\.]'), '');
    final parts = cleaned.split('.').where((e) => e.isNotEmpty).toList();
    final out = <int>[0, 0, 0];
    for (var i = 0; i < 3 && i < parts.length; i++) {
      out[i] = int.tryParse(parts[i]) ?? 0;
    }
    return out;
  }
}
