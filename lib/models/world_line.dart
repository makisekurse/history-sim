import 'chapter_node.dart';
import 'world_state.dart';

/// 一条世界线。
///
/// 玩家在某一幕发现走错了，可以从那一幕**分岔**出一条全新的世界线：
/// 保留分岔点之前的剧情，从分岔点重新做选择。
///
/// 原来那条线**原样保留** —— 这正是它和旧「回滚」的根本区别：
/// 回滚是单向销毁（丢掉后面的幕，只留一个会被下一次覆盖的备份槽），
/// 分支是**保留并新增**，多条线各走各的、互不干扰。
///
/// ⚠️ 每条线**自带** `history` / `chronicle` / `worldState` 三件套。
/// 三者必须永远处于同一个时间点 —— 这是整个引擎的核心不变量。
class WorldLine {
  final String id;

  /// 展示名，例如「主线」「世界线 2」。
  String name;

  List<ChapterNode> history;

  /// 编年史滚动摘要（这条线自己的）。
  String chronicle;

  /// 当前世界状态（这条线自己的）。
  WorldState worldState;

  /// 从哪条线分出来的。null = 开局就有的主线。
  final String? parentLineId;

  /// 分岔点：从第几幕分出来（1-based）。主线为 0。
  final int branchedAtChapter;

  /// **分岔点之前**的世界状态。
  ///
  /// 用途：在分岔点那一幕点「重新生成本幕」时，状态要退回这里，
  /// 而不是退成空 —— 否则这条线会丢掉分岔时继承来的全部局势。
  /// 主线恒为空状态。
  WorldState baseState;

  /// **分岔点之前**的编年史。主线恒为空串。
  String baseChronicle;

  final DateTime createdAt;
  DateTime updatedAt;

  WorldLine({
    required this.id,
    required this.name,
    List<ChapterNode>? history,
    this.chronicle = '',
    WorldState? worldState,
    this.parentLineId,
    this.branchedAtChapter = 0,
    WorldState? baseState,
    this.baseChronicle = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : history = history ?? <ChapterNode>[],
        worldState = worldState ?? WorldState(),
        baseState = baseState ?? WorldState(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 进程内自增序号。见 [newId]。
  static int _seq = 0;

  /// 生成一个唯一 id。
  ///
  /// ⚠️ **不能只用 `microsecondsSinceEpoch`** —— Windows 上 `DateTime.now()`
  /// 的实际分辨率只有约 1ms（系统计时器粒度），同一毫秒内连续调用会
  /// **返回完全相同的值**。
  ///
  /// 2026-09-25 实测踩到：新建存档时给主线生成的 id，和紧接着分岔出来的
  /// 新世界线 id **撞号**了。两条线 id 相同 → `activeLine` 按 id 查找时
  /// 永远返回第一条 → 切到新线后读到的还是旧线的进度。
  ///
  /// 拼一个进程内自增序号即可保证唯一（跨进程重启由时间戳区分）。
  static String newId() {
    _seq++;
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$t-${_seq.toRadixString(36)}';
  }

  int get chapterCount => history.length;

  bool get isEmpty => history.isEmpty;

  /// 最近一幕的剧中日期，列表页展示用。
  String get latestDate => history.isEmpty ? '' : history.last.date;

  /// 这是不是分岔出来的线（主线不是）。
  bool get isBranch => parentLineId != null;

  /// 深拷贝。切换/分岔时用它，避免两条线共享同一个 List 或 WorldState。
  WorldLine copy({
    String? id,
    String? name,
    List<ChapterNode>? history,
    String? chronicle,
    WorldState? worldState,
    DateTime? updatedAt,
  }) =>
      WorldLine(
        id: id ?? this.id,
        name: name ?? this.name,
        history: history ?? List<ChapterNode>.from(this.history),
        chronicle: chronicle ?? this.chronicle,
        worldState: worldState ?? this.worldState.copy(),
        parentLineId: parentLineId,
        branchedAtChapter: branchedAtChapter,
        baseState: baseState.copy(),
        baseChronicle: baseChronicle,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'history': history.map((e) => e.toJson()).toList(),
        'chronicle': chronicle,
        'worldState': worldState.toJson(),
        'parentLineId': parentLineId,
        'branchedAtChapter': branchedAtChapter,
        'baseState': baseState.toJson(),
        'baseChronicle': baseChronicle,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WorldLine.fromJson(Map<String, dynamic> json) {
    final wsRaw = json['worldState'];
    final baseRaw = json['baseState'];
    return WorldLine(
      id: (json['id'] ?? '').toString().isNotEmpty
          ? json['id'].toString()
          : newId(),
      name: (json['name'] ?? '主线').toString(),
      history: (json['history'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => ChapterNode.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          <ChapterNode>[],
      chronicle: (json['chronicle'] ?? '').toString(),
      worldState: wsRaw is Map
          ? WorldState.fromJson(Map<String, dynamic>.from(wsRaw))
          : WorldState(),
      parentLineId: json['parentLineId']?.toString(),
      branchedAtChapter: (json['branchedAtChapter'] as num?)?.toInt() ?? 0,
      baseState: baseRaw is Map
          ? WorldState.fromJson(Map<String, dynamic>.from(baseRaw))
          : WorldState(),
      baseChronicle: (json['baseChronicle'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
    );
  }
}
