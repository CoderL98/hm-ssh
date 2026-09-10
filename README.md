# 鸿蒙SSH（HmSSH）

HarmonyOS NEXT 原生远程管理客户端（ArkTS · Stage 模型）。首期面向手机，架构预留平板 / PC / 折叠屏扩展；阔折叠展开横屏时支持「主机列表 + 会话面板」并排。

> **当前里程碑**：主机 CRUD（preferences）、多协议（SSH / FTP / VNC）、自适应窄/宽布局、Mock 会话、**云帐号 + 主机/设置同步**（Rust server + 客户端接缝）。真实协议通过 `ISshSession` / `IFtpSession` / `IVncSession` 接缝后续以 NAPI 接入。

## 视觉语言

UI 采用 **鸿蒙系统设置「纯净风」**：浅灰页底 `#F1F3F5`、白色分组卡片、大标题列表行、灰色协议标签（非高饱和色块）、强调色（默认系统蓝 `#0A59F7`）仅用于链接/主操作。组件克制（细分割线、少胶囊按钮）；终端内容区使用独立配色方案，VNC 桌面区保持深色占位。

## 环境要求

| 项 | 建议值 |
| --- | --- |
| DevEco Studio | 5.0+（支持 HarmonyOS NEXT） |
| 兼容 SDK / API | `compatibleSdkVersion: 5.0.0(12)`，API 12+ |
| 设备类型 | phone（优先）、tablet、2in1 |
| 语言 | ArkTS，Stage 模型 |

本仓库可在无 DevEco 环境下完整阅读与二次开发；本地未捆绑 hvigor 守护进程时，请用 DevEco 打开工程完成同步与编译。

## 用 DevEco Studio 打开

1. 克隆或拷贝本仓库到本地。
2. 启动 **DevEco Studio** → **Open** → 选择本目录（含 `build-profile.json5` / `oh-package.json5` 的根目录）。
3. 等待自动同步 `oh_modules` / hvigor；若提示签名，在 **File → Project Structure → Signing Configs** 配置自动签名。
4. 选择 Phone / 折叠屏模拟器或真机，运行 **entry** 模块。

`bundleName`：`com.coderl98.hmssh`  
应用名：`鸿蒙SSH`

## 工程结构

```
hm-ssh/
├── AppScope/                  # 应用级配置与资源
├── entry/
│   └── src/main/ets/
│       ├── entryability/      # EntryAbility
│       ├── pages/             # Index / HostEdit / Terminal / FtpBrowser / VncSession / Settings / Account
│       ├── components/        # HostList* / TerminalView / FtpBrowserView / VncSessionView
│       ├── models/            # HostConfig（含 protocol）
│       ├── services/          # HostStore、ThemeStore、Auth、CloudSync、Ssh/Ftp/Vnc Session
│       ├── theme/             # ThemeTokens（强调色 / 终端配色 / 对比度）
│       ├── layout/            # Breakpoint 断点与分栏比例
│       └── common/            # 路由常量、CloudConfig
├── server/                    # Rust 云端（axum + sqlx + JWT + Argon2）
│   ├── src/                   # auth / db / cache / routes
│   ├── migrations/
│   ├── .env.example
│   └── README.md
├── build-profile.json5
├── oh-package.json5
├── hvigorfile.ts
└── README.md
```

## 功能说明

### 主机列表与协议

- 空态引导 + 设置风列表行；每项带静默灰色 **SSH / FTP / VNC** 协议标签与右箭头（整行连接；长按菜单编辑/删除）
- 添加 / 编辑：协议选择器；按协议显示相关字段
  - **SSH**（默认端口 22）：用户名、密码、私钥占位
  - **FTP**（默认端口 21）：用户名、密码、可选初始路径
  - **VNC**（默认端口 5900）：密码（无用户名必填）
- 删除确认；持久化：`@kit.ArkData` **preferences**（`HostStore`）
- 旧数据无 `protocol` 字段时视为 `ssh`


### 主题与外观

入口：**主机列表** 右上角「设置」→ `SettingsPage`。

