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

## 2.1.5.12（12）版本约定

`pubspec.yaml` 使用合法的 `2.1.5+12`；Android 将版本名与构建号组合为 `2.1.5.12`，versionCode 为 `12`。竖屏底栏提供弹幕/字幕开关、当前可用清晰度、倍速、静音、独立详情和全屏入口；评论仍由右侧评论按钮打开。竖屏设置仅保留固定倍速开关，倍率在播放器底栏选择。

竖屏设置现在可调整独立弹幕开关、字号、不透明度和显示区域。底栏全屏入口使用旧旋转图标，传入当前进度并复用详情页的全屏播放器。原生临时错误在初始化完成后观察 3 秒，只有没有恢复进度才显示失败，并按 1、2、4 秒间隔最多重试三次；缓冲且连续 12 秒无有效进度时触发恢复，刷新地址并恢复原进度和可用清晰度。后台、手动暂停或打开详情时停止自动重试，达到上限后可手动重试或滑到下一条，不再自动跳片。

评论不再固定半屏：横屏视频按实际宽高比贴顶完整显示，评论紧接画面；竖屏画面最高占屏幕 42%。从标题或顶部拖柄向下拖动可关闭；楼中楼左右滑入/滑出，返回保留主评论位置和草稿，首评随回复一起滚动。键盘弹起时重新分配画面与评论空间。设置新增默认清屏播放，双击临时恢复控件。字幕与弹幕独立，仅对当前视频按需加载，优先中文，暂无字幕或请求失败分别提示；字幕错误不会重启视频。

评论面板与视频视口共享打开/关闭动画，下拉时联动恢复，键盘弹起时视频适配剩余区域，播放器与进度不变。清屏保留右上角“退出清屏”，系统返回键也先退出清屏并关闭默认设置。首次加载/失败/正常播放统一返回按钮，去掉重叠导航；冷启动首个有效元数据批次返回后即开始播放，不等待填满推荐池。

普通详情页播放器顶栏新增竖屏入口（遵循竖屏功能总开关）。入口携带当前 aid/bvid/cid 与毫秒进度，从当前视频/分P继续播放，而不是随机打开推荐。先暂停详情播放并抑制自动画中画，返回详情后由现有路由生命周期恢复；已有竖屏页面时重置其当前选择并返回该页面，避免重复创建推荐控制器。手动选择不受推荐的“仅竖向”过滤影响，后续仍按推荐规则追加。

评论遮罩透明，打开评论不再叠加视频暗层；点击画面空白仍可关闭评论，不穿透触发视频暂停。竖屏设置 → 画面与手势新增“显示系统顶部状态栏”，默认关闭；开启仅显示顶部时间、电量、通知图标。设置返回、详情返回和前后台恢复会重新应用，退出竖屏恢复普通系统栏。


### 字幕与画面显示

- 竖屏设置按「基础播放 / 画面与手势 / 字幕设置 / 弹幕设置 / 网络与推荐」分组。移除顶部「你的竖屏体验」及副标题；固定倍速仍只有开关。
- 「画面比例」提供原始比例、16:9、4:3、1:1、9:16；「画面适配」提供完整显示、铺满裁切、拉伸铺满。默认仍为原始比例 + 完整显示，旧 `shortVideoFill=true` 不触发裁切。固定比例会改变宽高，裁切隐藏边缘，拉伸可能变形；恢复默认即可完整显示。
- 视频和加载封面同步使用显示选项；比例变化不重建播放器、不重新请求播放地址。评论缩放按当前显示比例计算。
- 字幕支持优先语言、顶部/居中/底部位置、12–28px 字号、背景不透明度、白/黄/青颜色、粗体、阴影、左/中/右对齐及最多 2/3/4/6 行。展开「字幕样式」可预览效果；小视口限制文字高度，避免评论缩小后溢出。
- 移除竖屏设置里的「AI 字幕翻译」和「AI 服务配置」；读取旧配置时强制停用竖屏 AI 翻译，避免隐藏开关继续外发字幕。不改动普通 AI 设置和账号配置。字幕语言选项只选择视频已有轨道，不生成翻译或语音字幕。
- 四组回归共 135 项通过，另有 1 项界面截图测试通过。覆盖默认无裁切、比例/适配持久化与即时应用、字幕样式和位置保存、旧翻译开关停用、小视口多行字幕、窄屏深色大字体布局。
- 真机新增验收：分别切换比例和适配方式并恢复默认，打开/下拉关闭评论，确认画面及进度连续；字幕选择位置、颜色、字号和行数后退出设置，检查横竖视频与清屏模式。模拟测试与截图不代表真实手机解码和手感验收。

### 进度拖动与直接全屏

- 竖屏底部进度条使用本地拖动预览，时间与滑块即时跟手；松手才向播放器提交跳转，快速连续操作串行处理并保留最新目标，避免旧进度回报造成回弹。水平拖动锁定翻页，取消手势不跳转；从进度条开始竖向滑动仍可正常切视频。
- 全屏按钮复用普通播放器与原有控件，但从首帧就铺满全屏，不再先显示详情页再放大。加载时可返回，失败可重试；退出全屏直接回到竖屏，保留同一分P的播放进度，原先手动暂停不会强制自动播放。独立「详情」入口不变。
- 回归测试覆盖拖动预览、原生进度迟到、松手单次跳转、连续请求合并、取消手势、未知时长、翻页互斥及全屏首帧/加载失败界面。四组测试共 135 项通过；模拟播放器结果不代表真机验收。
- 真机新增验收：反复左右拖动进度条后松手、拖动中下拉通知栏、从进度条向上翻页；播放/暂停状态分别进入全屏并返回；加载中返回及断网重试，确认不闪详情页、不串音且进度保留。
