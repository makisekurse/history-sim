# 拟境 · 交接文档

> **更新时间**：2026-09-25 17:00
> **仓库**：https://github.com/makisekurse/nijing （公开）
> **本地路径**：`D:\Gemini\06_代码工程\deng_1949_rpg\`（目录名是旧的，没跟着改名）
> **交接目标**：让接手的 Agent 不必重新摸索本机环境与历史坑点，直接能改代码、跑测试、出包发版。

---

## 一、这是什么

**拟境**（英文名 `nijing`，2026-09-25 由 `history-sim` 改名而来）是一个**世界书驱动的情境推演引擎**。

把自己放进一个世界，做一个行动，看这个世界如何回应。不是数值游戏 —— 没有血条、金币、属性面板。
全屏是长篇小说的阅读质感，每一幕由用户自己配置的大模型实时生成。

**应用零内置剧本。** 时代、身份、文风全部来自用户写的「世界书」。历史正剧、架空江湖、近未来都市都能跑。

- **开发者署名**：`makisekurisu`（用户明确要求只署他一个人）
- **包名**：`io.github.makisekurse.nijing`
- **应用显示名**：拟境

---

## 二、代码结构

```
lib/
├── main.dart                    入口：配置加载 + 主题注入 + 生命周期落盘
├── core/
│   ├── app_info.dart            应用常量（名称/版本/仓库地址，版本由构建期注入）
│   └── app_error.dart           错误分类
├── models/
│   ├── world_book.dart          世界书（12 个字段）
│   ├── world_line.dart          ★ 世界线：history + chronicle + worldState + 分岔来源
│   ├── save_slot.dart           ★ 存档槽 = 一本世界书 + 若干条世界线
│   ├── chapter_node.dart        一幕节点（含每幕状态快照）
│   ├── world_state.dart         结构化世界状态
│   ├── annotation.dart          词条 / 人物志条目
│   └── app_config.dart          全局配置（主题/字号/行距/排版/模型）
├── data/
│   ├── prefs_store.dart         SharedPreferences 封装（带写盘防抖 + flush）
│   ├── secure_store.dart        API Key 加密存储
│   └── world_book_repository.dart
├── services/
│   ├── game_session.dart        ★ 状态与纯逻辑：分岔/切换/快照自愈/reroll
│   ├── world_state_service.dart ★ 世界状态解析·合并·校验·截断
│   ├── response_parser.dart     ★ 模型输出解析（四步流水线 + 模板占位过滤）
│   ├── text_layout.dart         正文分段与缩进（可单测）
│   ├── prompt_builder.dart      提示词三层组装
│   ├── llm_client.dart          流式/非流式客户端
│   ├── fallback_service.dart    拒答与截断的三级兜底
│   ├── chronicle_service.dart   编年史压缩
│   ├── save_service.dart        存档读写
│   ├── world_builder_service.dart  AI 生成世界书
│   ├── providers.dart           服务商与模型清单
│   └── update_service.dart      检查更新
└── ui/
    ├── themes/app_theme.dart    四套皮肤 + ReadingPalette 阅读面色板
    ├── screens/
    │   ├── home_shell.dart      底部三入口：世界 / 继续 / 我的
    │   ├── worlds_tab.dart      世界列表
    │   ├── continue_tab.dart    继续你的故事
    │   ├── profile_tab.dart     我的
    │   ├── reader_screen.dart   ★ 阅读页（世界线管理在这里）
    │   ├── settings_screen.dart 设置（三个独立分区）
    │   ├── worldbook_editor_screen.dart
    │   ├── quick_create_screen.dart
    │   ├── chronicle_screen.dart / cast_screen.dart / about_screen.dart
    │   └── onboarding_screen.dart
    └── widgets/                 choice_pill / free_input_bar / glossary_sheet
```

规模：41 个 dart 文件 / 约 8850 行 / 86 项单测。

---

## 三、核心不变量（改代码前必读）

> **`history` · `chronicle` · `worldState` 三者必须永远处于同一个时间点。**

实现方式：`ChapterNode` 上的**每幕快照** —— `chronicleAfter` / `worldStateAfter`。

- 只在存档顶层存一份「当前状态」是**分岔不到历史幕**的（顶层那份永远是最新的）
- 分岔、reroll、编年史压缩三条路径都必须维护这个不变量
- 逻辑集中在 `lib/services/game_session.dart`，**有单测覆盖**，别绕过它直接改状态

### 快照自愈

旧存档可能缺快照（世界书自带开篇时，第一幕是在 UI 层直接构造的）。
`GameSession` 构造时调 `ensureSnapshots()` 自愈：缺快照的幕取上一幕的快照，
第一幕取空状态（它没跑过模型，状态本来就是空的 —— 对开篇场景是精确值）。

自愈**只在内存里做**，等用户下次正常保存时自然写回。

---

## 四、世界线机制（当前的核心特性）

### 数据模型

```
SaveSlot（= 一局推演）
├── worldBook          内嵌世界书快照（世界书被改/删也能打开）
├── lines: WorldLine[] 若干条世界线，**永不为空**
├── activeLineId       当前所在
└── createdAt / updatedAt

