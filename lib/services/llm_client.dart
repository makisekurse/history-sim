import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_error.dart';
import '../models/app_config.dart';
import 'providers.dart';

/// 统一的流式大模型客户端。
///
/// 相比旧版补齐了三件事：
/// 1. **超时** —— 旧版没有超时，SSE 卡住会永久挂起，只能杀进程
/// 2. **可中止** —— [cancel] 立刻断开
/// 3. **错误分类 + 自动重试** —— 不再把异常整个吞掉
class LlmClient {
  LlmClient({this.connectTimeout = const Duration(seconds: 30)});

  final Duration connectTimeout;
  static const int _maxRetries = 2;

  http.Client? _client;
  bool _cancelled = false;
  bool _yieldedAny = false;

  bool get isCancelled => _cancelled;

  /// 立刻中止当前请求。
  void cancel() {
    _cancelled = true;
    _client?.close();
    _client = null;
  }

  void reset() {
    _cancelled = false;
    _yieldedAny = false;
  }

  /// 流式生成一幕。逐段 yield 文本增量。
  ///
  /// 抛出的异常一律是 [AppError]，UI 直接读 `message` 即可显示。
  Stream<String> streamChat({
    required AppConfig config,
    required String apiKey,
    required List<Map<String, String>> messages,
    String workspaceId = '',
  }) async* {
    reset();
    var attempt = 0;

    while (true) {
      try {
        yield* _singleRequest(
          config: config,
          apiKey: apiKey,
          messages: messages,
          workspaceId: workspaceId,
        );
        return;
      } on AppError catch (e) {
        final canRetry = e.retryable &&
            !_yieldedAny &&
            !_cancelled &&
            attempt < _maxRetries;
        if (!canRetry) rethrow;
        attempt++;
        // 指数退避：0.8s → 2.0s
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt * attempt));
      }
    }
  }

  Stream<String> _singleRequest({
    required AppConfig config,
    required String apiKey,
    required List<Map<String, String>> messages,
    required String workspaceId,
  }) async* {
    final url = Providers.chatCompletionsUrl(config, workspaceId: workspaceId);

    final body = <String, dynamic>{
      'model': config.modelName.trim().isEmpty
          ? Providers.byId(config.apiProvider).defaultModel
          : config.modelName.trim(),
      'messages': messages,
      'stream': true,
      'temperature': config.temperature,
    };
    // qwen3 系列默认开思考模式，必须显式关掉，否则又慢又贵还污染正文。
    if (Providers.supportsThinkingSwitch(config.modelName)) {
      body['enable_thinking'] = false;
    }

    final request = http.Request('POST', Uri.parse(url));
    request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode(body);

    final client = http.Client();
    _client = client;

    http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(connectTimeout);
    } on TimeoutException {
      client.close();
      throw const AppError(
        AppErrorKind.network,
        '连接模型服务超时（30 秒无响应），请检查网络或代理。',
      );
    } catch (e) {
      client.close();
      if (_cancelled) {
        throw const AppError(AppErrorKind.cancelled, '已中止。');
      }
      throw AppError(
        AppErrorKind.network,
        '无法连接到模型服务，请检查网络连通性与 Base URL。',
        detail: e.toString(),
      );
    }

    if (response.statusCode != 200) {
      String text = '';
      try {
        text = await response.stream.bytesToString().timeout(connectTimeout);
      } catch (_) {
        text = '';
      }
      client.close();
      throw AppError.fromStatus(response.statusCode, text);
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    try {
      await for (final line in lines) {
        if (_cancelled) {
          client.close();
          throw const AppError(AppErrorKind.cancelled, '已中止。');
        }
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;

        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') break;

        String? chunk;
        try {
          final map = jsonDecode(payload);
          if (map is Map) {
            final choices = map['choices'];
            if (choices is List && choices.isNotEmpty) {
              final first = choices.first;
              if (first is Map) {
                final delta = first['delta'];
                if (delta is Map) {
                  final c = delta['content'];
                  if (c is String && c.isNotEmpty) chunk = c;
                }
              }
            }
          }
        } catch (_) {
          // 忽略非 JSON 行（有些实现会插入心跳）
        }

        if (chunk != null) {
          _yieldedAny = true;
          yield chunk;
        }
      }
    } on AppError {
      rethrow;
    } catch (e) {
      if (_cancelled) {
        throw const AppError(AppErrorKind.cancelled, '已中止。');
      }
      throw AppError(
        AppErrorKind.network,
        '流式读取中断，网络可能不稳定。',
        detail: e.toString(),
      );
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  /// 「测试连接」按钮：发一个最小请求，只验证 Key / 端点 / 模型名是否可用。
  ///
  /// 返回 null 表示成功，否则返回可读的错误。
  Future<String?> testConnection({
    required AppConfig config,
    required String apiKey,
    String workspaceId = '',
  }) async {
    if (apiKey.trim().isEmpty) return '还没有填 API Key。';

    final url = Providers.chatCompletionsUrl(config, workspaceId: workspaceId);
    final body = <String, dynamic>{
      'model': config.modelName.trim().isEmpty
          ? Providers.byId(config.apiProvider).defaultModel
          : config.modelName.trim(),
      'messages': <Map<String, String>>[
        <String, String>{'role': 'user', 'content': '回复两个字：就绪'},
      ],
      'stream': false,
      'max_tokens': 16,
    };
    if (Providers.supportsThinkingSwitch(config.modelName)) {
      body['enable_thinking'] = false;
    }

    final client = http.Client();
    try {
      final resp = await client
          .post(
            Uri.parse(url),
            headers: <String, String>{
              'Authorization': 'Bearer ${apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) return null;
      return AppError.fromStatus(resp.statusCode, resp.body).message;
    } on TimeoutException {
      return '连接超时（25 秒），请检查网络。';
    } catch (e) {
      return '连接失败：$e';
    } finally {
      client.close();
    }
  }
}
