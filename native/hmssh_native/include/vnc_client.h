#ifndef HMSSH_NATIVE_VNC_CLIENT_H
#define HMSSH_NATIVE_VNC_CLIENT_H

#include "common.h"

namespace hmssh {

struct VncFramebuffer {
  int width{0};
  int height{0};
  /** RGBA8888 pixel buffer (width * height * 4). */
  std::vector<uint8_t> rgba;
};

/**
 * Minimal RFB 3.8 client:
 * - ProtocolVersion handshake
 * - SecurityType None (1) or VNC Authentication (2)
 * - ClientInit / ServerInit
 * - FramebufferUpdateRequest + Raw encoding (TODO: CopyRect / tight / zrle)
 */
class VncClient {
 public:
  VncClient();
  ~VncClient();

  VncClient(const VncClient&) = delete;
  VncClient& operator=(const VncClient&) = delete;

  std::string Connect(const ConnectParams& params);
  void Disconnect();
  bool IsConnected() const;
  std::string GetFramebuffer(VncFramebuffer& out);
  std::string PointerEvent(int x, int y, int buttons);
  std::string KeyEvent(uint32_t keysym, bool down);
  /** Poll for FramebufferUpdate; fills rgba on Raw rectangles. */
  std::string PollUpdate();

 private:
  mutable std::mutex mu_;
  bool connected_{false};
  int sock_{-1};
  int width_{0};
  int height_{0};
  std::vector<uint8_t> rgba_;
  uint8_t challenge_[16]{};

  bool RecvAll(void* buf, size_t n);
  bool SendAll(const void* buf, size_t n);
  bool Handshake(const std::string& password, std::string& err);
  bool SecurityNone(std::string& err);
  bool SecurityVncAuth(const std::string& password, std::string& err);
  void FillPlaceholderDesktop();
  static int ConnectTcp(const std::string& host, int port, std::string& err);
  static void CloseSock(int& fd);
};

}  // namespace hmssh

#endif