WorldLine（= 一条世界线）
├── history / chronicle / worldState   自带三件套 → 天然互不干扰
├── parentLineId / branchedAtChapter   从哪条线、第几幕分出来
└── baseState / baseChronicle          分岔点**之前**的状态
```

### 行为

```
主线        第1幕 ── 第2幕 ── 第3幕 ── 第4幕      ← 原样保留
                    │
世界线 2             └── 第2幕' ── 第3幕'          ← 重新做选择
```

- **分岔**：`GameSession.branchFrom(index)` —— 新线保留 1..index+1 幕，
  `chronicle`/`worldState` 恢复到那一幕的快照，并自动切过去。**原线完全不动**。
- **切换**：`switchLine(id)` —— 四件套整体换成那条线的。
- **重命名 / 删除**：`renameLine` / `deleteLine`（至少保留一条）。
- **`baseState` 的用途**：在分岔点那一幕点「重新生成本幕」时，状态要退回分岔点**之前**，
  而不是退成空 —— 否则这条线会丢掉分岔时继承来的全部局势。

> 早先的「回滚」是**单向销毁**：丢掉后面的幕，只留一个会被下次覆盖、
> 而且没有任何入口能再打开的备份槽。世界线分支取代了它。
> `SaveSlot.backupIdPrefix` / `isBackup` 保留着，仅用于识别与清理旧数据。

### 一本书一局

进入世界时如果这本书**已有存档就接着玩**，没有才新建。所以「最近推演」里一本书只有一条。
想重开走世界书长按菜单的「重新开始一局」（整槽重置成一条新主线，带确认）。

---

## 五、模型输出契约

模型每幕必须返回带标签的结构。**五个块全是元数据，读者不该看见**，只有正文进阅读区：

```
<date>剧中日期</date>

<choices>
可选行动一
可选行动二
</choices>

<glossary>
词条|解释
</glossary>

<cast>
姓名|身份|立场
</cast>

