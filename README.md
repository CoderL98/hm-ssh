# 鸿蒙SSH（HmSSH）

HarmonyOS NEXT 原生远程管理客户端（ArkTS · Stage 模型）。首期面向手机，架构预留平板 / PC / 折叠屏扩展；阔折叠展开横屏时支持「主机列表 + 会话面板」并排。

> **当前里程碑**：主机 CRUD（preferences）、多协议（SSH / FTP / VNC）、自适应窄/宽布局、Mock 会话（SSH 回显 · FTP 内存文件系统 · VNC 占位桌面）。真实协议通过 `ISshSession` / `IFtpSession` / `IVncSession` 接缝后续以 NAPI 接入。

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
│       ├── pages/             # Index / HostEdit / Terminal / FtpBrowser / VncSession
│       ├── components/        # HostList* / TerminalView / FtpBrowserView / VncSessionView
│       ├── models/            # HostConfig（含 protocol）
│       ├── services/          # HostStore、Ssh/Ftp/Vnc Session（接口 + Mock）
│       ├── layout/            # Breakpoint 断点与分栏比例
│       └── common/            # 路由常量等
├── build-profile.json5
├── oh-package.json5
├── hvigorfile.ts
└── README.md
```

## 功能说明

### 主机列表与协议

- 空态引导 + 列表展示；每项带 **SSH / FTP / VNC** 协议徽章
- 添加 / 编辑：协议选择器；按协议显示相关字段
  - **SSH**（默认端口 22）：用户名、密码、私钥占位
  - **FTP**（默认端口 21）：用户名、密码、可选初始路径
  - **VNC**（默认端口 5900）：密码（无用户名必填）
- 删除确认；持久化：`@kit.ArkData` **preferences**（`HostStore`）
- 旧数据无 `protocol` 字段时视为 `ssh`

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

## Mock vs 真实（NAPI）计划

| 能力 | 当前 | 下一步 |
| --- | --- | --- |
| SSH | `MockSshSession` 回显 | NAPI + **libssh2**（或兼容库）：connect / auth / PTY channel |
| FTP | `MockFtpSession` 内存 FS | NAPI + **libcurl** 或自研 FTP：LIST / CWD / RETR / STOR |
| VNC | `MockVncSession` 占位画布 + 输入 stub | NAPI + **RFB** 解码（LibVNCClient 等）+ Surface 渲染与键鼠注入 |
| 凭据 | preferences 明文 | HUKS 加密；known_hosts / 证书校验 |

工厂类（`SshSessionFactory` / `FtpSessionFactory` / `VncSessionFactory`）可按编译开关切换 Mock / Native，业务 UI 无需改动。

## 已知差距

- 非真实网络协议，仅 Mock  
- 密码明文 preferences（仅演示）  
- VNC 无真实像素流；FTP 无真实传输与 TLS  
- 图标为占位；平板 / PC 多窗口与键鼠快捷键尚未打磨  
- 未在本环境执行 DevEco/hvigor 实机编译（请以 DevEco 同步结果为准）

## 许可

MIT © CoderL98（见 [LICENSE](./LICENSE)）
