# 项目构建基线

- 已于 2026-06-13 在 Windows 11 上验证 Android release APK 可成功构建。
- Git 远程 `upstream`（拉取）指向 `https://github.com/bggRGjQaUbCoE/PiliPlus.git`，`origin`（推送）指向 `https://github.com/gzy622/PiliPlus`，`upstream` 的推送 URL 已禁用以防误操作。
- 初次 Git 化前的完整目录快照保留在分支 `baseline-local-2.0.9` 和标签 `local-baseline-2.0.9`。
- 项目使用 Flutter 3.44.2、Dart 3.12.2、JDK 21、Gradle 9.5.0、Android SDK 36 和 NDK 28.2.13676358。
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

# 修改版标识

- “关于”页必须始终显示“当前为自制修改版”提示。
- 检测到上游新版本并展示更新弹窗时，必须提醒升级官方版本会丢失本地定制功能；无更新或检查失败时不额外打扰。
