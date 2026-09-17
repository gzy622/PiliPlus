# 项目构建基线

## 环境与工具链

- 本机已验证可构建 Android APK：release（2026-06-13、2026-09-17，后者基于 Flutter 3.47.1）与 debug（2026-07-31、2026-08-22，基于 Flutter 3.47.1）均成功。
- 工具链：Flutter 3.47.1、Dart 3.13.1、JDK 21、Gradle 9.5.0、Android SDK 36、NDK 28.2.13676358、CMake 3.22.1。
- 本机 Flutter 位于 `C:\tools\flutter-3.47.1`，Android SDK 位于 `C:\Android`。
- `flutter`、`dart`、Android SDK 未加入系统环境变量时，`scripts/build_android_local.ps1` 仍能通过本机候选路径找到工具链，并在构建进程内设置 `ANDROID_HOME` 与 `ANDROID_SDK_ROOT`。
- 构建脚本必须兼容 Windows PowerShell 5.1（双击运行）：调用 Java、Flutter 等原生命令时局部放宽错误流处理并依据退出码判断，避免 stderr 在全局 `Stop` 策略下触发 `NativeCommandError`。

## 构建流程

- 构建前置统一使用 `scripts/prep_build.ps1`：自动定位 Flutter、校验含所需 NDK 的 Android SDK、设置 `FLUTTER_ROOT`/`GITHUB_WORKSPACE`/`ANDROID_HOME`/`ANDROID_SDK_ROOT`，在现有 PATH 上追加 Flutter bin（不覆盖），并依次执行 `lib/scripts/patch.ps1 android` 与 `scripts/build_android_local.ps1`。`-SkipPatch` 跳过补丁；`-SkipBuild` 仅补丁不构建；`-Dev` 构建 dev 包名。
- 直接执行 Flutter 命令前，先运行 `scripts/prep_build.ps1 -SkipBuild`（即 `patch.ps1 android`），使上游依赖的 Flutter 与 `material_ui` 补丁生效。补丁后无需还原 `lib/scripts/{material,cupertino}/*.patch`（行尾规范化已在临时目录进行，不写回仓库）。
- 版本号 = 上游版本号 + 当前具体时间（如 `2.1.0.20260712.103800`），确保每次构建唯一且线性递增。APK 产物命名 `PiliPlus-<完整版本>-arm64-v8a.apk`。
- 未配置 `android/key.properties` 时，release APK 回退使用 Android Debug 证书签名；正式发布或稳定覆盖安装前必须配置独立 release keystore。

## 环境变量注意事项（本机终端与工具调用）

- 调用 Flutter/构建/补丁时，环境变量通过 PowerShell 内赋值或工具 `env` 参数传递；不要在 bash 命令里使用 `$env:` 前缀（bash 非 PowerShell）。
- 使用工具 `env` 参数时不要设置 `Path` 项（会整体覆盖系统 PATH，挤掉 `git`/`flutter`）；需要追加路径时在命令内用 `$env:Path='<项>;' + $env:Path`。

## Git 与版本库

- `upstream`（拉取）→ `https://github.com/bggRGjQaUbCoE/PiliPlus.git`；`origin`（推送）→ `https://github.com/gzy622/PiliPlus`；`upstream` 的推送 URL 已禁用。
- 初次 Git 化前的完整目录快照保留在分支 `baseline-local-2.0.9` 与标签 `local-baseline-2.0.9`。
- `flutter_inappwebview` 使用 pub.dev 发布的 `6.2.0-beta.3`；不要重新加入 Android 或 Windows Git 覆盖。旧 Git 依赖在 Windows Pub 缓存会因路径过长缺少 Java 文件；稳定版 `6.1.5` 的 Android 平台包不支持 AGP 9 的 ProGuard 配置。

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
- 合并前确保工作区干净、分支为 `main`；合并产生的兼容性修复应单独提交并在提交消息中注明修复原因。
- 已知问题：合并带入依赖升级时，`merge_upstream.ps1` 中的 `flutter pub get` 会解包出未打补丁的新版本依赖（2026-09-17 合并时 `material_ui` 由 1.2.0 升到 1.3.0），其后 analyze 会报大量 error，集中表现为 `StandardBottomSheet`、`BottomSheetDefaultsM3` 等未定义，以及 `hitTestBehavior`、`horizontalDragGestureRecognizer` 等命名参数不存在。
  - 处理：先运行 `scripts/prep_build.ps1 -SkipBuild` 重新打补丁（Flutter SDK 与 pub 缓存的 `material_ui`/`cupertino_ui`），再跑 `.\scripts\merge_upstream.ps1 -VerifyOnly`；这类报错与业务代码无关，不要据此改动代码。
- 已知差异：上游 CI 与本机都通过 `lib/scripts/patch.ps1`（本机经 `scripts/prep_build.ps1`）给 Flutter SDK 源码打补丁，但 `merge_upstream.ps1` 只做 `pub get`，不补打补丁（见上一条）；补丁暴露的成员若返回私有类型，外部库仍无法使用，合并后才会暴露编译错误。
  - `text_painter.patch` 暴露的 `TextPainter.layoutCache` 返回私有类型 `_TextPainterLayoutCacheWithOffset`，无法访问 `.lineMetrics`，应改用公开的 `computeLineMetrics()`。
  - 不要改动 `lib/utils/grid.dart` 中 `SliverGridLayout.layoutCache`（那是该类的自定义字段，与 TextPainter 无关）；哨兵检查只匹配 `textPainter.layoutCache` 与 `layoutCache?.lineMetrics`，避免误报。
- 合并后必须先通过 analyze 与 release 构建验证再提交；推送 `origin` 需人工确认。
