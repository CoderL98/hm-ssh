#ifndef HMSSH_NATIVE_SSH_CLIENT_H
#define HMSSH_NATIVE_SSH_CLIENT_H

#include "common.h"
#include <atomic>

namespace hmssh {

/**
 * SSH session backed by libssh2 when HMSSH_HAS_LIBSSH2 is defined.
 * Without libssh2, Connect returns a clear error so ArkTS falls back to Mock.
 */
class SshClient {
 public:
  SshClient();
  ~SshClient();

  SshClient(const SshClient&) = delete;
  SshClient& operator=(const SshClient&) = delete;

  /** Returns empty string on success, otherwise error message. */
  std::string Connect(const ConnectParams& params);
  void Disconnect();
  bool IsConnected() const;
  std::string Send(const std::string& data);
  std::string Read(int maxBytes = 16384);
  std::string Resize(int cols, int rows);

 private:
  std::mutex mu_;
  std::atomic<bool> connected_{false};
  int sock_{-1};
  void* session_{nullptr};   // LIBSSH2_SESSION*
  void* channel_{nullptr};   // LIBSSH2_CHANNEL*
  std::string lastError_;

  bool InitLibssh2();
  void CleanupUnlocked();
};

bool Libssh2Available();

}  // namespace hmssh

#endif
