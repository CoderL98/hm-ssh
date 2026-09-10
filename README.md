# 鸿蒙SSH（HmSSH）

HarmonyOS NEXT 原生远程管理客户端（ArkTS · Stage 模型）。首期面向手机，架构预留平板 / PC / 折叠屏扩展；阔折叠展开横屏时支持「主机列表 + 会话面板」并排。

> **当前里程碑**：主机 CRUD、多协议、自适应布局、Mock 会话、云帐号同步，以及 **NAPI 原生协议源码（SSH/FTP/VNC）+ HUKS 加密**。未在本环境链接 OHOS NDK；DevEco 编译 `.so` 后设置中开启「使用原生协议」即可优先走 Native，否则回退 Mock。

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
│       ├── services/          # HostStore、ThemeStore、Auth、CloudSync、HuksCrypto、AppSettings、Session
│       │   └── native/        # NativeBridge + NativeSsh/Ftp/VncSession
│       ├── theme/             # ThemeTokens（强调色 / 终端配色 / 对比度）
│       ├── layout/            # Breakpoint 断点与分栏比例
│       └── common/            # 路由常量、CloudConfig
│   └── src/main/cpp/          # CMake → native/hmssh_native
├── native/                    # NAPI C++ 协议后端源码 + 中文 README
│   └── hmssh_native/          # SSH(libssh2)/FTP/VNC + types
├── server/                    # Rust 云端（axum + sqlx + JWT + Argon2）
│   ├── src/                   # auth / db / cache / routes / admin
│   ├── migrations/
│   ├── .env.example
│   └── README.md
├── admin/                     # SvelteKit + shadcn-svelte 管理 UI
│   ├── src/
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

### SSH 终端

- 终端样式区域 + 底部输入行
- `ISshSession` + `SshSessionFactory`：设置开启原生且 `.so` 可用 → `NativeSshSession`（NAPI + libssh2），否则 `MockSshSession`
- Mock：连接横幅、命令回显、`exit` / `clear`

### FTP 浏览器

- 路径面包屑、文件/文件夹列表、上级 / 刷新、上传 / 下载
- `IFtpSession` + 工厂：Native（自研 PASV）或 Mock 内存 FS

### VNC 远程桌面

- `IVncSession` + 工厂：Native RFB（None/VNC Auth + Raw 帧）或 Mock 占位画布
- 触控 / 模拟按键；Native 提供 RGBA 缓冲供 PixelMap 绘制

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

入口：主机列表右上角 **「登录」/ 用户名**，或 **设置 → 帐号**（`AccountPage`）。

出厂默认 **真实 HTTP**（`CloudConfig.USE_MOCK = false`）；帐号页可切换 Mock 离线演示。默认基址 `http://10.0.2.2:8080`（模拟器访问宿主机）；本机可用 `http://127.0.0.1:8080`，真机改为电脑局域网 IP；均可在帐号页修改并持久化。

| 组件 | 说明 |
| --- | --- |
| `AuthService` | JWT + refresh；**HUKS 加密**后写入 preferences；HTTP 自动 refresh；401 重试 |
| `HuksCrypto` | `@kit.UniversalKeystoreKit` AES；可选口令 PBKDF「云端保险柜」；口令可 HUKS 加密后记住 |
| `CloudSyncService` | hosts/settings 同步；默认剥离明文；保险柜开启时带 `passwordEnc`/`privateKeyEnc` |
| `server/` | Rust 云端；`strip_host_secrets` **保留** `passwordEnc`/`privateKeyEnc`，清空明文 |

**合并策略（last-write-wins）**：以服务端资源级 `updated_at`（Unix ms）为权威；主机列表按 `id` 合并；本地 `HostStore` 仍是离线真相源。

**机密策略**：明文 `password`/`privateKey` 永不上传。本机 HUKS 密文存 `passwordLocalEnc`。可选「同步加密密钥到云端」（帐号页，默认 OFF）：用保险柜口令 PBKDF 派生密钥加密为 `passwordEnc`/`privateKeyEnc` 再同步。

**保险柜口令持久化（权衡）**：开启保险柜后默认「记住保险柜口令」——口令经本机 HUKS AES 加密写入 preferences，重启后可解开云端同步下来的 `passwordEnc`，无需每次重输。代价是本机已解锁设备上应用可自动取回口令（与记住登录 Token 同类风险）；退出登录或关闭保险柜会清除落盘密文。可在帐号页关闭「记住」改为仅内存保存。

