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
};

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
