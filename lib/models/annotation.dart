/// 随文注释与人物条目。
///
/// 两者都由**模型在每一幕的输出里附带**，应用不做任何本地预设词表 ——
/// 这样任何题材的世界书都能自动获得注释与人物志，不需要为每个剧本维护数据。
class GlossaryEntry {
  final String term;
  final String explanation;

  const GlossaryEntry({required this.term, required this.explanation});

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'term': term, 'explanation': explanation};

  factory GlossaryEntry.fromJson(Map<String, dynamic> j) => GlossaryEntry(
        term: (j['term'] ?? '').toString(),
        explanation: (j['explanation'] ?? '').toString(),
      );

  /// 解析一行 `词条|解释`。
  static GlossaryEntry? parseLine(String line) {
    final idx = line.indexOf('|');
    if (idx <= 0) return null;
    final term = line.substring(0, idx).trim();
    final exp = line.substring(idx + 1).trim();
    if (term.isEmpty || exp.isEmpty) return null;
    return GlossaryEntry(term: term, explanation: exp);
  }
}

class CastEntry {
  final String name;
  final String role;
  final String stance;

  const CastEntry({
    required this.name,
    this.role = '',
    this.stance = '',
  });

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'name': name, 'role': role, 'stance': stance};

  factory CastEntry.fromJson(Map<String, dynamic> j) => CastEntry(
        name: (j['name'] ?? '').toString(),
        role: (j['role'] ?? '').toString(),
        stance: (j['stance'] ?? '').toString(),
      );

  /// 解析一行 `姓名|身份|立场`（后两段可缺）。
  static CastEntry? parseLine(String line) {
    final parts = line.split('|').map((e) => e.trim()).toList();
    if (parts.isEmpty || parts.first.isEmpty) return null;
    return CastEntry(
      name: parts[0],
      role: parts.length > 1 ? parts[1] : '',
      stance: parts.length > 2 ? parts[2] : '',
    );
  }

  /// 同一人物再次出现时，用新信息覆盖旧信息（不覆盖成空）。
  CastEntry merge(CastEntry other) => CastEntry(
        name: name,
        role: other.role.isNotEmpty ? other.role : role,
        stance: other.stance.isNotEmpty ? other.stance : stance,
      );
}