#### 客户端登录与同步

1. **启动 Rust 云端**（见 [`server/README.md`](./server/README.md)）：

```bash
cd server && cp .env.example .env   # 设置 JWT_SECRET；可选 ADMIN_EMAIL / ADMIN_PASSWORD
cargo run                          # http://0.0.0.0:8080
```

2. **客户端基址**：帐号页确认「真实服务器」，填写：
   - 模拟器：`http://10.0.2.2:8080`
   - 本机 / 部分预览：`http://127.0.0.1:8080`
   - 真机：`http://<电脑局域网IP>:8080`  
   工程已允许 cleartext（`network_config.json`）；连不上时检查地址与防火墙。
3. **注册 / 登录**：邮箱 + 用户名 + 密码（≥8）；登录可用邮箱或用户名。成功后自动 `syncAll`。
4. **同步内容**：主机列表与主题/终端等设置；列表右上角可再进帐号页点「立即同步」或「退出登录」。
5. **冷启动**：若本地已有会话，`EntryAbility` 会后台 `syncAll`，结果 toast 提示。
6. **Mock**：帐号页切换「Mock（离线演示）」可无服务器联调 UI（切换会退出当前登录）。

管理控制台见 [`admin/README.md`](./admin/README.md)：

```bash
cd admin && cp .env.example .env   # PUBLIC_API_BASE
pnpm install && pnpm dev           # http://localhost:5173
```

环境变量摘要：`DATABASE_URL`（`sqlite:` / `postgres://` / `mysql://`）、`JWT_SECRET`、可选 `REDIS_URL`、`BIND`、`CORS_ORIGINS`、`AUTH_RATE_LIMIT_PER_MIN`（默认 20）、`ADMIN_EMAIL` / `ADMIN_PASSWORD`（种子管理员）。

## Mock vs 真实（NAPI）

| 能力 | 当前 | 说明 |
| --- | --- | --- |
| SSH | Mock + **Native 源码**（libssh2） | DevEco 链接 libssh2 后 `sshConnect` 可用；未链接时 Native connect 报错并回退 Mock |
| FTP | Mock + **Native 自研 PASV** | 无需三方库；需编译 `.so` |
| VNC | Mock + **Native RFB Raw** | None/VNC Auth；CopyRect 等为 TODO |
| 凭据 / Token | **HUKS AES** 落盘 | 明文仅内存；迁移旧明文 |
| 云端机密 | 可选保险柜 | 帐号页「同步加密密钥到云端」+ 口令 |

详见 [`native/README.md`](./native/README.md)。设置页：「使用原生协议（需编译 native）」。

## 已知差距 /  backlog

### 已完成（本阶段）

- 云端 auth 速率限制、密码最少 8 位、同步冲突 UX、refresh jti 轮换、服务端单测
- **NAPI 完整源码** `native/hmssh_native`（SSH/FTP/VNC）+ ArkTS Native*Session / 工厂回退 Mock
- **HUKS** 加密 Token 与主机机密；HostStore 明文迁移；帐号页「云端密钥保险柜」
- 服务端 `strip_host_secrets` 保留 `passwordEnc` / `privateKeyEnc`
- Admin UI access-token **自动 refresh**（skew ~60s / 401 重试一次，失败回登录页）
- AuthUser **短 TTL 缓存**（~45s，logout/revoke/disable/delete 时 invalidate）
- 保险柜口令 **HUKS 落盘**（「记住保险柜口令」默认 ON；logout / 关保险柜清除）
- 连接路径 **新鲜工厂**（Index / Terminal / FTP / VNC）；`preferNative` 翻转时重建会话

### 仍待 / 需 DevEco

- **链接 libssh2**：在 OHOS NDK 交叉编译并放入 `third_party/libssh2`（见 native/README）
- VNC 更多编码（CopyRect/Tight/ZRLE）；FTP TLS；PixelMap 完整绘制链路打磨
- known_hosts / 主机密钥校验
- 图标；平板 / PC 多窗口与快捷键；终端 ANSI 彩色
- 真机请将帐号页基址改为局域网 IP（出厂默认 10.0.2.2 面向模拟器）
- 本环境未跑 DevEco/hvigor；分布式限流需 Redis
- 用户自助改密 API（改密后需同样 invalidate AuthUser 缓存）

## 许可

MIT © CoderL98（见 [LICENSE](./LICENSE)）
