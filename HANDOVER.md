# 《决胜西南1949》沉浸式移动端文字沙盘推演系统 - 项目交接全景文档

> **文档创建时间**：2026-09-25 03:02  
> **项目存储唯一绝对路径**：`D:\Gemini\06_代码工程\deng_1949_rpg\`  
> **交接目标**：供后续接手的 AI Agent 快速无缝接盘，直接执行出包、测试与后续功能迭代。

---

## 一、 项目背景与核心需求

1. **产品定位**：
   - 专为手机端打造的**纯文学第一人称沉浸式大历史沙盘推演游戏**。
   - **绝对零 HUD**：摒弃血条、金币、属性面板等破坏代入感的传统游戏 UI，全屏呈现精装历史小说阅读质感，具备字号调节与三大纸质主题（时代报章、暗夜墨石、素雅宣纸）。
   - **双模交互**：每一幕由大模型（或离线沙盘）生成一段白描张力极强的剧情段落，结尾动态生成 2~3 个战略抉择分支胶囊，同时提供一个全自由意志输入框供玩家自创行动推进。

2. **首发剧本设定**：
   - **剧本名**：《决胜西南1949：主政大西南与建政风云》
   - **代入身份**：**邓小平同志**（中共中央西南局第一书记、中国人民解放军第二野战军政治委员，时年45岁）。
   - **历史跨度**：1949年10月至1952年（大迂回进军西南、解放川黔滇康、重庆入城与金融保卫战、成都接管与30万旧军队整编、西南大剿匪与清剿袍哥、开建成渝铁路、经略雪域西藏）。

3. **技术路线**：
   - 选用 **Flutter 独立轻量安卓 App**。
   - 手机直接联网直连大模型 API（无需电脑开着 Python 或查局域网 IP），脱离电脑独立运行。

---

## 二、 完整源码结构与核心文件导览

工程根目录位于：[`D:\Gemini\06_代码工程\deng_1949_rpg\`](file:///D:/Gemini/06_%E4%BB%A3%E7%A0%81%E5%B7%A5%E7%A8%8B/deng_1949_rpg/)

```text
D:\Gemini\06_代码工程\deng_1949_rpg\
├── pubspec.yaml                     # 项目依赖 (http, shared_preferences, cupertino_icons)
├── android/
│   ├── app/
│   │   ├── build.gradle.kts         # Android 应用配置 (已配置 ndkVersion, compileSdk)
│   │   └── src/main/AndroidManifest.xml # 已添加 INTERNET 网络权限与应用标签
│   └── gradle.properties            # 关键编译修复参数 (见下文)
└── lib/
    ├── main.dart                    # 入口：沉浸式状态栏与主题初始化
    ├── models/
    │   ├── chapter_node.dart        # 章节剧情节点与选项模型
    │   └── game_config.dart         # 用户设置模型 (API Key, WorkspaceId, 主题, 字号)
    ├── scenarios/
    │   └── deng_1949_scenario.dart  # 1949 邓小平经略大西南内置剧本与高质感离线沙盘推演树
    ├── services/
    │   ├── llm_service.dart         # 统一大模型流式接口 (深度适配阿里云百联与防审查包装)
    │   └── storage_service.dart     # SharedPreferences 本地持久化存储 (实时存盘防丢失)
    └── ui/
        ├── screens/
        │   ├── story_reader_screen.dart # 核心零 HUD 全屏小说阅读流视口 (打字机流式渐现)
        │   └── settings_drawer.dart     # 侧边配置抽屉 (百联参数、主题切换、全文章节复制导出)
        ├── themes/
        │   └── app_theme.dart           # 时代报章(赭红)、暗夜墨石、素雅宣纸三大阅读皮肤
        └── widgets/
            ├── choice_pill_button.dart  # 动态抉择分支胶囊卡片
            └── custom_action_bar.dart   # 玩家自由意志长句输入栏
