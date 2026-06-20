# PiliPlus — 代码架构地图

<div align="center">
  <img width="100" src="assets/images/logo/logo.png">
  <p><strong>使用 Flutter 开发的 BiliBili 第三方客户端</strong></p>
  <p><strong>⚠️ 自制修改版 — 包含本地定制功能</strong></p>
  <p>基于上游 v2.0.9 · Flutter 3.44.2 · Dart >=3.12.0 · GetX · media_kit</p>
  <p>版本 = 上游版本号 + 构建时间戳（如 <code>2.0.9.20260620.135050</code>）</p>
</div>

---

## 📋 目录

- [项目概览](#一项目概览)
- [应用启动链](#二应用启动链)
- [分层架构总览](#三分层架构总览)
- [网络层详解](#四网络层详解)
- [页面模块地图](#五页面模块地图)
- [播放器架构](#六播放器架构)
- [数据模型层](#七数据模型层)
- [服务层](#八服务层)
- [Utils 工具层](#九utils-工具层)
- [关键架构决策](#十关键架构决策)
- [Flutter 源码覆写](#十一flutter-源码覆写)
- [本地定制功能](#十二本地定制功能)
- [致谢](#致谢)

---

## 一、项目概览

| 属性 | 内容 |
|------|------|
| 项目名 | PiliPlus（自制修改版） |
| 上游 | [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) |
| 技术栈 | Flutter 3.44.2 / Dart >=3.12.0 |
| 状态管理 | GetX (GetMaterialApp + GetxController + Obx/Rx) |
| 播放引擎 | media_kit (libmpv) |
| 网络层 | Dio (REST) + 自研 Protobuf-over-HTTP (gRPC) |
| 持久化 | Hive CE (GetStorage 封装) |
| 代码量 | ~108 页面文件、28 REST 服务、7 gRPC 服务 |
| 平台 | ✅ Android · ✅ iOS · ✅ Pad · ✅ Windows · ✅ macOS · ✅ Linux |
| 版本号规则 | `<上游版本.日期.时间>`（如 `2.0.9.20260620.135050`），每次构建唯一 |

---

## 二、应用启动链

`lib/main.dart` 中的初始化顺序（CodeGraph 静态追踪验证）：

```
main()
├─ 1. ScaledWidgetsFlutterBinding.ensureInitialized()
├─ 2. MediaKit.ensureInitialized()              ← libmpv 引擎
├─ 3. _initAppPath()                            ← 应用目录
├─ 4. GStorage.init()                           ← Hive CE 本地存储
├─ 5. UI Scale = Pref.uiScale
├─ 6. Parallel: _initDownPath / _initTmpPath / CacheManager
├─ 7. Get.lazyPut(AccountService.new)
├─ 8. Get.lazyPut(DownloadService.new)
├─ 9. HttpOverrides.global                      ← 自定义证书
├─ 10. CacheManager.autoClearCache()
├─ 11. 平台初始化: orientation / webview / audio service
├─ 12. Request() 构造函数                        ← Dio 单例就绪
├─ 13. Request.setCookie() + RequestUtils.syncHistoryStatus()
├─ 14. SmartDialog 配置
├─ 15. 桌面端: windowManager 初始化 + 窗口位置恢复
├─ 16. DynamicColor (如启用)
├─ 17. runApp(const MyApp())
│
└─ MyApp (GetMaterialApp)
    └─ initialRoute: '/'
        └─ Routes.getPages
            └─ '/' → MainApp (底部导航壳)
                 ├─ /home    → HomePage       ← 首页推荐
                 ├─ /dynamics → DynamicsPage   ← 动态
                 ├─ /follow  → FollowPage      ← 关注
                 └─ /mine    → MinePage        ← 我的
```

**启动链关键观察：**
- `Get.lazyPut` 延迟注入服务，首次访问时才创建实例
- Dio 单例 (`Request`) 在 main 的后期初始化，此时存储/账号系统已就绪
- 桌面端在 `runApp` **之后**才异步初始化 `windowManager`，避免阻塞首帧

---

## 三、分层架构总览

```
┌───────────────────────────────────────────────────────────────────────┐
│                          UI Layer (Pages)                             │
│  主壳: lib/pages/main/view.dart (MainApp)                            │
│  ├─ 首页推荐   lib/pages/home/                                        │
│  ├─ 视频详情   lib/pages/video/          ← 最大模块 (~30 文件)        │
│  ├─ 直播间     lib/pages/live_room/                                   │
│  ├─ 搜索       lib/pages/search/ + search_panel/ + search_result/     │
│  ├─ 动态       lib/pages/dynamics/ + dynamics_detail/                 │
│  ├─ 用户空间   lib/pages/member/ + member_*/                          │
│  ├─ 私信       lib/pages/whisper/ + whisper_detail/                   │
│  ├─ 设置       lib/pages/setting/            ← ~20 子页面             │
│  └─ 更多 50+ 页: 番剧/收藏/历史/稍后再看/排行榜/订阅/音乐/文章...     │
│  模式: 每页三层 —— controller.dart + view.dart + widgets/              │
├───────────────────────────────────────────────────────────────────────┤
│                       Common / Widgets 层                              │
│  lib/common/widgets/                                                  │
│  ├─ badge / avatars / buttons / toast / tooltip / dialog              │
│  ├─ floating_navigation_bar (底部导航, 24063 bytes)                   │
│  ├─ draggable_sheet / dynamic_sliver_app_bar                          │
│  ├─ skeleton/                     ← 骨架屏组件                        │
│  └─ flutter/                      ← Flutter 原生组件覆写              │
│       ├─ text_field/              ← 大段覆写 (editable_text 272KB)   │
│       ├─ page/                    ← PageView / Scrollable 覆写        │
│       ├─ tabs.dart / list_tile.dart / refresh_indicator.dart          │
│       └─ text/                    ← RichText / Paragraph 覆写         │
├───────────────────────────────────────────────────────────────────────┤
│                      Network Layer                                    │
│  ┌─────────────────────────┐    ┌──────────────────────────────────┐  │
│  │  REST (Dio)             │    │  gRPC (Protobuf-over-HTTP)       │  │
│  │  lib/http/              │    │  lib/grpc/                       │  │
│  │                         │    │                                  │  │
│  │  Request 单例 ──────────┼────┤  GrpcReq.request()               │  │
│  │  (lib/http/init.dart)   │    │  内部调用 Request().post()        │  │
│  │                         │    │  + protobuf 编解码               │  │
│  │  28 个服务文件           │    │  7 个已迁移服务                   │  │
│  │  180+ REST 端点         │    │  15 个 proto 命名空间             │  │
│  └─────────────────────────┘    └──────────────────────────────────┘  │
├───────────────────────────────────────────────────────────────────────┤
│                       Models / Data 层                                 │
│  ├─ lib/models/              ← 手写 JSON 模型类                      │
│  │     common/ (枚举/常量 ~60 文件)                                   │
│  │     user/ member/ search/ dynamics/ home/ video/ login/            │
│  └─ lib/grpc/bilibili/       ← protoc 生成的 .pb.dart 模型           │
│        app/viewunite/ app/dynamic/ app/im/ app/playurl/               │
│        community/dm/ main/community/reply/ metadata/ ...              │
├───────────────────────────────────────────────────────────────────────┤
│                       Services 层                                      │
│  lib/services/                                                       │
│  ├─ account_service.dart     ← 账号生命周期管理                      │
│  ├─ audio_handler.dart       ← 后台音频播放 (AudioService)           │
│  ├─ audio_session.dart       ← 音频会话 (中断/耳机拔出)              │
│  ├─ download/                ← 下载服务 + 管理器                     │
│  ├─ shutdown_timer_service   ← 定时关机                              │
│  ├─ logger.dart              ← 日志记录                              │
│  └─ service_locator.dart     ← GetX 服务定位器                       │
├───────────────────────────────────────────────────────────────────────┤
│                     Plugin / Player 层                                 │
│  lib/plugin/pl_player/                                               │
│  ├─ controller.dart (55KB)   ← 核心控制器 (单例)                     │
│  ├─ view/view.dart (89KB)    ← 播放器 UI                             │
│  ├─ models/                  ← DataSource / 播放状态 / 全屏模式...    │
│  ├─ utils/                   ← 全屏工具 / 弹幕配置                   │
│  └─ widgets/                 ← 控制按钮 / 进度 / 画中画              │
├───────────────────────────────────────────────────────────────────────┤
│                       Utils 工具层                                     │
│  lib/utils/                                                          │
│  ├─ accounts/                ← 多账号管理、gRPC 请求头、Cookie        │
│  ├─ extension/               ← context_ext / theme_ext / num_ext 等  │
│  ├─ storage*.dart            ← Hive CE 持久化封装 (storage_pref 36K) │
│  ├─ page_utils.dart (23K)    ← 页面跳转工具                          │
│  ├─ request_utils.dart (21K) ← 请求工具                              │
│  ├─ image_utils.dart (10K)   ← 图片处理                              │
│  ├─ wbi_sign.dart            ← B 站 WBI 签名                         │
│  └─ ... 30+ 工具文件                                                │
├───────────────────────────────────────────────────────────────────────┤
│                       TCP / WebSocket                                 │
│  lib/tcp/live.dart ← 直播弹幕 WebSocket 连接                         │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 四、网络层详解

### 4.1 REST 层 (`lib/http/`) — 28 个服务文件

所有服务类均为 `abstract final class`，仅包含 `static` 方法。

```
lib/http/
├── init.dart              ← Request 单例: Dio 封装、HTTP/2、重试、Cookie、WBI
├── api.dart (~1011 行)    ← 所有 REST URL 常量
├── constants.dart         ← 基础 URL (api/app/live/passport/base)
│
├── video.dart             VideoHttp     ← 推荐/播放地址/三连/点赞/投币/心跳
├── live.dart              LiveHttp      ← 直播间/播放地址/弹幕 Token
├── search.dart            SearchHttp    ← 综合搜索/建议/热搜
├── reply.dart             ReplyHttp     ← 评论增删改查赞踩
├── dynamics.dart          DynamicsHttp  ← 动态列表/发布/删除
├── user.dart              UserHttp      ← 用户信息
├── member.dart            MemberHttp    ← 用户空间
├── fav.dart               FavHttp       ← 收藏夹管理
├── pgc.dart               PgcHttp       ← 番剧信息/评分/时间线
├── login.dart             LoginHttp     ← 二维码/短信/密码登录
├── msg.dart               MsgHttp       ← 消息通知
├── music.dart             MusicHttp     ← 音乐
├── danmaku.dart           DanmakuHttp   ← 弹幕发送/举报/过滤
├── follow.dart            FollowHttp    ← 关注分组
├── fan.dart               FanHttp       ← 粉丝
├── download.dart          DownloadHttp  ← 下载
├── sponsor_block*.dart    SponsorBlock  ← SponsorBlock (第三方)
├── black.dart             BlackHttp     ← 黑名单
├── match.dart             MatchHttp     ← 赛事
├── danmaku_block.dart     DanmakuBlockHttp ← 弹幕屏蔽规则
├── validate.dart          ValidateHttp  ← 验证
│
├── loading_state.dart     ← LoadingState 密封类 (Loading/Success/Error)
├── retry_interceptor.dart ← Dio 重试拦截器
├── browser_ua.dart        ← User-Agent 常量
└── error_msg.dart         ← 错误消息
```

### 4.2 gRPC 层 (`lib/grpc/`) — 7 个已迁移服务

同样为 `abstract final class` + `static` 方法。

```
lib/grpc/
├── grpc_req.dart  ← GrpcReq: 核心引擎
│                    内部调用 Request().post<Uint8List>() + protobuf 编解码
├── url.dart       ← GrpcUrl: gRPC 方法路径常量
│
├── view.dart      ViewGrpc    ← 视频详情 View 接口
├── dm.dart        DmGrpc      ← 弹幕分段加载 DmSegMobile
├── dyn.dart       DynGrpc     ← 动态红点 DynRed / OpusDetail
├── reply.dart     ReplyGrpc   ← 评论列表 (仅查询: MainList/DetailList/DialogList)
├── im.dart        ImGrpc      ← 私信/IM (最完整: 16 接口)
├── audio.dart     AudioGrpc   ← 音频播放 URL / 三连 / 投币
└── space.dart     SpaceGrpc   ← 空间动态流 / 搜索存档
```

### 4.3 gRPC 调用链验证（CodeGraph 追踪）

```
ViewGrpc.view(bvid)                    [lib/grpc/view.dart:8]
  └─ GrpcReq.request(url, proto, parser)  [lib/grpc/grpc_req.dart:55]
       ├─ Request().post<Uint8List>()     [lib/http/init.dart:36]
       │    └─ Dio 单例 (同一连接池/拦截器)
       ├─ compressProtobuf()              [lib/grpc/grpc_req.dart:22]
       │    └─ 5字节帧头 + 条件 gzip
       └─ _parse() / decompressProtobuf() [lib/grpc/grpc_req.dart:45/33]
```

**重要发现**: `GrpcReq` **不是**标准 gRPC 实现，而是**基于 Dio 的自定义 Protobuf-over-HTTP**。它复用 REST 层的同一个 Dio 实例、Cookie Jar、账号拦截器和重试逻辑，仅通过 `content-type: application/grpc` 和 `responseType: ResponseType.bytes` 区分。

### 4.4 gRPC 迁移状态

| 领域 | 查询 (Query) | 写入 (Mutation) | 状态 |
|------|-------------|----------------|------|
| **视频详情** | REST (`VideoHttp.videoIntro`) | REST | ❌ 未迁移 (`ViewGrpc` 已实现但被注释) |
| **评论** | ✅ gRPC (`ReplyGrpc`) | ❌ REST (`ReplyHttp`) | ⏳ 半迁移 |
| **弹幕** | ✅ gRPC (`DmGrpc`) | ❌ REST (`DanmakuHttp`) | ⏳ 半迁移 |
| **动态/Opus** | ✅ gRPC (`DynGrpc` / `SpaceGrpc`) | ❌ REST (`DynamicsHttp`) | ⏳ 半迁移 |
| **私信/IM** | ✅ gRPC (`ImGrpc`) | ✅ gRPC | ✅ 最完整 |
| **音频** | ✅ gRPC (`AudioGrpc`) | ✅ gRPC | ✅ 已迁移 |
| **直播** | ❌ REST | ❌ REST | ❌ 未迁移 |
| **搜索** | ❌ REST | — | ❌ 未迁移 |
| **番剧/PGC** | ❌ REST | ❌ REST | ❌ 未迁移 |
| **用户/关注** | ❌ REST | ❌ REST | ❌ 未迁移 |
| **收藏** | ❌ REST | ❌ REST | ❌ 未迁移 |
| **登录** | ❌ REST | ❌ REST | ❌ 未迁移 |
| **SponsorBlock** | ❌ REST | ❌ REST | ❌ 未迁移 |

> 📌 注意 `ViewGrpc.view()` 虽已实现（`lib/grpc/view.dart:8`），但 `PgcIntroController` 中注释掉了对它的调用（`lib/pages/video/introduction/pgc/controller.dart:457`），视频元数据仍走 REST。

### 4.5 `Request` (Dio) 调用者矩阵

CodeGraph 追踪到 `Request()` 单例被 **270+ 处**调用，覆盖全部 HTTP/gRPC 流量。关键调用者：

| 调用者 | 位置 |
|--------|------|
| `GrpcReq.request()` | `lib/grpc/grpc_req.dart:61` |
| `VideoHttp.*` (12+ 方法) | `lib/http/video.dart` |
| `LiveHttp.*` | `lib/http/live.dart` |
| `SearchHttp.*` | `lib/http/search.dart` |
| `DynamicsHttp.*` | `lib/http/dynamics.dart` |
| `ReplyHttp.*` | `lib/http/reply.dart` |
| `LoginHttp.*` | `lib/http/login.dart` |
| `PgcHttp.*` | `lib/http/pgc.dart` |
| `FavHttp.*` | `lib/http/fav.dart` |
| `UserHttp.*` | `lib/http/user.dart` |
| `MemberHttp.*` | `lib/http/member.dart` |
| `MsgHttp.*` | `lib/http/msg.dart` |

---

## 五、页面模块地图

> CodeGraph 搜索发现 ~50 个 Controller 类分布在 pages/*/controller.dart 中。
> 每个页面模块遵循 **controller.dart + view.dart + widgets/** 三层模式。

### 5.1 核心功能页

#### 🎬 视频详情 (`lib/pages/video/`) — 最大模块 (~30 文件)

```
video/
├── controller.dart  (52KB)       ← 主控制器: 播放/弹幕/互动
├── view.dart        (79KB)       ← 播放器 UI 布局
├── ai_conclusion/                ← AI 总结
├── download_panel/               ← 下载面板
├── introduction/
│   ├── ugc/                      ← UGC 视频简介 (controller 24KB)
│   │   └── widget/               ← action_item / menu_row / season / triple_mixin
│   └── pgc/                      ← PGC/番剧简介 (controller 15KB)
│       └── widget/               ← intro_detail / pgc_panel
├── medialist/                    ← 媒体列表
├── member/                       ← 成员信息
├── note/                         ← 笔记
├── pay_coins/                    ← 投币
├── post_panel/                   ← 投稿面板
├── related/                      ← 相关推荐
├── reply/                        ← 评论
├── reply_new/                    ← 新版评论
├── reply_reply/                  ← 评论回复
├── reply_search_item/            ← 评论搜索项
├── send_danmaku/                 ← 发送弹幕
├── view_point/                   ← 高能看点
└── widgets/                      ← 头部控制 / 播放器焦点
    ├── header_control.dart  (79KB)
    ├── header_mixin.dart    (21KB)
    └── player_focus.dart
```

**视频详情页调用链**（CodeGraph 验证）：

```
VideoDetailPageV                  [lib/pages/video/view.dart:74]
  └─ VideoDetailController        [lib/pages/video/controller.dart]
       ├─ PlPlayerController.getInstance()
       │    └─ VideoHttp.videoUrl()     ← 播放地址 (REST)
       │    └─ VideoHttp.playInfo()     ← HDR/音频 (REST)
       │    └─ VideoHttp.vttSubtitles() ← 字幕 (REST)
       │    └─ VideoHttp.tvPlayUrl()    ← TV 端 (REST)
       ├─ UgcIntroController
       │    └─ VideoHttp.videoIntro()   ← 视频元数据 (REST)
       │    └─ VideoHttp.ugcTriple()    ← 三连 (REST)
       │    └─ VideoHttp.likeVideo()    ← 点赞 (REST)
       ├─ PgcIntroController
       │    └─ VideoHttp.pgcLikeCoinFav() ← 番剧 (REST)
       │    └─ ViewGrpc.view()          ← 已注释, 未启用
       └─ VideoReplyController
            └─ ReplyGrpc.mainList()     ← 评论列表 (gRPC)
            └─ ReplyHttp.likeReply()    ← 评论操作 (REST)
```

#### 📺 直播 (`lib/pages/live_room/`)

```
LiveRoomController                [lib/pages/live_room/controller.dart]
  ├─ LiveHttp.liveRoomInfo()      ← 直播间信息 (REST)
  ├─ LiveHttp.liveRoomInfoH5()    ← H5 信息 (REST)
  ├─ VideoHttp.roomEntryAction()  ← 入房上报 (REST)
  └─ PlPlayerController.getInstance().setDataSource()  ← 播放
```

#### 🔍 搜索体系 (5 个独立页面)

```
搜索入口:     /search        → SearchPage
搜索面板:     /searchPanel   → SearchPanelPage (含 video/article/live/pgc/user 子面板)
搜索结果:     /searchResult  → SearchResultPage
热搜:         /searchTrending → SearchTrendingPage
搜索复用:     /favSearch / historySearch / laterSearch / followSearch / memberSearch
```

### 5.2 完整路由表

| 路由 | 页面 | 功能 |
|------|------|------|
| `/` | MainApp | 主壳（底部导航壳） |
| `/home` | HomePage | 首页推荐流 |
| `/hot` | HotPage | 热门视频 |
| `/videoV` | VideoDetailPageV | 🎬 **视频详情/播放** |
| `/liveRoom` | LiveRoomPage | 📺 **直播间** |
| `/webview` | WebviewPage | WebView |
| `/search` | SearchPage | 搜索 |
| `/searchResult` | SearchResultPage | 搜索结果 |
| `/searchTrending` | SearchTrendingPage | 热搜 |
| `/dynamics` | DynamicsPage | 动态流 |
| `/dynamicDetail` | DynamicDetailPage | 动态详情 |
| `/dynTopic` | DynTopicPage | 话题详情 |
| `/follow` | FollowPage | 关注列表 |
| `/fan` | FansPage | 粉丝列表 |
| `/member` | MemberPage | 用户空间 |
| `/memberSearch` | MemberSearchPage | 用户搜索 |
| `/memberDynamics` | MemberDynamicsPage | 用户动态 |
| `/memberGuard` | MemberGuardPage | 用户舰队 |
| `/upowerRank` | UpowerRankPage | 创作力排名 |
| `/fav` | FavPage | 收藏夹 |
| `/favDetail` | FavDetailPage | 收藏夹详情 |
| `/history` | HistoryPage | 历史记录 |
| `/later` | LaterPage | 稍后再看 |
| `/whisper` | WhisperPage | 私信列表 |
| `/whisperDetail` | WhisperDetailPage | 私信详情 |
| `/whisperSettings` | WhisperSettingsPage | 私信设置 |
| `/whisperBlock` | WhisperBlockPage | 私信屏蔽 |
| `/whisperSecondary` | WhisperSecondaryPage | 二级私信 |
| `/replyMe` | ReplyMePage | 回复我的 |
| `/atMe` | AtMePage | @我的 |
| `/likeMe` | LikeMePage | 收到的赞 |
| `/sysMsg` | SysMsgPage | 系统消息 |
| `/setting` | SettingPage | 设置主页 |
| `/recommendSetting` | RecommendSetting | 推荐流设置 |
| `/videoSetting` | VideoSetting | 音视频设置 |
| `/playSetting` | PlaySetting | 播放器设置 |
| `/styleSetting` | StyleSetting | 外观设置 |
| `/privacySetting` | PrivacySetting | 隐私设置 |
| `/extraSetting` | ExtraSetting | 其它设置 |
| `/barSetting` | BarSetPage | 导航栏设置 |
| `/displayModeSetting` | SetDisplayMode | 帧率设置 |
| `/colorSetting` | ColorSelectPage | 主题色选择 |
| `/fontSizeSetting` | FontSizeSelectPage | 字体大小 |
| `/playSpeedSet` | PlaySpeedPage | 倍速设置 |
| `/about` | AboutPage | 关于 |
| `/loginPage` | LoginPage | 登录 |
| `/subscription` | SubPage | 订阅 |
| `/subDetail` | SubDetailPage | 订阅详情 |
| `/danmakuBlock` | DanmakuBlockPage | 弹幕屏蔽 |
| `/liveDmBlockPage` | LiveDmBlockPage | 直播弹幕屏蔽 |
| `/sponsorBlock` | SponsorBlockPage | SponsorBlock |
| `/articlePage` | ArticlePage | 专栏 |
| `/articleList` | ArticleListPage | 专栏列表 |
| `/musicDetail` | MusicDetailPage | 音乐详情 |
| `/audio` | AudioPage | 音频播放 |
| `/download` | DownloadPage | 下载管理 |
| `/dlna` | DLNAPage | DLNA 投屏 |
| `/webdavSetting` | WebDavSettingPage | WebDAV 设置 |
| `/popularSeries` | PopularSeriesPage | 热门系列 |
| `/popularPrecious` | PopularPreciousPage | 热门精选 |
| `/matchInfo` | MatchInfoPage | 赛事信息 |
| `/pgc` | PgcPage | 番剧 |
| `/pgcIndex` | PgcIndexPage | 番剧索引 |
| `/pgcReview` | PgcReviewPage | 番剧评分 |
| `/rank` | RankPage | 排行榜 |
| `/bubble` | BubblePage | 气泡 |
| `/blackListPage` | BlackListPage | 黑名单 |
| `/logs` | LogsPage | 日志 |
| `/settingsSearch` | SettingsSearchPage | 设置搜索 |
| `/editProfile` | EditProfilePage | 编辑资料 |
| `/createFav` | CreateFavPage | 创建收藏夹 |
| `/createVote` | CreateVotePage | 创建投票 |
| `/spaceSetting` | SpaceSettingPage | 空间设置 |
| `/myReply` | MyReply | 我的回复 |
| `/mainReply` | MainReplyPage | 主回复 |
| `/videoWeb` | MemberVideoWeb | 成员视频 (Web) |
| `/ssWeb` | MemberSSWeb | 成员合集 (Web) |
| `/followed` | FollowedPage | 已关注 |
| `/sameFollowing` | FollowSamePage | 共同关注 |
| `/live` | LivePage | 直播分区 |
| `/liveAreaDetail` | LiveAreaDetailPage | 分区详情 |
| `/liveFollow` | LiveFollowPage | 关注直播 |
| `/liveSearch` | LiveSearchPage | 直播搜索 |

---

## 六、播放器架构

### `lib/plugin/pl_player/` — 自研播放器封装

```
pl_player/
├── controller.dart (55KB)           ← 核心控制器 (单例)
│   ├── getInstance() / dispose()     ← 生命周期
│   ├── setDataSource(DataSource)     ← 设置视频源
│   ├── play() / pause() / seekTo()   ← 播放控制
│   ├── setPlaybackSpeed()            ← 倍速
│   ├── enterPip() / enterDesktopPip()← 画中画
│   ├── setVolume() / setAlwaysOnTop()
│   ├── isBuffering / playerStatus    ← 响应式状态
│   ├── setAudioDelayIfExists(val)    ← [自制] 运行时设置 audio-delay
│   ├── getPlayerDiagnostics()        ← [自制] 读取 14 项 mpv 属性用于诊断
│   └── (BT 自动切换: 监听 devicesStream 即时应用/归零 audio-delay)
│
├── view/view.dart (89,160 bytes)     ← 播放器 UI
│   ├── 控制栏显示/隐藏
│   ├── 手势处理 (亮度/音量/快进)
│   ├── 弹幕层
│   └── 全屏切换
│
├── models/
│   ├── data_source.dart              ← sealed class DataSource
│   │   ├── NetworkSource (videoUrl + audioUrl)
│   │   └── FileSource (本地缓存)
│   ├── play_status.dart              ← 播放状态枚举
│   ├── play_repeat.dart              ← 循环模式
│   ├── fullscreen_mode.dart          ← 全屏模式
│   ├── video_fit_type.dart           ← 画面适配
│   ├── gesture_type.dart             ← 手势类型
│   ├── hwdec_type.dart               ← 硬解类型
│   ├── duration.dart                 ← 播放时长
│   ├── data_status.dart              ← 数据状态
│   ├── double_tap_type.dart          ← 双击行为
│   ├── heart_beat_type.dart          ← 心跳类型
│   ├── bottom_control_type.dart      ← 底部控制类型
│   ├── bottom_progress_behavior.dart ← 进度条行为
│   ├── audio_output_type.dart        ← 音频输出
│   └── play_speed.dart               ← 倍速预设
│
├── utils/
│   ├── fullscreen.dart               ← 全屏工具函数
│   └── danmaku_options.dart          ← 弹幕渲染配置
│
└── widgets/
    ├── bottom_control.dart           ← 底部控制栏
    ├── play_pause_btn.dart           ← 播放/暂停按钮
    ├── forward_seek.dart             ← 快进按钮
    ├── backward_seek.dart            ← 快退按钮
    ├── app_bar_ani.dart              ← 顶栏动画
    ├── common_btn.dart               ← 通用按钮
    ├── mpv_convert_webp.dart         ← WebP 动图转换
    └── ── (布局在 view.dart 中)
```

### `PlPlayerController` 调用者（CodeGraph 追踪）

| 调用者 | 位置 | 用途 |
|--------|------|------|
| `VideoDetailController` | `lib/pages/video/controller.dart:122` | 主视频页 |
| `LiveRoomController` | `lib/pages/live_room/controller.dart:176` | 直播播放 |
| `AudioController` | `lib/pages/audio/controller.dart:124` | 音频页 |
| `AudioHandler` | `lib/services/audio_handler.dart:89,142,...` | 后台音频 + PiP |
| `ShutdownTimerService` | `lib/services/shutdown_timer_service.dart:70,86,109` | 空闲自动关机 |
| `_VideoDetailPageVState` | `lib/pages/video/view.dart:87,138,...` | 暂停/恢复/PiP |
| `DanmakuInputView` | `lib/pages/video/send_danmaku/view.dart:469` | 弹幕发送 |

---

## 七、数据模型层

### 手写 JSON 模型 (`lib/models/`)

| 目录 | 内容 |
|------|------|
| `common/` | ~60 枚举/常量：视频质量、音质、搜索类型、排序方式、主题色、弹幕屏蔽类型等 |
| | 子目录: `dynamic/` `live/` `member/` `msg/` `reply/` `search/` `sponsor_block/` `theme/` `video/` |
| `user/` | 用户信息 (`info.dart/.g.dart`)、统计 (`stat.dart/.g.dart`)、弹幕屏蔽规则 |
| `member/` | 用户空间信息、标签 |
| `search/` | 搜索结果、搜索建议 |
| `dynamics/` | 动态结果、文章内容、投票 |
| `home/` | 首页推荐 |
| `video/` | 播放 URL |
| `login/` | 登录模型 |

### Proto 生成模型 (`lib/grpc/bilibili/`)

protoc 从 `.proto` 文件生成的三件套 (`.pb.dart` + `.pbenum.dart` + `.pbjson.dart`)：

| 命名空间 | 覆盖接口 |
|----------|----------|
| `bilibili.app.viewunite.v1` | 视频详情 View |
| `bilibili.app.dynamic.v2` | 动态 |
| `bilibili.app.interfaces.v1` | 收藏/历史接口 |
| `bilibili.app.listener.v1` | 播放监听 |
| `bilibili.app.playurl.v1` | 播放 URL |
| `bilibili.app.card.v1` | 卡片 |
| `bilibili.app.archive.v1` | 存档 |
| `bilibili.app.show.v1` | 推荐展示 |
| `bilibili.app.playeronline.v1` | 在线人数 |
| `bilibili.community.service.dm.v1` | 弹幕 |
| `bilibili.main.community.reply.v1` | 评论 |
| `bilibili.im.interfaces` | 私信 |
| `bilibili.im.type` | 私信类型 |
| `bilibili.account.service` | 账号 |
| `bilibili.metadata` | 元数据 (device/network/locale) |

---

## 八、服务层

`lib/services/` — 长期运行的后台服务：

| 服务 | 文件 | 说明 |
|------|------|------|
| `AccountService` | `account_service.dart` (995B) | 账号状态变化监听 |
| `AudioHandler` | `audio_handler.dart` (9.8KB) | 后台音频 (AudioService)，含 PiP 控制 |
| `AudioSessionHandler` | `audio_session.dart` (3.5KB) | 音频会话：打断恢复、耳机拔出暂停、蓝牙 A2DP 自动检测与延迟补偿切换 |
| `DownloadManager` | `download/download_manager.dart` (3KB) | 下载队列管理 |
| `DownloadService` | `download/download_service.dart` (18KB) | 下载业务逻辑 |
| `ShutdownTimerService` | `shutdown_timer_service.dart` (9.5KB) | 定时关机 |
| `Logger` | `logger.dart` (1.5KB) | 日志工具 |
| `ServiceLocator` | `service_locator.dart` (390B) | GetX 服务注册 |

---

## 九、Utils 工具层

`lib/utils/` — 30+ 工具文件：

| 类别 | 文件 | 说明 |
|------|------|------|
| **账号** | `accounts/account.dart` | 账号管理、多账号切换 |
| | `accounts/account_manager/` | 多账号管理器 (9KB) |
| | `accounts/grpc_headers.dart` | gRPC 请求头封装 |
| | `accounts/api_type.dart` | API 类型路由 |
| | `accounts/cookie_jar_adapter.dart` | Cookie 持久化 |
| **存储** | `storage.dart` | Hive CE 初始化 |
| | `storage_pref.dart` (36KB) | 设置项类型安全封装 |
| | `storage_key.dart` (10KB) | 所有 SettingBoxKey 常量 |
| | `cache_manager.dart` | 缓存清理 |
| **网络** | `request_utils.dart` (21KB) | 请求参数构建 |
| | `wbi_sign.dart` | WBI 签名算法 |
| | `url_utils.dart` | URL 解析 |
| **UI** | `page_utils.dart` (23KB) | 页面跳转/动画 |
| | `theme_utils.dart` (7.5KB) | 主题切换 |
| | `color_utils.dart` | 颜色工具 |
| | `grid.dart` (9KB) | 网格布局算法 |
| | `waterfall.dart` (4KB) | 瀑布流布局 |
| **扩展** | `extension/context_ext.dart` | BuildContext 扩展 |
| | `extension/theme_ext.dart` | Theme 扩展 |
| | `extension/num_ext.dart` | 数字格式化 |
| | `extension/iterable_ext.dart` | 集合操作 |
| | `extension/string_ext.dart` | 字符串工具 |
| | `extension/get_ext.dart` | GetX 扩展 (putOrFind) |
| **平台** | `platform_utils.dart` | 平台判断 |
| | `device_utils.dart` | 设备信息 |
| | `android/android_helper.dart` | Android 原生桥接 |
| | `permission_handler.dart` (7.4KB) | 权限请求 |
| **媒体** | `video_utils.dart` | 视频 URL 解析 |
| | `image_utils.dart` (10KB) | 图片处理 |
| | `danmaku_utils.dart` | 弹幕解析 |
| **其它** | `date_utils.dart` | 日期格式化 |
| | `num_utils.dart` | 数字格式化 (万/亿) |
| | `share_utils.dart` | 分享 |
| | `feed_back.dart` | 触觉反馈 |
| | `update.dart` (5.5KB) | 更新检查 |
| | `app_scheme.dart` (30KB) | 外部 Scheme 处理 |

---

## 十、关键架构决策

| # | 决策 | 实现 | 证据 |
|---|------|------|------|
| 1 | **状态管理: GetX** | 全项目使用 `GetxController` + `Obx`/`Rx` + `GetMaterialApp` + `GetPage` | `lib/main.dart:264`, `lib/pages/*/controller.dart` |
| 2 | **数据状态: 密封类** | `LoadingState<T>` 三态: `Loading` / `Success<T>` / `Error` | `lib/http/loading_state.dart:4-77` |
| 3 | **服务类: 抽象最终类** | REST 和 gRPC 服务均为 `abstract final class` + `static` 方法 | `lib/http/video.dart:47`, `lib/grpc/view.dart:7` |
| 4 | **Dio 双通道** | REST 和 gRPC 共享同一 Dio 单例，gRPC 仅改 content-type | `GrpcReq` 内部调用 `Request().post()` (`lib/grpc/grpc_req.dart:61`) |
| 5 | **Protobuf 模型** | gRPC 用 protoc 生成模型；非 gRPC 用手写 JSON 类 | `lib/grpc/bilibili/*.pb.dart`, `lib/models/*.dart` |
| 6 | **播放器: media_kit** | 基于 libmpv 的 media_kit，单例封装 (`PlPlayerController`) | `pubspec.yaml`, `lib/plugin/pl_player/controller.dart:71` |
| 7 | **持久化: Hive CE** | 本地存储通过 `GStorage` (Hive 封装) | `lib/utils/storage.dart` |
| 8 | **多账号** | `AccountManager` 管理多账号，通过 Dio 拦截器切换 | `lib/utils/accounts/account_manager/`, `lib/http/init.dart:40` |
| 9 | **HTTP/2 可选** | Dio 可配 `Http2Adapter`，网络切换时重建连接 | `lib/http/init.dart:160-196` |
| 10 | **Shaders 超分** | 集成 Anime4K GLSL 着色器实时提升动画画质 | `assets/shaders/Anime4K_*` |
| 11 | **Flutter 补丁** | 通过 `.patch` 文件修改 Flutter SDK 源码修复 bug | `lib/scripts/*.patch` |

---

## 十一、Flutter 源码覆写

`lib/scripts/` 目录下的补丁文件用于修复 Flutter SDK 组件在 PiliPlus 场景下的问题：

| 补丁 | 覆写组件 | 文件大小 |
|------|----------|----------|
| `bottom_sheet_android.patch` | BottomSheet（Android 适配） | 689B |
| `bottom_sheet_ios_piliplus.patch` | BottomSheet（iOS 适配） | 1.1KB |
| `bottom_sheet_ios_flutter.patch` | BottomSheet（Flutter 官方修复） | 6.6KB |
| `geetest_ios.patch` | 极验验证（iOS） | 6.4KB |
| `image_anim.patch` | 图片动画 | 642B |
| `layout_builder.patch` | LayoutBuilder | 3.2KB |
| `modal_barrier.patch` | 模态屏障 | 7.2KB |
| `mouse_cursor.patch` | 鼠标光标 | 654B |
| `navigation_drawer.patch` | 导航抽屉 | 671B |
| `navigator.patch` | 导航器 | 645B |
| `scroll_view.patch` | 滚动视图 | 2.7KB |
| `text_selection.patch` | 文本选择 | 5.8KB |

---

## 十二、本地定制功能

本仓库在上游基础上增加的定制功能：

| 功能 | 涉及文件 | 说明 |
|------|----------|------|
| **蓝牙 A2DP 延迟补偿** | `lib/services/audio_session.dart`<br>`lib/plugin/pl_player/controller.dart`<br>`lib/pages/setting/models/video_settings.dart` | 通过 `audio-delay`（mpv 参数）负值补偿蓝牙耳机音频延迟；支持运行时即时生效、保存确认 toast |
| **蓝牙自动检测切换** | `lib/services/audio_session.dart`<br>`lib/plugin/pl_player/controller.dart`<br>`lib/pages/setting/models/video_settings.dart` | 利用 `audio_session` 包的 `devicesStream` 实时检测蓝牙 A2DP 耳机连接状态，连接时自动应用延迟补偿值，断开时归零 |
| **播放器诊断** | `lib/pages/video/widgets/header_control.dart`<br>`lib/plugin/pl_player/controller.dart` | 播放信息弹窗中新增 `audio-delay`、`avsync`、`paused-on-cache`、`cache-secs`、`cache-buffering-state` 五项 mpv 运行时属性，支持点击复制，用于诊断音画同步和缓冲问题 |
| **时间戳版本号** | `lib/build_config.dart`<br>`scripts/build_android_local.ps1` | 版本号 = 上游版本号 + 当前具体时间（`2.0.9.20260620.135050`），APK 命名同步，确保每次构建唯一且可追溯 |
| **首页搜索框/我的搜索按钮隐藏** | 外观设置 | 支持隐藏首页搜索框和"我的"页搜索按钮，布局占位保留 |
| **修改版标识** | `lib/pages/about/view.dart` | 关于页始终显示"当前为自制修改版"提示；检测到上游更新时提醒升级官方版会丢失本地定制功能 |
| **signedDecimal 输入格式化器** | `lib/utils/filtering_text.dart` | 新增支持负号和小数的输入格式化器，用于音频延迟等需要负数输入的设置项 |

---

## 致谢

- 原作者: [guozhigq/pilipala](https://github.com/guozhigq/pilipala)
- 上游: [orz12/PiliPalaX](https://github.com/orz12/PiliPalaX)
- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [media-kit](https://github.com/media-kit/media-kit)
- [dio](https://pub.dev/packages/dio)
- [GetX](https://pub.dev/packages/get)
- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)

---

<sup>📐 本架构地图由 CodeGraph 符号分析 + explore 子代理生成 | 文件:line 引用均为静态分析验证</sup>
<sup>⚠️ 此仓库为 [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 的本地修改版，定制功能见[第十二章](#十二本地定制功能)。升级官方版会丢失本地定制功能。</sup>
