#ifndef HMSSH_NATIVE_SSH_CLIENT_H
#define HMSSH_NATIVE_SSH_CLIENT_H

#include "common.h"
#include <atomic>

namespace hmssh {

/**
 * SSH session backed by libssh2 when HMSSH_HAS_LIBSSH2 is defined.
 * Without libssh2, Connect returns a clear error so ArkTS falls back to Mock.
 *
 * Host key / known_hosts:
 * - ConnectParams.knownHostsPath: optional OpenSSH known_hosts file.
 * - SetHostKeyCallback: optional confirm hook; last fingerprint via LastHostKeyFingerprint().
 * Implementation records fingerprint after handshake; full known_hosts verify is TODO when
 * libssh2 knownhost API is wired in DevEco builds.
 */
class SshClient {
 public:
  SshClient();
  ~SshClient();

  SshClient(const SshClient&) = delete;
  SshClient& operator=(const SshClient&) = delete;

  void SetHostKeyCallback(HostKeyCallback cb);
  std::string LastHostKeyFingerprint();

  /** Returns empty string on success, otherwise error message. */
  std::string Connect(const ConnectParams& params);
  void Disconnect();
  bool IsConnected() const;
  std::string Send(const std::string& data);
  std::string Read(int maxBytes = 16384);
  std::string Resize(int cols, int rows);

 private:
  mutable std::mutex mu_;
  std::atomic<bool> connected_{false};
  int sock_{-1};
  void* session_{nullptr};   // LIBSSH2_SESSION*
  void* channel_{nullptr};   // LIBSSH2_CHANNEL*
  std::string lastError_;
  std::string lastHostKeyFingerprint_;
  HostKeyCallback hostKeyCallback_;
  std::string knownHostsPath_;

  bool InitLibssh2();
  void CleanupUnlocked();
  /** Record fingerprint stub; invokes callback if set. Returns false to abort. */
  bool CheckHostKeyUnlocked(const ConnectParams& params, void* session);
};

bool Libssh2Available();

}  // namespace hmssh

#endif
