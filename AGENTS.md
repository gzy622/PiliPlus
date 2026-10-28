# 项目构建基线

## 环境与工具链

- 本机已验证可构建 Android APK：release（2026-06-13、2026-09-17、2026-09-25，后两者基于 Flutter 3.47.1）与 debug（2026-07-31、2026-08-22，基于 Flutter 3.47.1）均成功。
- 2026-10-10 同步上游 `c2205a0ff` / 2.1.6.1：Flutter 3.47.7（Dart 3.13.5）下 analyze 无 error，arm64 release APK 构建成功，APK 签名校验通过；未做设备运行验证。
- 2026-10-28 同步上游 `628290b5c`：Flutter 3.47.8（Dart 3.13.7）下 analyze 无 error，arm64 release APK 构建成功，APK 签名校验通过；未做设备运行验证。
- 当前 Flutter 为 3.47.8、Dart 为 3.13.7；Gradle 9.5.0、NDK 28.2.13676358、CMake 3.22.1。此次 APK 的 compile/target SDK 为 37，最低 API 为 24。构建脚本检查到 `JAVA_HOME` 为 JDK 21，但此次 Gradle 实际使用 Android Studio 自带的 JBR 25.0.3；尚未验证本次合并在 JDK 21 下构建。
- 当前本机 Flutter 位于 `C:\tools\flutter-3.47.8`，旧 `C:\tools\flutter-3.47.7` 和 `C:\tools\flutter-3.47.1` 保留；此次构建实际选择 Android SDK `C:\Users\VG622\AppData\Local\Android\Sdk`，`C:\Android` 仍为候选路径。
- `flutter`、`dart`、Android SDK 未加入系统环境变量时，`scripts/build_android_local.ps1` 仍能通过本机候选路径找到工具链，并在构建进程内设置 `ANDROID_HOME` 与 `ANDROID_SDK_ROOT`。
- 构建脚本必须兼容 Windows PowerShell 5.1（双击运行）：调用 Java、Flutter 等原生命令时局部放宽错误流处理并依据退出码判断，避免 stderr 在全局 `Stop` 策略下触发 `NativeCommandError`。

## 构建流程

- 构建前置统一使用 `scripts/prep_build.ps1`：自动定位 Flutter、校验含所需 NDK 的 Android SDK、设置 `FLUTTER_ROOT`/`GITHUB_WORKSPACE`/`ANDROID_HOME`/`ANDROID_SDK_ROOT`，在现有 PATH 上追加 Flutter bin（不覆盖），并依次执行 `lib/scripts/patch.ps1 android` 与 `scripts/build_android_local.ps1`。`-SkipPatch` 跳过补丁；`-SkipBuild` 仅补丁不构建；`-Dev` 构建 dev 包名。
- 直接执行 Flutter 命令前，先运行 `scripts/prep_build.ps1 -SkipBuild`（即 `patch.ps1 android`），使上游依赖的 Flutter 与 `material_ui` 补丁生效。补丁后无需还原 `lib/scripts/{material,cupertino}/*.patch`（行尾规范化已在临时目录进行，不写回仓库）。
- 版本名称 = 上游版本号 + 当前具体时间（如 `2.1.6.2.20261028.215329`），确保每次构建唯一且线性递增。Android `versionCode` 使用构建日期 `YYYYMMDD`，同一天的多次构建数值相同。APK 产物命名 `PiliPlus-<完整版本>-arm64-v8a.apk`。
- 未配置 `android/key.properties` 时，release APK 回退使用 Android Debug 证书签名；正式发布或稳定覆盖安装前必须配置独立 release keystore。

## 环境变量注意事项（本机终端与工具调用）

- 调用 Flutter/构建/补丁时，环境变量通过 PowerShell 内赋值或工具 `env` 参数传递；不要在 bash 命令里使用 `$env:` 前缀（bash 非 PowerShell）。
- 使用工具 `env` 参数时不要设置 `Path` 项（会整体覆盖系统 PATH，挤掉 `git`/`flutter`）；需要追加路径时在命令内用 `$env:Path='<项>;' + $env:Path`。

## Git 与版本库

- `upstream`（拉取）→ `https://github.com/bggRGjQaUbCoE/PiliPlus.git`；`origin`（推送）→ `https://github.com/gzy622/PiliPlus`；`upstream` 的推送 URL 已禁用。
- 初次 Git 化前的完整目录快照保留在分支 `baseline-local-2.0.9` 与标签 `local-baseline-2.0.9`。
- `flutter_inappwebview` 使用 pub.dev 发布的 `6.2.0-beta.3`；不要重新加入 Android 或 Windows Git 覆盖。旧 Git 依赖在 Windows Pub 缓存会因路径过长缺少 Java 文件；稳定版 `6.1.5` 的 Android 平台包不支持 AGP 9 的 ProGuard 配置。
- `media_kit` 系列依赖的仓库 / path / ref 以 PiliPlus 上游（`upstream/main`）的 `dependency_overrides` 配置为准，上游升级时随之同步，不再固定回旧的 `My-Responsitories` 来源；仅在真实编译或运行失败时定位具体 API，再决定是否偏离上游。
  - 当前（上游 `628290b5c`）：`media_kit_video` → `bggRGjQaUbCoE/media-kit` `native`（1.2.5 / `85f0a6`），其余 6 包 → `My-Responsitories/media-kit` `native`（`73771e`；其中核心 `media_kit` 为 1.1.11，其余包版本按上游锁文件）。
  - 分支警示（当前有效，非永久规则）：**当前**不可单独把某个包切到 `upstream` 分支（1.2.6）。上游 partial revert 后的业务代码按 `native` 分支 API 编写（`Initializer.create` 需要首个 `mpv` 参数、`NativePlayer.setHeader` 为静态方法），与 `upstream` 分支混用会编译失败；`native` 分支不含 `stream-lavf-o` 重连参数。该警示只约束「单独换分支」，不限制仓库来源跟随上游；若将来上游变更分支/版本，应连同业务代码的 API 调用一并同步升级，不得引用本条历史规则去恢复旧来源或旧分支。

