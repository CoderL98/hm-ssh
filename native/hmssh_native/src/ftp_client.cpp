#include "ftp_client.h"

#include <cstdio>
#include <cctype>
#include <cstdlib>
#include <mutex>
#include <cstring>
#include <fstream>
#include <sstream>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <errno.h>

namespace hmssh {

FtpClient::FtpClient() = default;

FtpClient::~FtpClient() {
  Disconnect();
}

void FtpClient::CloseSock(int& fd) {
  if (fd >= 0) {
    ::close(fd);
    fd = -1;
  }
}

int FtpClient::ConnectTcp(const std::string& host, int port, std::string& err) {
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
    if (::connect(fd, p->ai_addr, p->ai_addrlen) == 0) {
      sock = fd;
      break;
    }
    ::close(fd);
  }
  freeaddrinfo(res);
  if (sock < 0) {
    err = "TCP connect failed";
  }
  return sock;
}

bool FtpClient::ReadReply(std::string& code, std::string& text) {
  text.clear();
  code.clear();
  char buf[512];
  std::string acc;
  while (true) {
    ssize_t n = ::recv(ctrlSock_, buf, sizeof(buf), 0);
    if (n <= 0) {
      return false;
    }
    acc.append(buf, static_cast<size_t>(n));
    // Look for complete last line: "XYZ <text>\r\n" where XYZ digits and space (final) or '-' (multi)
    size_t pos = 0;
    while (true) {
      size_t nl = acc.find("\r\n", pos);
      if (nl == std::string::npos) break;
      std::string line = acc.substr(pos, nl - pos);
      pos = nl + 2;
      if (line.size() >= 4 && std::isdigit(static_cast<unsigned char>(line[0])) &&
          std::isdigit(static_cast<unsigned char>(line[1])) &&
          std::isdigit(static_cast<unsigned char>(line[2])) && line[3] == ' ') {
        code = line.substr(0, 3);
        text = line.substr(4);
        lastReply_ = acc;
        return true;
      }
    }
    if (pos > 0) {
      acc.erase(0, pos);
    }
  }
}

bool FtpClient::SendCmd(const std::string& cmd, std::string& code, std::string& text) {
  std::string wire = cmd + "\r\n";
  if (::send(ctrlSock_, wire.data(), wire.size(), 0) < 0) {
    return false;
  }
  return ReadReply(code, text);
}

std::string FtpClient::Connect(const ConnectParams& params) {
  std::lock_guard<std::mutex> lock(mu_);
  Disconnect();
  std::string err;
  ctrlSock_ = ConnectTcp(params.host, params.port, err);
  if (ctrlSock_ < 0) {
    return err;
  }
  std::string code, text;
  if (!ReadReply(code, text) || code[0] != '2') {
    CloseSock(ctrlSock_);
    return "FTP greeting failed: " + text;
  }
  tlsRequested_ = params.useTls;
  if (params.useTls) {
    // Explicit FTPS (AUTH TLS) hook — requires OpenSSL/mbedTLS on control socket.
    // TODO(DevEco): AUTH TLS + PBSZ 0 + PROT P after linking TLS.
    CloseSock(ctrlSock_);
    return "FTPS/TLS requested but OpenSSL not linked (TODO: AUTH TLS); unset useTls or enable TLS in native build";
  }
  if (!SendCmd("USER " + params.username, code, text)) {
    CloseSock(ctrlSock_);
    return "USER failed";
  }
  if (code == "331") {
    if (!SendCmd("PASS " + params.password, code, text) || code[0] != '2') {
      CloseSock(ctrlSock_);
      return "PASS failed: " + text;
    }
  } else if (code[0] != '2') {
    CloseSock(ctrlSock_);
    return "USER rejected: " + text;
  }
  connected_ = true;
  cwd_ = "/";
  if (!params.privateKey.empty()) {
    // unused for FTP; remotePath carried via username? ignore
  }
  // optional CWD if host path encoded in password field? ArkTS passes remotePath separately via Cd
  return "";
}

void FtpClient::Disconnect() {
  std::lock_guard<std::mutex> lock(mu_);
  if (ctrlSock_ >= 0 && connected_) {
    std::string code, text;
    SendCmd("QUIT", code, text);
  }
  CloseSock(ctrlSock_);
  connected_ = false;
  cwd_ = "/";
}

bool FtpClient::IsConnected() const {
  std::lock_guard<std::mutex> lock(mu_);
  return connected_;
}

std::string FtpClient::GetCwd() const {
  std::lock_guard<std::mutex> lock(mu_);
  return cwd_;
}

std::string FtpClient::Cd(const std::string& path) {
  std::lock_guard<std::mutex> lock(mu_);
  if (!connected_) return "not connected";
  std::string code, text;
  if (!SendCmd("CWD " + path, code, text) || code[0] != '2') {
    return "CWD failed: " + text;
  }
  // PWD
  if (SendCmd("PWD", code, text) && code[0] == '2') {
    // 257 "path"
    auto q1 = text.find('"');
    auto q2 = text.find('"', q1 == std::string::npos ? 0 : q1 + 1);
    if (q1 != std::string::npos && q2 != std::string::npos && q2 > q1) {
      cwd_ = text.substr(q1 + 1, q2 - q1 - 1);
    } else {
      cwd_ = path;
    }
  } else {
    cwd_ = path;
  }
  return "";
}

