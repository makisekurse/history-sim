import '../models/annotation.dart';
import '../models/chapter_node.dart';
import '../models/save_slot.dart';
import '../models/world_state.dart';
import 'world_state_service.dart';

/// 一局推演的**状态与纯逻辑**，与 UI 完全解耦。
///
/// 从上千行的 ReaderScreen 里拆出来，好处是这些逻辑现在**可以单测** ——
/// 回滚一致性、reroll 状态恢复这类东西最容易出隐蔽 bug，
/// 靠手点界面根本测不出来。
///
/// 核心不变量（**三者必须永远处于同一个时间点**）：
/// `history` · `chronicle` · `worldState`
class GameSession {
  final SaveSlot slot;

  List<ChapterNode> history;
  String chronicle;
  WorldState worldState;
  List<String> choices;

  GameSession(this.slot)
      : history = List<ChapterNode>.from(slot.history),
        chronicle = slot.chronicle,
        worldState = slot.worldState.copy(),
        choices = slot.history.isEmpty
            ? <String>[]
            : List<String>.from(slot.history.last.choices);

  int get chapterCount => history.length;

  bool get isEmpty => history.isEmpty;

  String get worldName => slot.worldBook.name;

  /// 生成过程中先清空分支，避免用户点到上一轮的选项。
  void clearChoices() => choices = <String>[];

  /// 落定一幕：合并状态、写入快照。
  ///
  /// 快照（chronicleAfter / worldStateAfter）是回滚的基础 ——
  /// 只在存档顶层存一份「当前状态」是回滚不到历史幕的。
  ChapterNode appendChapter({
    required String content,
    required String playerAction,
    required String date,
    required List<String> choices,
    required List<GlossaryEntry> glossary,
    required List<CastEntry> cast,
    required String rawOutput,
    required String stateRaw,
    String? title,
  }) {
    // 模型只提出状态变化；校验、合并、截断都在这里做。
    final nextState = WorldStateService.merge(
      worldState,
      WorldStateService.parse(stateRaw),
    );

    final node = ChapterNode(
      chapterIndex: history.length + 1,
      title: title ?? '第 ${history.length + 1} 幕',
      content: content,
      playerAction: playerAction,
      date: date,
      choices: choices,
      glossary: glossary,
      cast: cast,
      rawOutput: rawOutput,
      chronicleAfter: chronicle,
      worldStateAfter: nextState,
    );

    history = <ChapterNode>[...history, node];
    worldState = nextState;
    this.choices = List<String>.from(choices);
    return node;
  }

  /// 世界书自带开篇时，直接落第一幕（不走模型）。
  ChapterNode seedOpening({
    required String content,
    required String date,
    required List<String> choices,
  }) {
    final node = ChapterNode(
      chapterIndex: 1,
      title: '第一幕',
      content: content,
      date: date,
      choices: choices,
      chronicleAfter: chronicle,
      worldStateAfter: worldState.copy(),
    );
    history = <ChapterNode>[node];
    this.choices = List<String>.from(choices);
    return node;
  }

  /// 编年史被压缩后，把它记到最后一幕的快照上 ——
  /// 否则回滚到这一幕时，编年史会停留在「未来」的版本。
  void attachChronicle(String updated) {
    chronicle = updated;
    if (history.isNotEmpty) {
      history[history.length - 1] =
          history.last.copyWith(chronicleAfter: updated);
    }
  }

  /// 回滚到第 [index] 幕（index 从 0 起），之后的内容全部丢弃。
  ///
  /// ⚠️ history / chronicle / worldState **三者必须回到同一个时间点**，
  /// 否则模型会「记得」那些已经被撤销的未来。
  void rollbackTo(int index) {
    if (index < 0 || index >= history.length) return;
    final target = history[index];

    history = history.sublist(0, index + 1);
    // 旧存档没有快照字段：保守地沿用当前值 ——
    // 宁可不回退，也不要串线到未来。
    if (target.chronicleAfter != null) {
      chronicle = target.chronicleAfter!;
    }
    if (target.worldStateAfter != null) {
      worldState = target.worldStateAfter!.copy();
    }
    choices = List<String>.from(target.choices);
  }

  /// 弹出最后一幕以便重新生成，并把状态恢复到**这一幕之前**。
  ///
  /// ⚠️ 不恢复的话，第二次生成会继承第一次留下的状态
  /// （例如「张某已死」还在），状态就脏了。
  ///
  /// 返回被弹出的那一幕；history 为空时返回 null。
  ChapterNode? popLastForReroll() {
    if (history.isEmpty) return null;
    final last = history.last;

    history = history.sublist(0, history.length - 1);
    final prev = history.isEmpty ? null : history.last;

    if (prev == null) {
      // 回到开局
      worldState = WorldState();
      chronicle = '';
      choices = <String>[];
    } else {
      if (prev.chronicleAfter != null) chronicle = prev.chronicleAfter!;
      if (prev.worldStateAfter != null) {
        worldState = prev.worldStateAfter!.copy();
      }
      choices = List<String>.from(prev.choices);
    }
    return last;
  }

  /// 当前分支是否值得备份（和上次备份的起点不同才值得）。
  bool shouldBackupOver(int? existingBackupChapters) =>
      history.isNotEmpty && existingBackupChapters != history.length;

  /// 生成一个备份存档（**单槽覆盖**，避免连续回滚堆出一堆重复存档）。
  SaveSlot buildBackup({required String backupId, DateTime? createdAt}) =>
      SaveSlot(
        id: backupId,
        title: '【回滚备份】${slot.title}',
        worldBook: slot.worldBook,
        history: List<ChapterNode>.from(history),
        chronicle: chronicle,
        worldState: worldState.copy(),
        createdAt: createdAt ?? DateTime.now(),
      );

  /// 把当前状态写回存档对象（调用方负责持久化）。
  SaveSlot toSlot() {
    slot.history = history;
    slot.chronicle = chronicle;
    slot.worldState = worldState;
    return slot;
  }

  /// 塞进 system prompt 的世界状态文本。
  String get worldStateForPrompt =>
      WorldStateService.renderForPrompt(worldState);
}
