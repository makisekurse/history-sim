import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/world_book_repository.dart';
import '../../models/world_book.dart';
import '../../services/file_export_service.dart';

/// 世界书编辑器。
///
/// 所有字段都由用户填写 —— 应用不提供任何预设剧本。
class WorldBookEditorScreen extends StatefulWidget {
  final WorldBook book;

  /// 是否为「AI 生成后的预览」—— 只是换个措辞，落库时机由调用方决定。
  final bool isPreview;

  const WorldBookEditorScreen({
    super.key,
    required this.book,
    this.isPreview = false,
  });

  @override
  State<WorldBookEditorScreen> createState() => _WorldBookEditorScreenState();
}

class _WorldBookEditorScreenState extends State<WorldBookEditorScreen> {
  late TextEditingController _name;
  late TextEditingController _era;
  late TextEditingController _worldview;
  late TextEditingController _playerRole;
  late TextEditingController _style;
  late TextEditingController _rules;
  late TextEditingController _opening;
  late TextEditingController _choices;
  late TextEditingController _goal;
  late TextEditingController _characters;
  late TextEditingController _factions;
  late TextEditingController _locations;
  late TextEditingController _dimensions;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _name = TextEditingController(text: b.name);
    _era = TextEditingController(text: b.era);
    _worldview = TextEditingController(text: b.worldview);
    _playerRole = TextEditingController(text: b.playerRole);
    _style = TextEditingController(text: b.narrativeStyle);
    _rules = TextEditingController(text: b.extraRules);
    _opening = TextEditingController(text: b.openingScene);
    _choices = TextEditingController(text: b.openingChoices.join('\n'));
    _goal = TextEditingController(text: b.playerGoal);
    _characters = TextEditingController(text: b.keyCharacters);
    _factions = TextEditingController(text: b.keyFactions);
    _locations = TextEditingController(text: b.keyLocations);
    _dimensions = TextEditingController(text: b.stateDimensions);
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _name,
      _era,
      _worldview,
      _playerRole,
      _style,
      _rules,
      _opening,
      _choices,
      _goal,
      _characters,
      _factions,
      _locations,
      _dimensions,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  WorldBook _collect() => widget.book.copyWith(
        name: _name.text.trim().isEmpty ? '未命名世界书' : _name.text.trim(),
        era: _era.text.trim(),
        worldview: _worldview.text.trim(),
        playerRole: _playerRole.text.trim(),
        narrativeStyle: _style.text.trim(),
        extraRules: _rules.text.trim(),
        openingScene: _opening.text.trim(),
        openingChoices: _choices.text
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        playerGoal: _goal.text.trim(),
        keyCharacters: _characters.text.trim(),
        keyFactions: _factions.text.trim(),
        keyLocations: _locations.text.trim(),
        stateDimensions: _dimensions.text.trim(),
      );

  Future<void> _save() async {
    final book = _collect();
    await WorldBookRepository.upsert(book);
    if (!mounted) return;
    Navigator.of(context).pop(book);
  }

  Future<void> _export() async {
    final book = _collect();
    final json = book.exportToJson();
    final ts = FileExportService.formatTimestamp();
    final safeName = FileExportService.sanitizeFileName(book.name);
    final fileName = '拟境_世界书_${safeName}_$ts.json';

    final res = await FileExportService.exportFile(
      fileName: fileName,
      content: json,
      mimeType: 'application/json',
    );
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          res.success
              ? '世界书已保存至：${res.path}\n（已同时复制到剪贴板）'
              : '保存失败：${res.message}（已复制到剪贴板）',
        ),
        action: SnackBarAction(
          label: '系统分享',
          onPressed: () => FileExportService.shareText(
            title: '世界书 · ${book.name}',
            text: json,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('世界书'),
        actions: <Widget>[
          IconButton(
            tooltip: '导出 JSON',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _export,
          ),
          TextButton(
            onPressed: _save,
            child: Text(widget.isPreview ? '确认并保存' : '保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: <Widget>[
          _field(
            _name,
            '世界书名',
            '例如：决胜西南1949',
            required: true,
          ),
          _field(_era, '时代与跨度', '例如：1949年10月 - 1952年7月'),
          _field(
            _worldview,
            '世界观与背景设定',
            '时代背景、局势、主要矛盾、地理与制度环境……模型据此推演',
            maxLines: 8,
            required: true,
          ),
          _field(
            _playerRole,
            '你扮演的人物',
            '身份、职务、年龄、性格、立场，例如「西南局第一书记，45岁」',
            maxLines: 4,
            required: true,
          ),
          _field(
            _goal,
            '玩家目标',
            '这一局你想做什么、想验证什么。例如「尽量遵循历史，但允许自己的选择改变后续走向」',
            maxLines: 3,
          ),
          _field(
            _style,
            '叙事文风',
            '例如：白描为主，沉稳遒劲，多用军情电报与公文语气；或：冷峻谍战笔法',
            maxLines: 3,
          ),
          _field(
            _rules,
            '世界规则与禁忌',
            '你不希望出现的内容，或必须遵守的设定',
            maxLines: 4,
          ),
          _field(
            _characters,
            '关键人物（选填）',
            '一行一位：姓名 | 身份 | 立场。留空则由模型自行发挥',
            maxLines: 5,
          ),
          _field(
            _factions,
            '关键势力（选填）',
            '一行一方：名称 | 诉求 | 与主角的关系',
            maxLines: 4,
          ),
          _field(
            _locations,
            '关键地点（选填）',
            '一行一处：地名 | 意义',
            maxLines: 4,
          ),
          _field(
            _dimensions,
            '状态维度模板（选填）',
            '告诉模型每一幕的「当前世界状态」该盯住哪些维度。'
                '留空则用通用五维：时间 / 地点 / 已知事实 / 人物关系 / 进行中事件',
            maxLines: 3,
          ),
          _field(
            _opening,
            '开篇场景（选填）',
            '留空则由模型根据世界观自动起笔',
            maxLines: 5,
          ),
          _field(
            _choices,
            '开篇分支（选填，一行一条）',
            '留空则第一幕的分支也由模型生成',
            maxLines: 4,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Text(
              '带 * 的是必填项。保存后回到首页新建推演即可开始。\n'
              '世界书只保存在本机；导出 JSON 后可以分享给别人导入。',
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    int maxLines = 2,
    bool required = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 2 : 1,
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            hintText: hint,
            alignLabelWithHint: true,
          ),
        ),
      );
}