| 项 | 选项 | 说明 |
| --- | --- | --- |
| 外观 | 浅色 / 深色 / 跟随系统 | `ThemeStore.themeMode`；经 `ApplicationContext.setColorMode`（API 12）强制或跟随；窗口背景同步 |
| 强调色 | 系统蓝、绿、橙、紫、粉、灰/中性 | 作用于主操作文字、链接、选中行 tint、协议选中 chip、焦点 |
| 终端配色 | Classic Dark、Light、Solarized Dark/Light、Nord、Monokai | 成对 bg+fg（+cursor）；应用于 `TerminalView` 内容区与输入框 |

持久化：`preferences`（`ThemeStore`）键 `theme_mode` / `accent_id` / `terminal_scheme_id`。变更通过 `AppStorage.themeRev` 驱动页面刷新。

**对比度安全规则**

- 强调色主按钮文字：按强调色相对亮度自动黑 (`#000`) / 白 (`#FFF`)（阈值 0.55）。
- 选中行 / 软强调底：强调色低透明叠色（浅色约 10%、深色约 22–28%），徽章仍用中性灰底+灰字，双主题可读。
- 终端预设：出厂即为连贯 bg+fg；`ensureTerminalContrast` 拒绝 fg==bg 或对比度 &lt; 4.5，不达标则回退 Classic Dark。后续若开放自定义，同样钳制。

令牌解析：`theme/ThemeTokens.ets`；深色资源：`entry/src/main/resources/dark/element/color.json`（纯净风黑底 + `#1C1C1E` 卡片）。

### SSH 终端（Mock）

- 终端样式区域 + 底部输入行
- `MockSshSession`：连接横幅、命令回显、`exit` / `clear`
- 抽象 `ISshSession` + `SshSessionFactory`

### FTP 浏览器（Mock）

- 路径面包屑、文件/文件夹列表、上级 / 刷新、上传 / 下载
- `MockFtpSession`：内存文件系统（含 `/home/user` 示例树）；`list` / `cd` / `download` / `upload` 更新 Mock FS
- 空目录、加载中、错误态
- 抽象 `IFtpSession` + `FtpSessionFactory`，便于替换真实 FTP（libcurl / 自研）

### VNC 远程桌面（Mock）

- 占位「帧缓冲」画布（假分辨率标签 + 网格）、连接状态、断开
- 触控 → `sendPointer` stub；「模拟按键」→ `sendKey` stub
- `MockVncSession` + `IVncSession`；**真实 RFB 必须走 NAPI 原生模块**（像素解码与输入注入）

### 自适应 / 折叠屏 / 平板 / PC

| 场景 | 布局 |
| --- | --- |
| 窄屏（宽度 &lt; 600vp，典型手机竖屏） | 仅主机列表；连接后按协议 `router` 压栈进入 Terminal / FtpBrowser / VncSession 页 |
| 宽屏（≥ 600vp：阔折叠展开横屏、平板等） | 左侧列表 + 右侧会话面板；切换主机时右栏按协议重连 |
| 超宽（≥ 840vp / ≥ 1000vp） | 左侧列表略加宽（约 36% / 38%） |

实现要点：

- `layout/Breakpoint.ets`：`useSplitLayout`、`listPanePercent`
- `Index` 监听 `windowSizeChange`，像素 → vp 后切换 `useSplit` 与列表宽度
- 分栏模式下选中不同协议主机，会断开当前会话并打开对应面板

### 折叠屏与多协议测试建议

1. **阔折叠**：折叠竖屏 → 窄布局；展开横屏 → 左右分栏。
2. 分别添加 SSH / FTP / VNC 主机，在窄屏点「连接」应进入对应页面；宽屏应在右栏切换面板。
3. FTP：进入目录、返回上级、上传生成 mock 文件、下载 toast 提示。
4. VNC：查看占位桌面，触摸区域观察状态栏 stub 指针事件，点「模拟按键」。
5. DevEco 预览器拖拽窗口宽度验证断点（可调 `BreakpointConstants.SPLIT_MIN`）。

## 默认端口一览

| 协议 | 默认端口 |
| --- | --- |
| SSH | 22 |
| FTP | 21 |
| VNC | 5900 |


### 帐号与云同步

入口：**设置 → 帐号**（`AccountPage`）。出厂默认 Mock（`CloudConfig.USE_MOCK`）；**帐号页可运行时切换** Mock / 真实服务器并填写基址（持久化到 `AuthStore`）。