# 首页搜索框显示规则

- 外观设置中的“隐藏首页搜索框”默认关闭，修改后重启应用生效。
- 隐藏首页搜索框时必须保留原搜索框的 `Expanded` 和 44dp 高度占位，确保右侧消息按钮、头像及顶部栏整体布局位置不变。
- “隐藏首页搜索框”沿用旧版备份键 `hideHomeSearchBar`，不要改名，以保证设置导入兼容。
- 外观设置中的“隐藏‘我的’页搜索按钮”默认关闭，修改后重启应用生效；隐藏时保留 48dp 宽度占位，确保其余顶部按钮位置不变。

# 修改版标识

- “关于”页必须始终显示“当前为自制修改版”提示。
- 检测到上游新版本并展示更新弹窗时，必须提醒升级官方版本会丢失本地定制功能；无更新或检查失败时不额外打扰。

# 同步上游与合并验证

- 同步上游的标准流程是运行 `scripts/merge_upstream.ps1`：拉取 upstream → merge-tree 预检 → 合并 → 已知 API 哨兵检查 → `flutter pub get` → `flutter analyze`（仅以 `error -` 行为失败判定，info 不致命）→ release APK 构建。
- 同步上游/合并类任务必须交付 release APK：构建走 `scripts/build_android_local.ps1`，产物为 `build/app/outputs/flutter-apk/PiliPlus-<完整版本>-arm64-v8a.apk`（同时复制到桌面），只做 debug 验证不算完成。
- 手动解决合并冲突后，用 `.\scripts\merge_upstream.ps1 -VerifyOnly` 重跑验证（跳过拉取/预检/合并）；`-SkipBuild` 可跳过最后的 release 构建（仅限静态检查场景，交付 APK 前不得使用）。
- 通过规定的 analyze 和 release 构建后，直接交付通过验证的 APK，不为提交后更新包内提交号而再次构建。提交前构建的 APK 所记录的提交号可能仍是合并前的 HEAD，应如实说明；若代码、依赖或构建配置在验证后发生影响构建的变更，或用户明确要求重建，则重新构建。
- analyze 已通过且没有影响分析结果的新改动时，不为审查或确认 info 提示数量重复运行；分析失败、存在需要核实的具体问题、相关内容发生变化或用户明确要求时，再运行必要的检查。
- 合并前确保工作区干净、分支为 `main`；合并产生的兼容性修复应单独提交并在提交消息中注明修复原因。
- 已知问题：合并带入依赖升级时，`merge_upstream.ps1` 中的 `flutter pub get` 会解包出未打补丁的新版本依赖（2026-09-17 合并时 `material_ui` 由 1.2.0 升到 1.3.0），其后 analyze 会报大量 error，集中表现为 `StandardBottomSheet`、`BottomSheetDefaultsM3` 等未定义，以及 `hitTestBehavior`、`horizontalDragGestureRecognizer` 等命名参数不存在。
  - 处理：先运行 `scripts/prep_build.ps1 -SkipBuild` 重新打补丁（Flutter SDK 与 pub 缓存的 `material_ui`/`cupertino_ui`），再跑 `.\scripts\merge_upstream.ps1 -VerifyOnly`；这类报错与业务代码无关，不要据此改动代码。
  - 上游会同时更新补丁文件本身：2026-09-25 合并时 `material_ui` 由 1.3.0 升到 1.4.0，`lib/scripts/material/tabs.patch` 同步更新为 1.4.0 的行号（旧补丁在 1.4.0 上直接 `patch does not apply`）。因此重打补丁必须用合并后的补丁文件，顺序为先合并、再 `prep_build.ps1 -SkipBuild`（它会先删除缓存中最新版本的 `material_ui`，再由 `pub get` 重新解包并打补丁）。
- 已知差异：上游 CI 与本机都通过 `lib/scripts/patch.ps1`（本机经 `scripts/prep_build.ps1`）给 Flutter SDK 源码打补丁，但 `merge_upstream.ps1` 只做 `pub get`，不补打补丁（见上一条）；补丁暴露的成员若返回私有类型，外部库仍无法使用，合并后才会暴露编译错误。
  - `text_painter.patch` 暴露的 `TextPainter.layoutCache` 返回私有类型 `_TextPainterLayoutCacheWithOffset`，无法访问 `.lineMetrics`，应改用公开的 `computeLineMetrics()`。
  - 不要改动 `lib/utils/grid.dart` 中 `SliverGridLayout.layoutCache`（那是该类的自定义字段，与 TextPainter 无关）；哨兵检查只匹配 `textPainter.layoutCache` 与 `layoutCache?.lineMetrics`，避免误报。
- 合并后必须先通过 analyze 与 release 构建验证再提交；推送 `origin` 需人工确认。
