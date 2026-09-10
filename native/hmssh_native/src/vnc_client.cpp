#include "vnc_client.h"
#include "vnc_des.inc"

#include <cstring>
#include <cstdio>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>

namespace hmssh {

static void BitReverse8(uint8_t* key) {
  for (int i = 0; i < 8; ++i) {
    uint8_t b = key[i];
    b = static_cast<uint8_t>(((b * 0x0802LU & 0x22110LU) | (b * 0x8020LU & 0x88440LU)) * 0x10101LU >> 16);
    key[i] = b;
  }
}

static void VncDesEncrypt(const uint8_t password[8], const uint8_t challenge[16], uint8_t response[16]) {
  uint8_t key[8];
  std::memcpy(key, password, 8);
  BitReverse8(key);
  HmsshDesEncryptBlock(key, challenge, response);
  HmsshDesEncryptBlock(key, challenge + 8, response + 8);
}

VncClient::VncClient() = default;
VncClient::~VncClient() { Disconnect(); }

void VncClient::CloseSock(int& fd) {
  if (fd >= 0) { ::close(fd); fd = -1; }
}

int VncClient::ConnectTcp(const std::string& host, int port, std::string& err) {
  struct addrinfo hints {};
  struct addrinfo* res = nullptr;
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  std::string portStr = std::to_string(port);
  if (getaddrinfo(host.c_str(), portStr.c_str(), &hints, &res) != 0 || !res) {
    err = "DNS resolve failed: " + host;
    return -1;
  }
  int sock = -1;
  for (auto* p = res; p; p = p->ai_next) {
    int fd = ::socket(p->ai_family, p->ai_socktype, p->ai_protocol);
    if (fd < 0) continue;
    if (::connect(fd, p->ai_addr, p->ai_addrlen) == 0) { sock = fd; break; }
    ::close(fd);
  }
  freeaddrinfo(res);
  if (sock < 0) err = "TCP connect failed";
  return sock;
}

bool VncClient::RecvAll(void* buf, size_t n) {
  auto* p = static_cast<uint8_t*>(buf);
  size_t off = 0;
  while (off < n) {
    ssize_t r = ::recv(sock_, p + off, n - off, 0);
    if (r <= 0) return false;
    off += static_cast<size_t>(r);
  }
  return true;
}

bool VncClient::SendAll(const void* buf, size_t n) {
  auto* p = static_cast<const uint8_t*>(buf);
  size_t off = 0;
  while (off < n) {
    ssize_t w = ::send(sock_, p + off, n - off, 0);
    if (w <= 0) return false;
    off += static_cast<size_t>(w);
  }
  return true;
}

void VncClient::FillPlaceholderDesktop() {
  rgba_.assign(static_cast<size_t>(width_ * height_ * 4), 0);
  for (int y = 0; y < height_; ++y) {
    for (int x = 0; x < width_; ++x) {
      size_t i = static_cast<size_t>((y * width_ + x) * 4);
      bool grid = ((x / 32) + (y / 32)) % 2 == 0;
      rgba_[i + 0] = grid ? 0x1A : 0x22;
      rgba_[i + 1] = grid ? 0x23 : 0x2B;
      rgba_[i + 2] = grid ? 0x32 : 0x3A;
      rgba_[i + 3] = 0xFF;
    }
  }
}

bool VncClient::SecurityNone(std::string& err) {
  uint8_t result[4];
  if (!RecvAll(result, 4)) { err = "SecurityResult recv failed"; return false; }
  uint32_t r = (result[0] << 24) | (result[1] << 16) | (result[2] << 8) | result[3];
  if (r != 0) { err = "Security failed (None)"; return false; }
  return true;
}

bool VncClient::SecurityVncAuth(const std::string& password, std::string& err) {
  if (!RecvAll(challenge_, 16)) { err = "VNC challenge recv failed"; return false; }
  uint8_t key[8]{};
  for (size_t i = 0; i < 8 && i < password.size(); ++i) key[i] = static_cast<uint8_t>(password[i]);
  uint8_t response[16];
  VncDesEncrypt(key, challenge_, response);
  if (!SendAll(response, 16)) { err = "VNC auth response send failed"; return false; }
  uint8_t result[4];
  if (!RecvAll(result, 4)) { err = "SecurityResult recv failed"; return false; }
  uint32_t r = (result[0] << 24) | (result[1] << 16) | (result[2] << 8) | result[3];
  if (r != 0) { err = "VNC authentication failed"; return false; }
  return true;
}

bool VncClient::Handshake(const std::string& password, std::string& err) {
  char ver[12];
  if (!RecvAll(ver, 12)) { err = "ProtocolVersion recv failed"; return false; }
  const char* mine = "RFB 003.008\n";
  if (!SendAll(mine, 12)) { err = "ProtocolVersion send failed"; return false; }
  uint8_t nTypes = 0;
  if (!RecvAll(&nTypes, 1)) { err = "security types count failed"; return false; }
  if (nTypes == 0) {
    uint8_t lenb[4];
    if (!RecvAll(lenb, 4)) { err = "security failure"; return false; }
    uint32_t len = (lenb[0] << 24) | (lenb[1] << 16) | (lenb[2] << 8) | lenb[3];
    std::string reason(len, '\0');
    if (len && !RecvAll(reason.data(), len)) { err = "security failure (no reason)"; return false; }
    err = "server rejected: " + reason;
    return false;
  }
  std::vector<uint8_t> types(nTypes);
  if (!RecvAll(types.data(), nTypes)) { err = "security types list failed"; return false; }
  bool hasNone = false, hasVnc = false;
  for (uint8_t t : types) { if (t == 1) hasNone = true; if (t == 2) hasVnc = true; }
  uint8_t chosen = 0;
  if (!password.empty() && hasVnc) chosen = 2;
  else if (hasNone) chosen = 1;
  else if (hasVnc) chosen = 2;
  else { err = "no supported security type (need None/VNC Auth)"; return false; }
  if (!SendAll(&chosen, 1)) { err = "security type send failed"; return false; }
  if (chosen == 1) { if (!SecurityNone(err)) return false; }
  else { if (!SecurityVncAuth(password, err)) return false; }
  uint8_t shared = 0;
  if (!SendAll(&shared, 1)) { err = "ClientInit failed"; return false; }
  uint8_t hdr[24];
  if (!RecvAll(hdr, 24)) { err = "ServerInit failed"; return false; }
  width_ = (hdr[0] << 8) | hdr[1];
  height_ = (hdr[2] << 8) | hdr[3];
  uint32_t nameLen = (hdr[20] << 24) | (hdr[21] << 16) | (hdr[22] << 8) | hdr[23];
  if (nameLen > 0) {
    std::vector<uint8_t> name(nameLen);
    if (!RecvAll(name.data(), nameLen)) { err = "desktop name recv failed"; return false; }
  }
  if (width_ <= 0 || height_ <= 0 || width_ > 8192 || height_ > 8192) {
    err = "invalid framebuffer size"; return false;
  }
  uint8_t setEnc[8] = {2, 0, 0, 1, 0, 0, 0, 0};
  SendAll(setEnc, sizeof(setEnc));
  uint8_t spf[20] = {0};
  spf[4] = 32; spf[5] = 24; spf[6] = 0; spf[7] = 1;
  spf[8] = 0; spf[9] = 255; spf[10] = 0; spf[11] = 255; spf[12] = 0; spf[13] = 255;
  spf[14] = 0; spf[15] = 8; spf[16] = 16;
  SendAll(spf, sizeof(spf));
  FillPlaceholderDesktop();
  uint8_t fur[10] = {
      3, 0, 0, 0, 0, 0,
      static_cast<uint8_t>((width_ >> 8) & 0xff), static_cast<uint8_t>(width_ & 0xff),
      static_cast<uint8_t>((height_ >> 8) & 0xff), static_cast<uint8_t>(height_ & 0xff)};
  SendAll(fur, sizeof(fur));
  return true;
}

std::string VncClient::Connect(const ConnectParams& params) {
  std::lock_guard<std::mutex> lock(mu_);
  Disconnect();
  std::string err;
  sock_ = ConnectTcp(params.host, params.port, err);
  if (sock_ < 0) return err;
  if (!Handshake(params.password, err)) { CloseSock(sock_); return err; }
  connected_ = true;
  return "";
}

void VncClient::Disconnect() {
  std::lock_guard<std::mutex> lock(mu_);
  CloseSock(sock_);
  connected_ = false;
  width_ = height_ = 0;
  rgba_.clear();
}

bool VncClient::IsConnected() const {
  std::lock_guard<std::mutex> lock(mu_);
  return connected_;
}

std::string VncClient::GetFramebuffer(VncFramebuffer& out) {
  std::lock_guard<std::mutex> lock(mu_);
  if (!connected_) return "not connected";
  out.width = width_;
  out.height = height_;
  out.rgba = rgba_;
  return "";
}

std::string VncClient::PointerEvent(int x, int y, int buttons) {
  std::lock_guard<std::mutex> lock(mu_);
  if (!connected_) return "not connected";
  uint8_t msg[6] = {
      5, static_cast<uint8_t>(buttons & 0xff),
      static_cast<uint8_t>((x >> 8) & 0xff), static_cast<uint8_t>(x & 0xff),
      static_cast<uint8_t>((y >> 8) & 0xff), static_cast<uint8_t>(y & 0xff)};
  if (!SendAll(msg, sizeof(msg))) return "pointer send failed";
  return "";
}

std::string VncClient::KeyEvent(uint32_t keysym, bool down) {
  std::lock_guard<std::mutex> lock(mu_);
  if (!connected_) return "not connected";
  uint8_t msg[8] = {
      4, static_cast<uint8_t>(down ? 1 : 0), 0, 0,
      static_cast<uint8_t>((keysym >> 24) & 0xff), static_cast<uint8_t>((keysym >> 16) & 0xff),
      static_cast<uint8_t>((keysym >> 8) & 0xff), static_cast<uint8_t>(keysym & 0xff)};
  if (!SendAll(msg, sizeof(msg))) return "key send failed";
  return "";
}

std::string VncClient::PollUpdate() {
  std::lock_guard<std::mutex> lock(mu_);
  if (!connected_) return "not connected";
  uint8_t type = 0;
  ssize_t n = ::recv(sock_, &type, 1, MSG_DONTWAIT);
  if (n == 0) { connected_ = false; return "connection closed"; }
  if (n < 0) return "";
  if (type != 0) return "";
  uint8_t pad_nrect[3];
  if (!RecvAll(pad_nrect, 3)) return "FBU header failed";
  uint16_t nRects = (pad_nrect[1] << 8) | pad_nrect[2];
  for (uint16_t i = 0; i < nRects; ++i) {
    uint8_t rh[12];
    if (!RecvAll(rh, 12)) return "rect header failed";
    int x = (rh[0] << 8) | rh[1];
    int y = (rh[2] << 8) | rh[3];
    int w = (rh[4] << 8) | rh[5];
    int h = (rh[6] << 8) | rh[7];
    int32_t enc = (rh[8] << 24) | (rh[9] << 16) | (rh[10] << 8) | rh[11];
    if (enc == 0) {
      size_t nbytes = static_cast<size_t>(w) * static_cast<size_t>(h) * 4;
      std::vector<uint8_t> pix(nbytes);
      if (!RecvAll(pix.data(), nbytes)) return "raw pixels failed";
      for (int row = 0; row < h; ++row) {
        int dy = y + row;
        if (dy < 0 || dy >= height_) continue;
        for (int col = 0; col < w; ++col) {
          int dx = x + col;
          if (dx < 0 || dx >= width_) continue;
          size_t src = static_cast<size_t>((row * w + col) * 4);
          size_t dst = static_cast<size_t>((dy * width_ + dx) * 4);
          rgba_[dst + 0] = pix[src + 2];
          rgba_[dst + 1] = pix[src + 1];
          rgba_[dst + 2] = pix[src + 0];
          rgba_[dst + 3] = 0xFF;
        }
      }
    } else {
      return "unsupported encoding " + std::to_string(enc) + " (only Raw; TODO CopyRect)";
    }
  }
  uint8_t fur[10] = {
      3, 1, 0, 0, 0, 0,
      static_cast<uint8_t>((width_ >> 8) & 0xff), static_cast<uint8_t>(width_ & 0xff),
      static_cast<uint8_t>((height_ >> 8) & 0xff), static_cast<uint8_t>(height_ & 0xff)};
  SendAll(fur, sizeof(fur));
  return "";
}

}  // namespace hmssh
