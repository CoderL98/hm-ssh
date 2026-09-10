# Third-party dependencies

## libssh2（SSH）

本仓库**不捆绑**预编译 `.a` / `.so`（Cloud Linux 无法完整链接 OpenHarmony NDK）。请在 DevEco / OHOS 工具链侧准备：

1. 从 https://www.libssh2.org/ 或 GitHub `libssh2/libssh2` 获取源码。
2. 使用 **OHOS NDK** 交叉编译 `arm64-v8a`（及需要的 ABI），依赖 OpenSSL 或 mbedTLS（OHOS 允许的加密库）。
3. 将产物放到：
   - `native/hmssh_native/third_party/libssh2/include/libssh2.h`
   - `native/hmssh_native/third_party/libssh2/lib/libssh2.a`
4. 或通过 CMake 缓存变量：`-DHMSSH_LIBSSH2_ROOT=/path/to/prefix`

未找到 libssh2 时模块仍可编译：`sshConnect` 返回明确错误，ArkTS 工厂回退 Mock。

## FTP / VNC

自研 BSD socket 实现，无额外第三方依赖。
