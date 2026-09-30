# Android ARM64 Release 构建

## 当前配置

- 应用名称：PiliNara；仓库：[JIANGJINMOU/Pili](https://github.com/JIANGJINMOU/Pili)。
- `applicationId` / namespace：`com.example.pilinara`。
- ABI：仅 `arm64-v8a`；不提供 32 位 ARM 或 x86 安装包。
- 当前版本号以 `pubspec.yaml` 为准。修改包名不会自动迁移另一个包的数据。
- 本地验证环境使用 Flutter **3.47.5** / Dart **3.13.4**；依赖中含定制的 material_ui、GetX 和 media-kit，不要随意替换为官方同名依赖。
- Android 配置使用 compileSdk / targetSdk **37**、AGP **9.1.0**、Gradle Wrapper **9.5.0**，JDK 路径通过 `flutter doctor -v` 检查。Java/Kotlin 字节码目标为 17，NDK 版本跟随 Flutter 配置。

## 准备与验证

安装 Flutter、Git、Android SDK 及兼容 JDK，接受 SDK 许可证。首次获取 Git/Maven/pub 依赖需要联网。
Windows 建议使用较短的仓库、Flutter 和缓存路径，以减少原生构建的长路径问题。

```sh
git clone https://github.com/JIANGJINMOU/Pili.git
cd Pili
flutter doctor -v
flutter pub get
flutter test test/short_video_comment_sheet_test.dart test/short_video_settings_test.dart test/playback_lifecycle_speed_test.dart test/short_video_recommendation_test.dart
flutter analyze lib/pages/short_video lib/pages/setting/widgets/fixed_speed_setting.dart lib/pages/setting/models/short_video_settings.dart lib/utils/fixed_playback_speed.dart test/short_video_comment_sheet_test.dart test/short_video_settings_test.dart test/playback_lifecycle_speed_test.dart test/short_video_recommendation_test.dart
```

保留仓库中的 `pubspec.lock`，使用 Gradle Wrapper；不要把开发机的 `local.properties`、缓存、账号信息或签名材料提交到仓库。
上游 CI 含额外的 Flutter SDK 调整；修改 SDK 或升级依赖后，需要重跑手势和面板测试，不能只凭构建成功判断兼容。

## 签名

`android/app/build.gradle.kts` 优先读取 `android/key.properties`；未提供时会回退到本机 Android Debug 签名证书。
**Release 构建模式与签名证书是两回事**：回退签名的 APK 仍是 Release，但不应把该证书当作正式发布密钥。
需要稳定覆盖安装时，应妥善保存并持续使用同一发布密钥。以下仅为占位配置，不包含真实密钥：

```properties
storeFile=/absolute/path/to/release.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

`android/key.properties` 和 `*.jks` 已忽略。不要提交密码、私钥或 keystore，也不要为了安装失败就直接卸载旧应用。

## 构建与检查

```sh
flutter build apk --release --target-platform android-arm64
```

输出：`build/app/outputs/flutter-apk/app-release.apk`。不要使用 `--debug` 或开发用 `dev` Gradle 属性，否则应用标识/构建类型可能不同。

使用 Android SDK Build Tools 检查安装包（Windows 使用对应 `.exe` / `.bat`）：

```sh
aapt dump badging build/app/outputs/flutter-apk/app-release.apk
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

核对包名 `com.example.pilinara`、版本号、`native-code: 'arm64-v8a'`，并确认没有 `application-debuggable`。
还应检查 ZIP 的 `lib/` 中仅有 `arm64-v8a`，原生入口为 `com.example.pilinara.MainActivity`。

## 安装与真机验收

- `com.examole.pili` 是旧测试包标识，与当前包是两个独立应用，不会自动迁移数据。
- 相同包名覆盖安装需要签名一致、版本满足安装规则。不同来源 APK 不保证可以直接覆盖；先备份再处理安装冲突。
- 本仓库只做本地构建/测试时，不代表 GitHub Releases 已发布新 APK。
- 真机至少验证：快速/反向滑动、连续播放、评论与子评论滚动/返回、断网重试、通知栏与锁屏恢复、手动暂停、临时/固定倍速、清除推荐记录，以及关闭移动网络预加载。
- 自动化测试使用假的网络响应和原生播放器，不能替代实际设备的网络、解码、耗电或帧耗时检查。
