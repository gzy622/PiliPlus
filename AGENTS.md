# 项目构建基线

- 已于 2026-06-13 在 Windows 11 上验证 Android release APK 可成功构建。
- Git 远程 `upstream` 指向 `https://github.com/bggRGjQaUbCoE/PiliPlus.git`，本地 `main` 基于上游正式版本标签并叠加本地定制提交。
- 初次 Git 化前的完整目录快照保留在分支 `baseline-local-2.0.9` 和标签 `local-baseline-2.0.9`。
- 项目使用 Flutter 3.44.2、Dart 3.12.2、JDK 17、Gradle 9.5.0、Android SDK 36 和 NDK 28.2.13676358。
- 本机 Flutter 位于 `C:\tools\flutter`，Android SDK 位于 `C:\Android`。
- `flutter`、`dart` 和 Android SDK 未加入系统环境变量时，项目脚本 `scripts/build_android_local.ps1` 仍可通过本机候选路径找到工具链，并在构建进程内设置 `ANDROID_HOME` 与 `ANDROID_SDK_ROOT`。
- 构建脚本必须兼容双击时使用的 Windows PowerShell 5.1。调用 Java、Flutter 等原生命令时，应局部放宽错误流处理并依据退出码判断，不能让 stderr 输出在全局 `Stop` 策略下触发 `NativeCommandError`。
- 直接执行 Flutter 命令前需要为当前终端设置 `ANDROID_HOME=C:\Android` 和 `ANDROID_SDK_ROOT=C:\Android`，或运行 `flutter config --android-sdk C:\Android`。
- 已验证的构建命令：

  ```powershell
  $env:ANDROID_HOME='C:\Android'
  $env:ANDROID_SDK_ROOT='C:\Android'
  C:\tools\flutter\bin\flutter.bat build apk --release --target-platform android-arm64 --split-per-abi --dart-define-from-file=pili_release.json --no-pub
  ```

- 未配置 `android/key.properties` 时，release APK 会回退使用 Android Debug 证书签名。用于正式发布或稳定覆盖安装前必须配置独立 release keystore。

# 首页搜索框显示规则

- 外观设置中的“隐藏首页搜索框”默认关闭，修改后重启应用生效。
- 隐藏首页搜索框时必须保留原搜索框的 `Expanded` 和 44dp 高度占位，确保右侧消息按钮、头像及顶部栏整体布局位置不变。
- “隐藏首页搜索框”沿用旧版备份键 `hideHomeSearchBar`，不要改名，以保证设置导入兼容。
- 外观设置中的“隐藏‘我的’页搜索按钮”默认关闭，修改后重启应用生效；隐藏时保留 48dp 宽度占位，确保其余顶部按钮位置不变。

# Codex 与 Reasonix 协作

- Codex 负责判断是否委派、定义验收条件、审查 Reasonix 的改动，并执行最终测试、修正和交付。
- Reasonix 是中低风险任务的主执行者，可独立完成代码搜索、调用链分析、候选方案、机械性修改、局部功能实现和初步测试。
- 优先整块委派“定位、修改、初测、报告”，不要把同一任务拆成多轮零碎问答。预计不能替代明显的 Codex 阅读或实现工作时，不调用 Reasonix。
- Reasonix 的任务必须明确目标、允许修改范围、禁止事项、验收命令和输出格式；不得自行扩大范围。
- Reasonix 默认直接修改工作区并返回不超过 30 行的交付报告，至少包含修改文件、关键依据、已运行检查、失败项和剩余风险。
- Codex 优先审查 diff 和证据，不重复完整探索 Reasonix 已处理的源码；只有证据不足、风险较高或测试失败时才重新深入读取。
- 核心架构、安全敏感逻辑、签名与密钥、发布操作、破坏性文件操作和 Git 写操作不得交给 Reasonix。
- Reasonix 可运行与任务直接相关的分析、单元测试和局部构建作为初步验证；完整发布构建和最终验收仍由 Codex 执行。
- 本机 Reasonix 的 `bash` 工具当前解析为 Git Bash。访问 Windows 路径时使用 `/c/...` 形式；需要执行项目 PowerShell 脚本时显式调用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <脚本>`。
- 项目级 Reasonix 工具与权限配置位于 `reasonix.toml`。旧版迁移 MCP 已停用，避免无关工具启动和上下文成本。
