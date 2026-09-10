#include "ssh_client.h"

#include <cstring>
#include <mutex>

#if defined(HMSSH_HAS_LIBSSH2)
#include <libssh2.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#endif

namespace hmssh {

bool Libssh2Available() {
#if defined(HMSSH_HAS_LIBSSH2)
  return true;
#else
  return false;
#endif
}

SshClient::SshClient() = default;

SshClient::~SshClient() {
  Disconnect();
}

bool SshClient::InitLibssh2() {
#if defined(HMSSH_HAS_LIBSSH2)
  static std::once_flag once;
  static bool ok = false;
  std::call_once(once, []() {
    ok = (libssh2_init(0) == 0);
  });
  return ok;
#else
  return false;
#endif
}

void SshClient::CleanupUnlocked() {
#if defined(HMSSH_HAS_LIBSSH2)
  if (channel_) {
    auto* ch = static_cast<LIBSSH2_CHANNEL*>(channel_);
    libssh2_channel_close(ch);
    libssh2_channel_free(ch);
    channel_ = nullptr;
  }
  if (session_) {
    auto* sess = static_cast<LIBSSH2_SESSION*>(session_);
    libssh2_session_disconnect(sess, "HmSSH disconnect");
    libssh2_session_free(sess);
    session_ = nullptr;
  }
  if (sock_ >= 0) {
    close(sock_);
    sock_ = -1;
  }
#endif
  connected_ = false;
}

void SshClient::SetHostKeyCallback(HostKeyCallback cb) {
  std::lock_guard<std::mutex> lock(mu_);
  hostKeyCallback_ = std::move(cb);
}

std::string SshClient::LastHostKeyFingerprint() {
  std::lock_guard<std::mutex> lock(mu_);
  return lastHostKeyFingerprint_;
}

bool SshClient::CheckHostKeyUnlocked(const ConnectParams& params, void* session) {
  // Stub: produce a deterministic placeholder fingerprint for UI confirm.
  // When HMSSH_HAS_LIBSSH2: prefer libssh2_session_hostkey + SHA256.
  std::string fp = "SHA256:pending-hostkey-verify";
#if defined(HMSSH_HAS_LIBSSH2)
  if (session) {
    size_t len = 0;
    int type = 0;
    const char* key = libssh2_session_hostkey(static_cast<LIBSSH2_SESSION*>(session), &len, &type);
    if (key && len > 0) {
      // Lightweight hex prefix — full SHA256 base64 TODO (needs OpenSSL EVP or libssh2 hash helpers)
      char buf[64];
      size_t n = len < 16 ? len : 16;
      static const char* hex = "0123456789abcdef";
      std::string hx;
      hx.reserve(n * 2);
      for (size_t i = 0; i < n; ++i) {
        unsigned char c = static_cast<unsigned char>(key[i]);
        hx.push_back(hex[(c >> 4) & 0xf]);
        hx.push_back(hex[c & 0xf]);
      }
      fp = "SHA256-stub:" + hx;
      (void)buf;
      (void)type;
    }
    // TODO(DevEco): libssh2_knownhost_readfile(params.knownHostsPath) + check
    if (!params.knownHostsPath.empty()) {
      // Path recorded for future known_hosts check; currently advisory only.
      knownHostsPath_ = params.knownHostsPath;
    }
  }
#else
  (void)session;
  if (!params.knownHostsPath.empty()) {
    knownHostsPath_ = params.knownHostsPath;
  }
#endif
  lastHostKeyFingerprint_ = fp;
  if (hostKeyCallback_) {
    return hostKeyCallback_(params.host, params.port, fp);
  }
  return true;
}

std::string SshClient::Connect(const ConnectParams& params) {
  std::lock_guard<std::mutex> lock(mu_);
  CleanupUnlocked();

#if !defined(HMSSH_HAS_LIBSSH2)
  lastError_ =
      "libssh2 未链接：请按 native/README.md 在 DevEco 中启用 HMSSH_HAS_LIBSSH2 并 vendoring libssh2";
  return lastError_;
#else
  if (!InitLibssh2()) {
    lastError_ = "libssh2_init failed";
    return lastError_;
  }

  struct addrinfo hints {};
  struct addrinfo* res = nullptr;
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  std::string portStr = std::to_string(params.port);
  if (getaddrinfo(params.host.c_str(), portStr.c_str(), &hints, &res) != 0 || !res) {
    lastError_ = "DNS resolve failed: " + params.host;
    return lastError_;
  }

  sock_ = -1;
  for (auto* p = res; p; p = p->ai_next) {
    int fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
    if (fd < 0) {
      continue;
    }
    if (connect(fd, p->ai_addr, p->ai_addrlen) == 0) {
      sock_ = fd;
      break;
    }
    close(fd);
  }
  freeaddrinfo(res);
  if (sock_ < 0) {
    lastError_ = "TCP connect failed";
    return lastError_;
  }

  LIBSSH2_SESSION* sess = libssh2_session_init();
  if (!sess) {
    CleanupUnlocked();
    lastError_ = "libssh2_session_init failed";
    return lastError_;
  }
  session_ = sess;
  libssh2_session_set_blocking(sess, 1);

  if (libssh2_session_handshake(sess, sock_) != 0) {
    char* msg = nullptr;
    int len = 0;
    libssh2_session_last_error(sess, &msg, &len, 0);
    lastError_ = msg ? std::string(msg, len) : "SSH handshake failed";
    CleanupUnlocked();
    return lastError_;
  }

  if (!CheckHostKeyUnlocked(params, sess)) {
    lastError_ = "host key rejected (fingerprint=" + lastHostKeyFingerprint_ + ")";
    CleanupUnlocked();
    return lastError_;
  }

  int rc = -1;
  if (!params.privateKey.empty()) {
    rc = libssh2_userauth_publickey_frommemory(
        sess, params.username.c_str(), params.username.size(),
        nullptr, 0,
        params.privateKey.c_str(), params.privateKey.size(),
        params.password.empty() ? nullptr : params.password.c_str());
  } else {
    rc = libssh2_userauth_password(sess, params.username.c_str(), params.password.c_str());
  }
  if (rc != 0) {
    char* msg = nullptr;
    int len = 0;
    libssh2_session_last_error(sess, &msg, &len, 0);
    lastError_ = msg ? std::string(msg, len) : "SSH auth failed";
    CleanupUnlocked();
    return lastError_;
  }

  LIBSSH2_CHANNEL* ch = libssh2_channel_open_session(sess);
  if (!ch) {
    lastError_ = "open session channel failed";
    CleanupUnlocked();
    return lastError_;
  }
  channel_ = ch;
  if (libssh2_channel_request_pty(ch, "xterm") != 0) {
    lastError_ = "PTY request failed";
    CleanupUnlocked();
    return lastError_;
  }
  if (libssh2_channel_shell(ch) != 0) {
    lastError_ = "shell request failed";
    CleanupUnlocked();
    return lastError_;
  }
  connected_ = true;
  lastError_.clear();
  return "";
#endif
}

void SshClient::Disconnect() {
  std::lock_guard<std::mutex> lock(mu_);
  CleanupUnlocked();
}

bool SshClient::IsConnected() const {
  return connected_.load();
}

std::string SshClient::Send(const std::string& data) {
  std::lock_guard<std::mutex> lock(mu_);
#if !defined(HMSSH_HAS_LIBSSH2)
  return "libssh2 not linked";
#else
  if (!connected_ || !channel_) {
    return "not connected";
  }
  auto* ch = static_cast<LIBSSH2_CHANNEL*>(channel_);
  size_t off = 0;
  while (off < data.size()) {
    ssize_t n = libssh2_channel_write(ch, data.data() + off, data.size() - off);
    if (n < 0) {
      return "channel write failed";
    }
    off += static_cast<size_t>(n);
  }
  return "";
#endif
}

std::string SshClient::Read(int maxBytes) {
  std::lock_guard<std::mutex> lock(mu_);
#if !defined(HMSSH_HAS_LIBSSH2)
  return "";
#else
  if (!connected_ || !channel_) {
    return "";
  }
  auto* ch = static_cast<LIBSSH2_CHANNEL*>(channel_);
  std::string out;
  out.resize(static_cast<size_t>(maxBytes > 0 ? maxBytes : 16384));
  ssize_t n = libssh2_channel_read(ch, out.data(), out.size());
  if (n > 0) {
    out.resize(static_cast<size_t>(n));
    return out;
  }
  return "";
#endif
}

std::string SshClient::Resize(int cols, int rows) {
  std::lock_guard<std::mutex> lock(mu_);
#if !defined(HMSSH_HAS_LIBSSH2)
  return "libssh2 not linked";
#else
  if (!connected_ || !channel_) {
    return "not connected";
  }
  auto* ch = static_cast<LIBSSH2_CHANNEL*>(channel_);
  if (libssh2_channel_request_pty_size(ch, cols, rows) != 0) {
    return "pty resize failed";
  }
  return "";
#endif
}

}  // namespace hmssh
