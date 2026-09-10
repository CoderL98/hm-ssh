#ifndef HMSSH_NATIVE_FTP_CLIENT_H
#define HMSSH_NATIVE_FTP_CLIENT_H

#include "common.h"

namespace hmssh {

struct FtpListEntry {
  std::string name;
  std::string path;
  bool isDirectory{false};
  int64_t size{0};
  int64_t modifiedAt{0};
};

/**
 * Minimal FTP client (control + PASV data). Uses BSD sockets available on OHOS.
 */
class FtpClient {
 public:
  FtpClient();
  ~FtpClient();

  FtpClient(const FtpClient&) = delete;
  FtpClient& operator=(const FtpClient&) = delete;

  std::string Connect(const ConnectParams& params);
  void Disconnect();
  bool IsConnected() const;
  std::string GetCwd() const;
  std::string Cd(const std::string& path);
  std::string List(std::vector<FtpListEntry>& out);
  /** RETR to local sandbox path; returns error or empty. */
  std::string Retr(const std::string& remotePath, const std::string& localPath);
  /** STOR from local sandbox path; returns error or empty. */
  std::string Stor(const std::string& remotePath, const std::string& localPath);

 private:
  mutable std::mutex mu_;
  bool connected_{false};
  int ctrlSock_{-1};
  std::string cwd_{"/"};
  std::string lastReply_;

  bool ReadReply(std::string& code, std::string& text);
  bool SendCmd(const std::string& cmd, std::string& code, std::string& text);
  int OpenPasvDataSocket(std::string& err);
  static int ConnectTcp(const std::string& host, int port, std::string& err);
  static void CloseSock(int& fd);
};

}  // namespace hmssh

#endif
