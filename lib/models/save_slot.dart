import 'chapter_node.dart';
import 'world_book.dart';
import 'world_line.dart';
import 'world_state.dart';

/// 一个存档槽 = 一本世界书 + **若干条世界线**。
///
/// 2026-09-25 改：以前一个槽只有一条线（`history` / `chronicle` / `worldState`
/// 全在顶层），「回滚」靠**销毁**后面的幕实现，只留一个会被下次覆盖的备份槽。
///
/// 现在改成**多世界线**：从某一幕分岔出一条新线，原来的线原样保留，
/// 玩家可以随时在多条线之间查看和切换，各线的进度与选择记录互不干扰。
///
/// 存档里**内嵌世界书快照**，所以即使之后世界书被改或被删，
/// 老存档依然能完整打开。
class SaveSlot {
  final String id;
  String title;
  WorldBook worldBook;

  /// 所有世界线。**永不为空**（构造时会兜一条主线）。
  List<WorldLine> lines;

  /// 当前所在的世界线 id。
  String activeLineId;

  DateTime createdAt;
  DateTime updatedAt;

  SaveSlot({
    required this.id,
    required this.title,
    required this.worldBook,
    List<WorldLine>? lines,
    String? activeLineId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : lines = (lines == null || lines.isEmpty)
            ? <WorldLine>[WorldLine(id: WorldLine.newId(), name: '主线')]
            : lines,
        activeLineId = activeLineId ?? '',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now() {
    // 保证 activeLineId 一定指向一条真实存在的线 ——
    // 存档损坏或线被删掉时不至于崩，也不会出现「没有当前线」的中间态。
    if (!this.lines.any((l) => l.id == this.activeLineId)) {
      this.activeLineId = this.lines.first.id;
    }
  }

  static String newId() => WorldLine.newId();

  /// 回滚前自动备份的槽位用这个前缀。
  ///
  /// ⚠️ 2026-09-25：世界线分支上线后**不再产生新的备份** ——
  /// 分支本身就保留了原线，不需要备份。这个前缀只用于识别与清理旧数据。
  static const String backupIdPrefix = 'backup_';

  static String backupIdFor(String slotId) => '$backupIdPrefix$slotId';

  /// 这是不是一份旧版的自动备份（而非用户真实在玩的推演）。
  bool get isBackup => id.startsWith(backupIdPrefix);

  // ---------- 当前世界线 ----------

  WorldLine get activeLine {
    for (final l in lines) {
      if (l.id == activeLineId) return l;
    }
    return lines.first;
  }

  /// 切换当前世界线。
  void switchTo(String lineId) {
    if (lines.any((l) => l.id == lineId)) {
      activeLineId = lineId;
      updatedAt = DateTime.now();
    }
  }

  /// 分岔出来的线（不含主线）。
  List<WorldLine> get branches =>
      lines.where((l) => l.isBranch).toList();

  // ---------- 便捷访问：绝大多数地方只关心「当前这条线」 ----------

  List<ChapterNode> get history => activeLine.history;

  String get chronicle => activeLine.chronicle;

  WorldState get worldState => activeLine.worldState;

  int get chapterCount => activeLine.chapterCount;

  /// 最近一次落定的日期，用于列表页展示。
  String get latestDate => activeLine.latestDate;

  // ---------- 序列化 ----------

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'worldBook': worldBook.toJson(),
        'lines': lines.map((e) => e.toJson()).toList(),
        'activeLineId': activeLineId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SaveSlot.fromJson(Map<String, dynamic> json) {
    final wbRaw = json['worldBook'];
    final createdAt = DateTime.tryParse((json['createdAt'] ?? '').toString());
    final updatedAt = DateTime.tryParse((json['updatedAt'] ?? '').toString());

    return SaveSlot(
      id: (json['id'] ?? '').toString().isNotEmpty
          ? json['id'].toString()
          : newId(),
      title: (json['title'] ?? '未命名推演').toString(),
      worldBook: wbRaw is Map
          ? WorldBook.fromJson(Map<String, dynamic>.from(wbRaw))
          : WorldBook.blank(),
      lines: _parseLines(json, createdAt: createdAt, updatedAt: updatedAt),
      activeLineId: json['activeLineId']?.toString(),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 解析世界线。
  ///
  /// **旧存档迁移**：v1 的存档没有 `lines` 字段，`history` / `chronicle` /
  /// `worldState` 全在顶层。这里把它们原样包成一条叫「主线」的世界线 ——
  /// 老玩家打开旧档不会丢进度，也不需要额外的迁移步骤。
  static List<WorldLine> _parseLines(
    Map<String, dynamic> json, {
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final raw = json['lines'];
    if (raw is List && raw.isNotEmpty) {
      final parsed = raw
          .whereType<Map>()
          .map((e) => WorldLine.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (parsed.isNotEmpty) return parsed;
    }

    final wsRaw = json['worldState'];
    return <WorldLine>[
      WorldLine(
        id: WorldLine.newId(),
        name: '主线',
        history: (json['history'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) => ChapterNode.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            <ChapterNode>[],
        chronicle: (json['chronicle'] ?? '').toString(),
        worldState: wsRaw is Map
            ? WorldState.fromJson(Map<String, dynamic>.from(wsRaw))
            : WorldState(),
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
    ];
  }

  /// 列表页用的摘要行。
  String get summaryLine {
    final parts = <String>[
      worldBook.name,
      '第 $chapterCount 幕',
      if (lines.length > 1) '${lines.length} 条世界线',
      if (latestDate.isNotEmpty) latestDate,
    ];
    return parts.join(' · ');
  }
}