int FtpClient::OpenPasvDataSocket(std::string& err) {
  std::string code, text;
  if (!SendCmd("PASV", code, text) || code != "227") {
    err = "PASV failed: " + text;
    return -1;
  }
  // 227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)
  auto l = text.find('(');
  auto r = text.find(')');
  if (l == std::string::npos || r == std::string::npos || r <= l) {
    err = "PASV parse failed";
    return -1;
  }
  std::string inside = text.substr(l + 1, r - l - 1);
  int h1=0,h2=0,h3=0,h4=0,p1=0,p2=0;
  if (std::sscanf(inside.c_str(), "%d,%d,%d,%d,%d,%d", &h1,&h2,&h3,&h4,&p1,&p2) != 6) {
    err = "PASV numbers parse failed";
    return -1;
  }
  char ip[64];
  std::snprintf(ip, sizeof(ip), "%d.%d.%d.%d", h1, h2, h3, h4);
  int port = p1 * 256 + p2;
  return ConnectTcp(ip, port, err);
}

static void ParseListLine(const std::string& line, const std::string& cwd, std::vector<FtpListEntry>& out) {
  if (line.empty()) return;
  // Prefer MLSD-like or UNIX ls -l
  FtpListEntry e;
  e.modifiedAt = 0;
  if (line.find(';') != std::string::npos && line.find("type=") != std::string::npos) {
    // MLSD: type=file;size=123; name
    e.isDirectory = line.find("type=dir") != std::string::npos || line.find("type=cdir") != std::string::npos ||
                    line.find("type=pdir") != std::string::npos;
    auto sp = line.find(' ');
    std::string facts = sp == std::string::npos ? line : line.substr(0, sp);
    e.name = sp == std::string::npos ? "" : line.substr(sp + 1);
    auto sz = facts.find("size=");
    if (sz != std::string::npos) {
      e.size = std::atoll(facts.c_str() + sz + 5);
    }
  } else {
    // UNIX: drwxr-xr-x ... name
    e.isDirectory = !line.empty() && line[0] == 'd';
    std::istringstream iss(line);
    std::string perm, links, owner, group, sizeStr, month, day, timeOrYear, name;
    if (!(iss >> perm >> links >> owner >> group >> sizeStr >> month >> day >> timeOrYear)) {
      return;
    }
    std::getline(iss, name);
    name = Trim(name);
    if (name == "." || name == "..") return;
    e.name = name;
    e.size = std::atoll(sizeStr.c_str());
  }
  if (e.name.empty() || e.name == "." || e.name == "..") return;
  if (cwd == "/") e.path = "/" + e.name;
  else e.path = cwd + "/" + e.name;
  out.push_back(e);
}

std::string FtpClient::List(std::vector<FtpListEntry>& out) {
  std::lock_guard<std::mutex> lock(mu_);
  out.clear();
  if (!connected_) return "not connected";
  std::string err;
  int data = OpenPasvDataSocket(err);
  if (data < 0) return err;
  std::string code, text;
  // Try MLSD then LIST
  bool ok = SendCmd("MLSD", code, text);
  if (!ok || (code[0] != '1' && code[0] != '2')) {
    ok = SendCmd("LIST", code, text);
  }
  if (!ok || (code[0] != '1' && code[0] != '2')) {
    CloseSock(data);
    return "LIST failed: " + text;
  }
  std::string body;
  char buf[1024];
  while (true) {
    ssize_t n = ::recv(data, buf, sizeof(buf), 0);
    if (n <= 0) break;
    body.append(buf, static_cast<size_t>(n));
  }
  CloseSock(data);
  // consume final reply if 1xx
  if (code[0] == '1') {
    ReadReply(code, text);
  }
  size_t start = 0;
  while (start < body.size()) {
    size_t nl = body.find('\n', start);
    std::string line = (nl == std::string::npos) ? body.substr(start) : body.substr(start, nl - start);
    if (!line.empty() && line.back() == '\r') line.pop_back();
    ParseListLine(line, cwd_, out);
    if (nl == std::string::npos) break;
    start = nl + 1;
  }
  return "";
}

std::string FtpClient::Retr(const std::string& remotePath, const std::string& localPath) {
  std::lock_guard<std::mutex> lock(mu_);
  if (!connected_) return "not connected";
  std::string err;
  int data = OpenPasvDataSocket(err);
  if (data < 0) return err;
  std::string code, text;
  if (!SendCmd("RETR " + remotePath, code, text) || (code[0] != '1' && code[0] != '2')) {
    CloseSock(data);
    return "RETR failed: " + text;
  }
  std::ofstream ofs(localPath, std::ios::binary);
  if (!ofs) {
    CloseSock(data);
    return "cannot open local path: " + localPath;
  }
  char buf[4096];
  while (true) {
    ssize_t n = ::recv(data, buf, sizeof(buf), 0);
    if (n <= 0) break;
    ofs.write(buf, n);
  }
  CloseSock(data);
  if (code[0] == '1') ReadReply(code, text);
  return "";
}

std::string FtpClient::Stor(const std::string& remotePath, const std::string& localPath) {
  std::lock_guard<std::mutex> lock(mu_);
  if (!connected_) return "not connected";
  std::ifstream ifs(localPath, std::ios::binary);
  if (!ifs) return "cannot open local path: " + localPath;
  std::string err;
  int data = OpenPasvDataSocket(err);
  if (data < 0) return err;
  std::string code, text;
  if (!SendCmd("STOR " + remotePath, code, text) || (code[0] != '1' && code[0] != '2')) {
    CloseSock(data);
    return "STOR failed: " + text;
  }
  char buf[4096];
  while (ifs) {
    ifs.read(buf, sizeof(buf));
    std::streamsize n = ifs.gcount();
    if (n <= 0) break;
    ssize_t off = 0;
    while (off < n) {
      ssize_t w = ::send(data, buf + off, static_cast<size_t>(n - off), 0);
      if (w <= 0) {
        CloseSock(data);
        return "STOR data send failed";
      }
      off += w;
    }
  }
  CloseSock(data);
  if (code[0] == '1') ReadReply(code, text);
  return "";
}

}  // namespace hmssh