| 组件 | 说明 |
| --- | --- |
| `AuthService` | `IAuthService` + `HttpAuthService` / `MockAuthService`；JWT + refresh 存 preferences（**HUKS 为后续**）；HTTP 请求自动 refresh |
| `CloudSyncService` | `GET/PUT /api/v1/sync/hosts` 与 `/settings`；登录后自动同步；主机保存/删除与主题变更后台推送 |
| `server/` | Rust 云端：注册/登录/refresh/logout、SQLite（默认可换 PG/MySQL）、内存/Redis 缓存 |

**合并策略（last-write-wins）**：以服务端资源级 `updated_at`（Unix ms）为权威；主机列表按 `id` 合并，同一 id 取本地/远端 `updatedAt` 较大者；设置 JSON 整包采用较新一侧。本地 `HostStore` 仍是离线真相源，云同步为 **additive**。

**机密不上云**：同步载荷默认清空 `password` / `privateKey`（客户端 `toCloudJson` + 服务端再剥离）；合并时若云端为空则保留本机密。

启动云端见 [`server/README.md`](./server/README.md)：

```bash
cd server && cp .env.example .env   # 设置 JWT_SECRET
cargo run                          # http://0.0.0.0:8080
```

环境变量摘要：`DATABASE_URL`（`sqlite:` / `postgres://` / `mysql://`）、`JWT_SECRET`、可选 `REDIS_URL`、`BIND`、`CORS_ORIGINS`、`AUTH_RATE_LIMIT_PER_MIN`（默认 20）。

## Mock vs 真实（NAPI）计划

| 能力 | 当前 | 下一步 |
| --- | --- | --- |
| SSH | `MockSshSession` 回显 | NAPI + **libssh2**（或兼容库）：connect / auth / PTY channel |
| FTP | `MockFtpSession` 内存 FS | NAPI + **libcurl** 或自研 FTP：LIST / CWD / RETR / STOR |
| VNC | `MockVncSession` 占位画布 + 输入 stub | NAPI + **RFB** 解码（LibVNCClient 等）+ Surface 渲染与键鼠注入 |
| 凭据 | preferences 明文 | HUKS 加密；known_hosts / 证书校验 |
| 云帐号 Token | preferences + 自动 refresh + 服务端 refresh jti 轮换 | HUKS 加密存储（下一步） |

工厂类（`SshSessionFactory` / `FtpSessionFactory` / `VncSessionFactory`）可按编译开关切换 Mock / Native，业务 UI 无需改动。

## 已知差距 /  backlog

### 已完成（本阶段）

- 云端 auth 按 IP 速率限制（默认 20 次/分钟，超限 429）
- 客户端 Mock / Account 注册与服务端统一密码最少 **8** 位
- ThemeTokens 更广用于 HostListPanel 标题/链接与 Account 主操作（Settings 纯净风不变）
- 同步冲突 UX：服务端较新且本地有数据时 toast「已从云端合并」；帐号页展示 `lastSyncAt`
- Refresh token 轻量轮换：刷新时签发新 refresh，并将旧 jti 写入缓存 denylist
- 服务端单测 / 集成冒烟：`strip_host_secrets`、速率限制、refresh 轮换（`cd server && cargo test`）

### 仍待

- **真实 NAPI**：SSH（libssh2）/ FTP（libcurl 或自研）/ VNC（RFB + Surface）— 当前仅 Mock 接缝
- **HUKS**：凭据与云 Token 加密落盘；加密后再同步主机机密（可选策略）— 当前 preferences 明文演示，主机密码/私钥默认不上云
- VNC 无真实像素流；FTP 无真实传输与 TLS
- 图标为占位；平板 / PC 多窗口与键鼠快捷键尚未打磨
- 终端 ANSI 彩色与完整光标渲染尚未展开（当前 bg/fg/cursor 基础令牌）
- 云同步出厂 Mock；真机在帐号页切「真实服务器」并填可达地址（需 cleartext/HTTP 或 HTTPS）
- 未在本环境执行 DevEco/hvigor 实机编译（请以 DevEco 同步结果为准）
- 分布式限流（多实例需 Redis 共享计数）；当前为进程内固定窗口

## 许可

MIT © CoderL98（见 [LICENSE](./LICENSE)）
