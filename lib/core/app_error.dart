/// 统一错误分类。
///
/// 旧版本在 `catch (e)` 里把异常整个吞掉，只给两句通用选项，
/// 用户永远不知道是 Key 错了、额度没了还是断网。现在所有网络/解析
/// 失败都必须先归类成 [AppError]，UI 才能给出可读提示。
enum AppErrorKind {
  /// 连不上 / DNS 失败 / 超时
  network,

  /// 401 / 403：Key 错、Key 被停用、无该模型权限
  auth,

  /// 429 或额度耗尽
  rateLimit,

  /// 5xx
  server,

  /// 模型拒答（内容审核拦截，返回空或只有致歉语）
  refused,

  /// 输出被截断（没有出现 <choices> 结构块）
  truncated,

  /// 返回体解析失败
  parse,

  /// 用户主动中止
  cancelled,

  unknown,
}

class AppError implements Exception {
  final AppErrorKind kind;

  /// 面向用户的中文说明，可直接显示。
  final String message;

  /// 原始信息，仅用于排查。
  final String? detail;

  final int? statusCode;

  const AppError(this.kind, this.message, {this.detail, this.statusCode});

  /// 是否值得自动重试。
  bool get retryable =>
      kind == AppErrorKind.network ||
      kind == AppErrorKind.server ||
      kind == AppErrorKind.rateLimit ||
      kind == AppErrorKind.truncated;

  /// 是否属于「模型不愿意说」—— 走兜底链路而不是单纯重试。
  bool get isRefusal =>
      kind == AppErrorKind.refused || kind == AppErrorKind.truncated;

  factory AppError.fromStatus(int statusCode, String body) {
    final brief = body.length > 300 ? '${body.substring(0, 300)}…' : body;
    if (statusCode == 401 || statusCode == 403) {
      return AppError(
        AppErrorKind.auth,
        'API Key 无效或没有该模型的调用权限，请在设置里核对 Key 与模型名。',
        detail: 'HTTP $statusCode · $brief',
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      return AppError(
        AppErrorKind.rateLimit,
        '请求过于频繁或额度已耗尽，稍后再试。',
        detail: 'HTTP 429 · $brief',
        statusCode: statusCode,
      );
    }
    if (statusCode >= 500) {
      return AppError(
        AppErrorKind.server,
        '模型服务端出错（$statusCode），已自动重试。',
        detail: 'HTTP $statusCode · $brief',
        statusCode: statusCode,
      );
    }
    if (statusCode == 400) {
      return AppError(
        AppErrorKind.auth,
        '请求被拒绝（400）：多为模型名不存在或参数不合法，请核对「模型代码」。',
        detail: 'HTTP 400 · $brief',
        statusCode: statusCode,
      );
    }
    return AppError(
      AppErrorKind.unknown,
      '接口返回异常状态 $statusCode。',
      detail: brief,
      statusCode: statusCode,
    );
  }

  @override
  String toString() => 'AppError(${kind.name}): $message';
}