<state>
时间：… / 地点：… / 事实：…；… / 关系：姓名|态度；… / 事件：…；…
</state>
```

- 缺 `<choices>` → 判定截断 → 走三级兜底（`fallback_service.dart`）
- 解析在 `response_parser.dart`：标签定位 → 结构块切分 → 结构化提取 → 正文重建
- **不做过度正文清洗**：正文里的 `名字|身份|立场` 行只要不在结构块内就原样保留

### ⚠️ 提示词里绝不能出现可被照抄的内容行

这是踩过的坑：内核提示词原本写的是

```
<choices>
第一条可供主角决断的具体行动（一句话，30~60 字）
第二条可供主角决断的具体行动
第三条（可选）
</choices>
```

模型把这四行当成「格式的一部分」原样抄进了输出，界面上出现了
「第一条可供主角决断的具体行动（一句话，30~60 字）」混在真实选项里，
正文里也混进了「（正文：约 500 字的白描叙事）」。

**现在内核是「空骨架 + 散文说明」** —— 骨架里标签内部一律留空，
内容要求全部写在骨架之外。解析器再加一道 `isTemplateNoise` / `isBodyNoise` 兜底。
正文的过滤刻意比列表项**更窄**（正文是文学文本，宁可漏杀不能误杀 ——
`〈〉` 书名号在中文小说里合法，不在正文里过滤）。

**改提示词时务必守住这条。**

---

## 六、主题与阅读体验

四套皮肤（`ui/themes/app_theme.dart`）：

| id | 名称 | 定位 |
|---|---|---|
| `mirage` | 拟境 | 冷调深墨 + 雾蓝，**默认**，为沉浸式推演设计 |
| `vintage` | 时代报章 | 暖纸 + 砖红 |
| `dark` | 暗夜墨石 | 暖黑 + 橘调 |
| `parchment` | 素雅宣纸 | 亮白纸面 |

阅读页不用 Material 语义色，而是一套 **`ReadingPalette`**（ThemeExtension）：
页面底色 / 正文墨色 / 极淡分隔线 / 幕首标记色 / 选项卡底色。四套皮肤各自调过。

阅读设置里可调：主题、字号、行距、**段首缩进（顶格/一格/两格）**、
**段间距（紧凑/适中/宽松）**、打开时跳到最新一幕、顶栏自动隐藏。

### 段首缩进必须用 WidgetSpan，不能用空白字符

`TextLayout.indent()` 生成的 U+3000 前缀在实机上**不生效** ——
代码与配置链路都验过是对的，问题在文本排版层把行首空白吃掉了
（两端对齐时行首空白被当 hanging whitespace 处理）。

现在用 `WidgetSpan(child: SizedBox(width: n * fontSize))`：占位盒子是布局实体，
shaper 折叠不了它，缩进**必然**生效。见 `reader_screen.dart` 的 `_paragraph()`。

### 沉浸模式与手势

- 进推演页 `SystemChrome.setEnabledSystemUIMode(immersiveSticky)`，退出恢复 `edgeToEdge`
- 单击唤出顶栏用 **`Listener` 监听原始指针事件**（在手势竞技场之前触发，不会被
  `SelectionArea` 抢走），判断条件**只有一个：指针有没有拖动**。
  ⚠️ 别再加"是否有选中文字""落点是否在底部"之类的守卫 —— 加过一次，
  任一判断卡住就让顶栏彻底唤不出来。

---

## 七、本机环境与三大坑（极其重要）

### 工具链路径

| 项 | 路径 |
|---|---|
| Flutter | `D:\dev\flutter\bin\flutter.bat`（3.47.5 stable） |
| JDK | `D:\dev\jdk17` |
| Android SDK | `D:\dev\android-sdk` |
| Gradle 缓存 | `D:\dev\gradle-home` |
| 签名密钥 | `D:\workbuddy工作空间\测试签名密钥\test-signing.jks`，alias `anerycoft`，口令 `android` |
| GitHub Token | `D:\dev\ghtok.txt` |

### ⛔ 坑 1：卡巴斯基拦截命名管道 → 所有 flutter 命令必须提权

降权进程下 Dart 无法创建子进程管道，`flutter analyze/build/test` 全部秒崩，报
`CreateFile failed 231 (所有的管道范例都在使用中。)`。

**解决**：用 `D:\dev\elev_flutter.py <mode> <proj>` 提权执行（mode: pub/analyze/test/icons/build）。
日志写到 `D:\dev\elev_<mode>.log`。

### ⛔ 坑 2：Dart 分析器在中文路径下崩溃

工程路径含 `06_代码工程`，`flutter analyze` 会因 LSP 消息截断崩掉
（`FormatException: Unexpected end of input`）。

**解决**：用 ASCII 路径的目录联接 —— `D:\dev\nijing_verify` → 工程真实路径，
在这个联接路径下执行 flutter 命令。

### ⛔ 坑 3：工作文件夹无法在会话内改名

`deng_1949_rpg` 这个名字是旧的，但**改不动** —— WorkBuddy 自身持有目录句柄
（工作区根目录就是它），普通权限和提权都失败（`WinError 32`）。

⚠️ **更危险的是**：`shutil.move` 在 `os.rename` 失败后会走「复制再删除」兜底，
中断会留下残缺副本（实测留下过 2.5 GB 残骸）。
**不要用 `shutil.move` 兜底 rename，失败了就直接报错。**

---

## 八、出包与发版

### 本地构建

```bash
# 走提权包装器（坑 1），不要直接调 flutter
python D:\dev\elev_flutter.py build D:\dev\nijing_verify
```

⚠️ **必须显式 `--target-platform android-arm64`**：Flutter 的 Gradle 插件会绕过
`android` 里的 `ndk.abiFilters`，只用 abiFilters 的话三个 ABI 全都会打进包里
（实测 51 MB vs 18.8 MB）。脚本里已带。

### CI

`.github/workflows/android.yml`，**出包与发版分离**：

| 触发 | 行为 |
|---|---|
| 推 `main` / 手动 | 只构建 + 上传 Artifact，**不发版** |
| 推 `v*` 标签 | 构建 + **发布 Release**（这一步才算"发包"） |

版本号由 `Resolve version` 步骤决定：**推标签时以标签为准**，
推 main 时用 `run_number`（只增不减）。这样 Release 标签与包内 versionName 对得上。

仓库 Secret：`TEST_KEYSTORE_BASE64`（固定签名密钥的 base64）。
没配会退回 debug 签名 —— 那样每个包签名不同，无法覆盖安装。

### 交付规矩（用户明确要求）

1. 每次交付必须说清 **commit 短 SHA + 改了什么 + 版本号**
2. **版本号只增不减**
3. **不自己随便推** —— 用户说推才推
4. **默认只走 GitHub Release 给直链**，不要用本地文件发送
5. 签名必须固定，**禁止** `keytool -genkeypair` 现场生成
6. ⭐ **只要发包就必须同时更新 README** —— 顺序：改代码 → 改 README → 提交 → 打标签发版

---

## 九、测试

```bash
python D:\dev\elev_flutter.py test D:\dev\nijing_verify
```

**86 项，必须全过。** 覆盖四类最容易出隐蔽 bug 的地方：

- **世界线分岔与切换** —— 分岔后原线是否完全不动、新线是否继承到分岔点、
  两线是否互不干扰、切换后四件套是否跟着换、分岔点重生成是否退回 `baseState`
- **快照一致性** —— 三者是否同点、旧存档缺快照能否自愈
- **世界状态的解析、合并与截断** —— 畸形输入不抛异常、关系走增量、总预算兜底
- **模型输出解析与正文排版** —— 10 类畸形标签写法、模板占位过滤、正文分段

---

## 十、踩坑记录（后来的 Agent 优先看这里）

### 1. `DateTime.now()` 在 Windows 上分辨率只有约 1ms —— id 会撞号

`WorldLine.newId()` 原本是 `DateTime.now().microsecondsSinceEpoch.toRadixString(36)`。
同一毫秒内连续调用**返回完全相同的值**，于是新建存档时给主线生成的 id
和紧接着分岔出来的新世界线 id 撞号 → 两条线 id 相同 → `activeLine` 按 id 查找时
永远返回第一条 → **切到新线后读到的还是旧线的进度**。

**修法**：拼一个进程内自增序号。见 `world_line.dart` 的 `newId()`。

**通用教训：任何"用时间戳当唯一 id"的地方都要检查这个。**

### 2. 懒加载列表的 `maxScrollExtent` 首帧不可信

`ListView` 是懒加载的，首帧之后 `maxScrollExtent` 只反映**已经铺出来**的那部分，
直接 `jumpTo(maxScrollExtent)` 会落在半路。

**正解**：给目标挂 `GlobalKey`，先 `Scrollable.ensureVisible` 定位，下一帧再补一次到底。

### 3. 设置防抖写入从未落盘

`PrefsStore.flush()` 写了但**从来没被调用过**，也没有生命周期监听。
700ms 防抖窗口内退出应用，设置就丢了 —— 表现为「设置没生效」。

**修法**：离散选择（主题/字号/开关/选模型）改成立即落盘；
`main.dart` 加 `WidgetsBindingObserver`，在 paused/hidden/detached 时 flush 兜底。

### 4. 用"看不见"换"数得对"是错的

为了修「推演数量虚高」，把备份槽从列表里过滤掉了 —— 数量是准了，
但唯一的查看入口也堵死了。**该做的是给它一个正当的家，不是藏起来。**

### 5. 别用"保守兜底"掩盖数据缺失

`rollbackTo` 里原本有 `if (target.worldStateAfter != null)` 的守卫，
本意是"旧存档没快照就别回退"。但它把**数据缺失变成了静默跳过** ——
回滚后状态停在后来的幕，界面上完全看不出哪里错了。
**状态恢复路径上要么显式补齐，要么显式报错，不要静默。**

### 6. 两个看起来无关的现象，先找共同根因

「继续进入跳回第一幕」和「最近推演每进一次多一条」用户是分开报的，
实际是同一行代码（每次都 `SaveSlot.newId()` 建新槽）造成的。
**别分别打补丁。**

### 7. 守卫条件越加越糟

顶栏唤出加过两个"精确"守卫（有选中文字 / 落点在底部），
任一卡住就让功能彻底失效。**可靠性优先于精确性** ——
宁可偶尔多触发一次，也不要让功能彻底不能用。

---

## 十一、已知待办

- **`GameSession` 只拆了状态与纯逻辑**；流式渲染与交互仍在 `reader_screen.dart`（约 1400 行）。
  彻底的 controller 化（把流式也搬出去 + 改 setState 粒度）还没做 —— 纯重构，无用户可见收益。
- **世界线还没有跨槽的全局视图**。目前切换入口在阅读页的「世界线」里，
  从首页进不去。
- **没有截图**。README 有截图会好读很多。
- **屏幕常亮**（阅读时不息屏）没做 —— 需要引原生插件，一直没排期。
- **`verticalText`（竖排阅读）已删除**。它原本是假实现（只加大字距，不是真竖排排版）。
  要做真竖排得换渲染方式。

---

## 十二、给接手者的建议顺序

1. 先读 `lib/services/game_session.dart` 与 `lib/models/world_line.dart` —— 这是全局最核心的两块
2. 再读 `reader_screen.dart` 的 build + `_paragraph` + 世界线那几个方法
3. 跑一遍 `python D:\dev\elev_flutter.py test D:\dev\nijing_verify` 确认基线是绿的
4. 改完必须：`analyze` 零问题 → `test` 全过 → 更 README → 提交 → 打标签发版
