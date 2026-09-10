# 鸿蒙SSH（HmSSH）

HarmonyOS NEXT 原生 SSH 客户端（ArkTS · Stage 模型）。首期面向手机，架构预留平板 / PC / 折叠屏扩展；阔折叠展开横屏时支持「主机列表 + 终端」并排。

> **当前里程碑**：工程骨架、主机 CRUD（preferences 持久化）、自适应窄/宽布局、Mock SSH 会话（回显）。真实 SSH 通过 `ISshSession` 接缝后续接入。

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
│       ├── pages/             # Index / HostEditPage / TerminalPage
│       ├── components/        # HostListPanel / HostListItem / TerminalView
│       ├── models/            # HostConfig
│       ├── services/          # HostStore、SshSession（接口 + Mock）
│       ├── layout/            # Breakpoint 断点与分栏判定
│       └── common/            # 路由常量等
├── build-profile.json5
├── oh-package.json5
├── hvigorfile.ts
└── README.md
```

## 功能说明（里程碑 1）

### 主机列表

- 空态引导 + 列表展示
- 添加 / 编辑：名称、主机、端口（默认 22）、用户名、密码、私钥占位
- 删除确认
- 持久化：`@kit.ArkData` **preferences**（`HostStore`）

### 终端（Mock）

- 终端样式区域（Scroll + 等宽 Text）+ 底部输入行
- `MockSshSession`：连接横幅、命令回显、`exit` / `clear` 等简单指令
- 抽象接口 `ISshSession` + `SshSessionFactory`，便于替换为原生实现

### 自适应 / 折叠屏

| 场景 | 布局 |
| --- | --- |
| 窄屏（宽度 &lt; 600vp，典型手机竖屏） | 仅主机列表；连接后 `router` 压栈进入 `TerminalPage` |
| 宽屏（≥ 600vp：阔折叠展开横屏、平板等） | 左侧列表 + 右侧终端主从并排 |

实现要点：

- `layout/Breakpoint.ets`：`BreakpointHelper.useSplitLayout(widthVp)`
- `Index` 监听 `windowSizeChange`，像素 → vp 后切换 `useSplit`
- 旋转 / 折叠状态变化时自动在窄栈与宽分栏间切换

### 折叠屏测试建议

1. 使用 **阔折叠** 模拟器或真机：折叠竖屏应走窄布局；展开横屏应出现左右分栏。
2. 在展开态旋转为竖屏：若宽度仍 ≥ 600vp 则保持分栏，否则回退栈式。
3. DevEco 预览器可拖拽窗口宽度验证断点（可调 `BreakpointConstants.SPLIT_MIN`）。

## 真实 SSH 接入下一步

当前无内置 libssh；接缝已预留：

1. **Native 模块（NAPI）**  
   - 新建 `ssh_native` HAR / 共享库，链入 **libssh2**（或兼容库）。  
   - 暴露 `connect / authenticate / openChannel / read / write / disconnect`。

2. **实现 `ISshSession`**  
   - 新增 `NativeSshSession implements ISshSession`。  
   - 在 `SshSessionFactory.create()` 中按编译开关或配置切换 Mock / Native。

3. **安全**  
   - 密码与私钥改为加密存储（例如 HUKS）；避免明文 preferences。  
   - Host key 校验、known_hosts。

4. **终端体验**  
   - PTY 尺寸随窗口变化；ANSI 解析；滚动性能优化。

5. **权限**  
   - 已声明 `ohos.permission.INTERNET`；若读本地私钥文件需补充文件访问能力说明。

## 已知差距

- 非真实 SSH，仅 Mock 回显  
- 密码明文 preferences（仅演示）  
- 图标为占位色块，可替换为正式品牌资源  
- 平板 / PC 多窗口、自由窗口与键鼠快捷键尚未打磨  
- 未在本环境执行 DevEco/hvigor 实机编译（请以 DevEco 同步结果为准）

## 许可

MIT © CoderL98（见 [LICENSE](./LICENSE)）
