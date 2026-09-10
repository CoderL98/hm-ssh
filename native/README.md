# 原生协议模块（hmssh_native）

HarmonyOS NEXT **Node-API（NAPI）C++** 模块，为 SSH / FTP / VNC 提供真实协议后端。本仓库在 Cloud Linux 上无法完整链接 OpenHarmony NDK，因此交付 **完整可在 DevEco 编译的源码**；未产出 `.so` 时 ArkTS 工厂自动回退 Mock。

## 目录

```
native/
├── README.md                 # 本文
└── hmssh_native/
    ├── CMakeLists.txt
    ├── oh-package.json5
    ├── include/              # ssh/ftp/vnc 头文件
    ├── src/                  # 实现 + napi_init.cpp
    ├── types/libhmssh_native/Index.d.ts
    └── third_party/          # libssh2 放置说明
entry/src/main/cpp/
├── CMakeLists.txt            # add_subdirectory → native/hmssh_native
└── types/libhmssh_native/    # oh_modules 类型声明
```

## 在 DevEco 中启用 C++

1. 用 DevEco Studio 打开仓库根目录，同步工程。
2. 确认 `entry/build-profile.json5` 含 `externalNativeOptions.path = ./src/main/cpp/CMakeLists.txt`。
3. 确认 `entry/oh-package.json5` 依赖 `libhmssh_native.so`（file: types）。
4. **File → Project Structure** 检查 NDK / ABI；默认 `abiFilters: ["arm64-v8a"]`。
5. Build → Make Module `entry`。成功后产物为 `libhmssh_native.so`。

## 第三方依赖

| 协议 | 依赖 | 说明 |
| --- | --- | --- |
| SSH | **libssh2** + OpenSSL/mbedTLS | 需 OHOS NDK 交叉编译后放入 `third_party/libssh2` 或设 `HMSSH_LIBSSH2_ROOT`；未链接时 `sshConnect` 报错 |
| FTP | 无（自研 PASV 客户端） | 控制连接 + LIST/CWD/RETR/STOR；`useTls` 显式 FTPS 钩子（未链 OpenSSL 时清晰报错） |
| VNC | 无（自研 RFB 3.8） | Security None / VNC Auth；Framebuffer **Raw + CopyRect**；Tight/ZRLE 需 zlib（stub 报错） |

详见 `hmssh_native/third_party/README.md`。

### 启用 libssh2 示例

```bash
# 在 OHOS NDK 环境中交叉编译 libssh2 后：
cmake -DHMSSH_ENABLE_LIBSSH2=ON \
      -DHMSSH_LIBSSH2_ROOT=/path/to/libssh2-prefix \
      ...
```

或把头文件/静态库放到：

```
native/hmssh_native/third_party/libssh2/include/libssh2.h
native/hmssh_native/third_party/libssh2/lib/libssh2.a
```

## NAPI 导出

| 方法 | 作用 |
| --- | --- |
| `nativeAvailable()` | `.so` 已加载 |
| `sshConnect/Send/Read/Resize/Disconnect` | SSH + PTY |
| `ftpConnect/Cd/List/Retr/Stor/Disconnect` | FTP |
| `vncConnect/Framebuffer/PointerEvent/KeyEvent/Disconnect` | VNC |

ArkTS：`import native from 'libhmssh_native.so'`；加载失败则工厂使用 Mock。

## ABI

当前工程默认 **arm64-v8a**（手机 / 折叠屏主流）。如需 x86_64 模拟器，在 `externalNativeOptions.abiFilters` 追加 `"x86_64"` 并准备对应三方库。

## 与 Mock 的关系

设置页开关「使用原生协议（需编译 native）」为 ON 且 `.so` 可用时走 Native；否则或连接失败时可回退（工厂优先 Native，不可用则 Mock）。UI 始终通过 `ISshSession` / `IFtpSession` / `IVncSession` 接缝。

## 会话选项扩展（2026-09）

### SSH：known_hosts / 主机密钥确认

`NativeConnectParams.knownHostsPath`（可选）指向 OpenSSH `known_hosts` 文件。

- C++：`SshClient::SetHostKeyCallback` + `LastHostKeyFingerprint()`；握手后记录指纹（libssh2 下为 `SHA256-stub:` + hostkey 前缀 hex）。
- NAPI：`sshConnect` 结果含 `hostKeyFingerprint`，供 ArkTS 弹窗确认。
- **完整** `libssh2_knownhost_readfile` 校验仍为 TODO（需 DevEco 链接 libssh2 后启用）；当前路径参数已接入，未设置回调时默认接受并记录指纹。

### FTP：显式 FTPS / TLS

`NativeConnectParams.useTls = true` 时在 greeting 后走 AUTH TLS 钩子。

- 未链接 OpenSSL/mbedTLS：`ftpConnect` 返回明确错误（不静默降级）。
- TODO：`AUTH TLS` + `PBSZ 0` + `PROT P` + TLS 包装控制/数据通道。

### VNC：额外编码

- **已实现**：Raw (0)、CopyRect (1)
- **Stub**：Tight (7)、ZRLE (16) — 返回需 zlib 的说明错误
- 后续：接入 zlib 后实现 Tight/ZRLE 解码