```

---

## 三、 阿里云百联 (DashScope) 官方 API 对齐规范

代码在 [`lib/services/llm_service.dart`](file:///D:/Gemini/06_%E4%BB%A3%E7%A0%81%E5%B7%A5%E7%A8%8B/deng_1949_rpg/lib/services/llm_service.dart) 与 [`lib/ui/screens/settings_drawer.dart`](file:///D:/Gemini/06_%E4%BB%A3%E7%A0%81%E5%B7%A5%E7%A8%8B/deng_1949_rpg/lib/ui/screens/settings_drawer.dart) 中已完全对齐用户提供的百联官方技术文档：

1. **协议规范**：OpenAI 兼容模式 (`/chat/completions`)。
2. **请求头**：`Authorization: Bearer <DASHSCOPE_API_KEY>`，`Content-Type: application/json`。
3. **请求体**：
   ```json
   {
     "model": "qwen3.8-max",
     "messages": [
       {"role": "system", "content": "学术唯物史观元叙事包装Prompt..."},
       {"role": "user", "content": "..."}
     ],
     "stream": true,
     "temperature": 0.85
   }
   ```
4. **Base URL 与 WorkspaceId 智能解析**：
   - 华北2（北京）地域若填入业务空间 ID，自动拼接：`https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`；
   - 通用默认端点：`https://dashscope.aliyuncs.com/compatible-mode/v1`；
   - 同时也保留了 DeepSeek 与自定义端点切换。
5. **防审核机制**：Prompt 开篇注入学术沙盘与历史唯物主义文学演化包装（Meta-Framing），防止国内模型针对敏感政治人物被动拒答。

---

## 四、 本机编译环境与三大关键坑点修复记录

### 1. 宿主环境路径
- **Flutter 路径**：`D:\dev\flutter\bin\flutter.bat` (Flutter 3.47.5 stable)
- **Java 路径**：`D:\dev\jdk17\bin\java.exe` (JDK 17)
- **Android SDK 路径**：`D:\dev\android-sdk`
- **Gradle 缓存路径**：`D:\dev\gradle-home`
- **NDK 路径**：`D:\dev\android-sdk\ndk\28.2.13676358`

### 2. 已解决的三大编译深坑（极其重要，避免重复踩坑！）
1. **Windows 中文路径拦截**：
   - *问题*：工程位于 `D:\Gemini\06_代码工程\`，AGP 默认拦截非 ASCII 路径报错。
   - *修复*：已在 `android/gradle.properties` 添加 `android.overridePathCheck=true`。
2. **NDK 缺失与 sdkmanager 闪退**：
   - *问题*：Flutter 3.47 默认强制要求 NDK `28.2.13676358`，Gradle 调用旧版 `sdkmanager.bat` 发生 0xC0000409 异常。
   - *修复*：已在宿主使用 `android sdk install "ndk/28.2.13676358"` 完整下载并解压了 2.1GB 官方 NDK，`D:\dev\android-sdk\ndk\28.2.13676358\source.properties` 已经就绪。
3. **Kotlin 跨盘符增量编译相对路径异常**：
   - *问题*：工程位于 `D:` 盘，而 pub 缓存在 `C:` 盘，Kotlin 增量编译器内部调用 `relativeTo()` 报 `different roots` 错误导致 `:shared_preferences_android:compileDebugKotlin` 失败。
   - *修复*：已在 `android/gradle.properties` 添加：
     ```properties
     kotlin.incremental=false
     kotlin.incremental.jvm=false
     ```
     彻底禁用跨盘符增量计算，改为干净利落的全量编译。

---

## 五、 构建成果与直接交付状态（已构建完毕！）

> **重大更新**：本项目的最终 APK 已经于 2026-09-25 03:02:43 **全量编译成功（Exit Code 0）**！接手的 Agent 或用户无需再次执行编译，安装包已就位。

### 1. 最终安装包直接交付路径：
- **最便捷根目录产物**：[`D:\Gemini\06_代码工程\决胜西南1949.apk`](file:///D:/Gemini/06_%E4%BB%A3%E7%A0%81%E5%B7%A5%E7%A8%8B/%E5%86%B3%E8%83%9C%E8%A5%BF%E5%8D%971949.apk)
- **编译原生目录产物**：[`D:\Gemini\06_代码工程\deng_1949_rpg\build\app\outputs\flutter-apk\app-debug.apk`](file:///D:/Gemini/06_%E4%BB%A3%E7%A0%81%E5%B7%A5%E7%A8%8B/deng_1949_rpg/build/app/outputs/flutter-apk/app-debug.apk)

### 2. 手机安装与游玩指南：
1. 直接将电脑中的 [`决胜西南1949.apk`](file:///D:/Gemini/06_%E4%BB%A3%E7%A0%81%E5%B7%A5%E7%A8%8B/%E5%86%B3%E8%83%9C%E8%A5%BF%E5%8D%971949.apk) 通过微信文件传输助手、QQ、网盘或 USB 数据线发到安卓手机上；
2. 手机点击安装包直接安装（安装后桌面生成名为“决胜西南1949”的独立 App）；
3. 打开后即刻进入 1949 邓小平经略大西南推演现场，支持离线试玩与百联 API 在线推演！
