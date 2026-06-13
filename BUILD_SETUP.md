# PiliPlus 本地构建说明 🏗️

这个脚本帮你把 PiliPlus 源码编译成 APK 安装包，装到自己手机上。

---

## 🚀 最简单用法（5 步）

```
1. 双击 scripts/build_android_local.ps1
2. 等 3-5 分钟（第一次会久一些，因为要下载依赖）
3. 看到 "构建成功" 的框框
4. 把 APK 传到手机上（QQ/微信/数据线/网盘）
5. 在手机上点 APK 文件安装
```

> **构建产物位置**：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
>
> **脚本会自动输出**：APK 路径、大小、SHA256、版本号、包名

---

## ✅ 你需要先装什么

### 1. Java 17（JDK）
安装 Eclipse Temurin 17：
```
winget install "Eclipse Temurin JDK with Hotspot 17"
```
装完后**设置环境变量** `JAVA_HOME` 指向安装目录（如 `C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot\`）。

### 2. Flutter 3.44.2
安装 FVM（Flutter 版本管理器）：
```
winget install fvm
```
然后在项目目录运行：
```
fvm install 3.44.2
fvm use 3.44.2
```

### 3. Android SDK
安装 [Android Studio](https://developer.android.com/studio)，然后在 SDK Manager 里安装 Android SDK。

设置环境变量 `ANDROID_HOME`，指向 SDK 目录（通常是 `%LOCALAPPDATA%\Android\Sdk`）。

---

## 🔄 修改代码后重新构建

改了代码后，再次双击 `scripts/build_android_local.ps1` 即可。

脚本会自动：
- 重新获取依赖
- 应用本机环境修复
- 编译新版 APK
- 输出新 APK 的信息

---

## ⚠️ 常见问题

| 问题 | 原因 | 解决 |
|---|---|---|
| 找不到 `JAVA_HOME` | 没装 JDK 17 或没设环境变量 | 安装 JDK 17，设置 `JAVA_HOME` 环境变量 |
| 找不到 `Flutter SDK` | 没装 FVM 或 Flutter | 运行 `fvm install 3.44.2 && fvm use` |
| 找不到 `Android SDK` | 没设 `ANDROID_HOME` | 装 Android Studio，设置 `ANDROID_HOME` |
| 构建时报网络错误 | 下载依赖超时 | 检查网络/代理/VPN，重试 |
| 构建失败提示 `TLS` | 本机网络环境问题 | 脚本会自动修复，重试即可 |

---

## 🔧 本机环境修复说明

以下修复是脚本自动执行的，只影响你的**本机构建环境**，不改项目源码：

| 修复 | 干什么 | 为什么需要 |
|---|---|---|
| TLS 握手修复 | 改 `android/gradle.properties` 的 JVM 参数 | Windows 上某些 JDK 17 版本 HTTPS 连接有问题 |
| Git 长路径 | `git config core.longpaths true` | Windows 路径超过 260 字符时 Git 会报错 |
| 插件文件恢复 | 从 Git 恢复被删除的源文件 | Flutter 的 `pub get` 在 Windows 上偶尔会误删文件 |
| 原生库预下载 | 用 `curl` 预先下载 jar 文件 | Gradle 的 `URL.openStream()` 在本机网络环境下可能超时 |

---

## 📂 项目文件说明（了解即可）

| 文件/目录 | 干什么的 |
|---|---|
| `pubspec.yaml` | 项目配置（版本号、依赖） |
| `android/` | Android 相关配置 |
| `lib/` | 源码 |
| `build/` | 编译产物（APK 在这里） |
| `build/local_jars/` | 预下载的原生库（自动生成） |

---

## 🔒 安全提示

- 不要提交 `key.properties`、`*.jks`、`local.properties` 到 Git。
- 项目 `.gitignore` 已经自动排除这些文件。
- `android/key.properties.example` 是个模板，你如果要签名就复制它改。
