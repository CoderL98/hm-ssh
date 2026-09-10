#ifndef HMSSH_NATIVE_COMMON_H
#define HMSSH_NATIVE_COMMON_H

#include <cstdint>
#include <string>
#include <vector>
#include <mutex>
#include <memory>
#include <functional>

namespace hmssh {

struct ConnectParams {
  std::string host;
  int port{22};
  std::string username;
  std::string password;
  std::string privateKey;
  /** Optional OpenSSH known_hosts file path (SSH). Empty = skip file check. */
  std::string knownHostsPath;
  /**
   * FTP: when true, request explicit FTPS (AUTH TLS) after greeting.
   * Requires OpenSSL linked; otherwise Connect returns a clear TODO error.
   */
  bool useTls{false};
};

/**
 * Host-key callback stub: records fingerprint for ArkTS / UI confirm.
 * When set, SSH Connect invokes it with "SHA256:..." style fingerprint.
 * Return true to accept, false to abort connect.
 * Default (unset) accepts and stores last fingerprint on the client.
 */
using HostKeyCallback = std::function<bool(const std::string& host,
                                           int port,
                                           const std::string& fingerprint)>;

inline std::string Trim(const std::string& s) {
  size_t b = 0;
  while (b < s.size() && (s[b] == ' ' || s[b] == '\t' || s[b] == '\r' || s[b] == '\n')) {
    ++b;
  }
  size_t e = s.size();
  while (e > b && (s[e - 1] == ' ' || s[e - 1] == '\t' || s[e - 1] == '\r' || s[e - 1] == '\n')) {
    --e;
  }
  return s.substr(b, e - b);
}

}  // namespace hmssh

#endif
