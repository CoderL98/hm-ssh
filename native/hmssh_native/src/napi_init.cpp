#include "ssh_client.h"
#include "ftp_client.h"
#include "vnc_client.h"

#include <napi/native_api.h>
#include <map>
#include <mutex>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace {

std::mutex gMu;
int gNextId = 1;
std::map<int, std::unique_ptr<hmssh::SshClient>> gSsh;
std::map<int, std::unique_ptr<hmssh::FtpClient>> gFtp;
std::map<int, std::unique_ptr<hmssh::VncClient>> gVnc;

std::string GetStringProp(napi_env env, napi_value obj, const char* key) {
  napi_value v;
  if (napi_get_named_property(env, obj, key, &v) != napi_ok) return "";
  size_t len = 0;
  napi_get_value_string_utf8(env, v, nullptr, 0, &len);
  std::string s(len, '\0');
  if (len > 0) {
    napi_get_value_string_utf8(env, v, &s[0], len + 1, &len);
    s.resize(len);
  }
  return s;
}

int GetIntProp(napi_env env, napi_value obj, const char* key, int def) {
  napi_value v;
  if (napi_get_named_property(env, obj, key, &v) != napi_ok) return def;
  int32_t out = def;
  napi_get_value_int32(env, v, &out);
  return out;
}

bool GetBoolProp(napi_env env, napi_value obj, const char* key, bool def) {
  napi_value v;
  if (napi_get_named_property(env, obj, key, &v) != napi_ok) return def;
  bool out = def;
  napi_get_value_bool(env, v, &out);
  return out;
}

napi_value MakeString(napi_env env, const std::string& s) {
  napi_value out;
  napi_create_string_utf8(env, s.c_str(), s.size(), &out);
  return out;
}

napi_value MakeInt(napi_env env, int v) {
  napi_value out;
  napi_create_int32(env, v, &out);
  return out;
}

napi_value MakeBool(napi_env env, bool v) {
  napi_value out;
  napi_get_boolean(env, v, &out);
  return out;
}

hmssh::ConnectParams ParseConnect(napi_env env, napi_value obj) {
  hmssh::ConnectParams p;
  p.host = GetStringProp(env, obj, "host");
  p.port = GetIntProp(env, obj, "port", 22);
  p.username = GetStringProp(env, obj, "username");
  p.password = GetStringProp(env, obj, "password");
  p.privateKey = GetStringProp(env, obj, "privateKey");
  p.knownHostsPath = GetStringProp(env, obj, "knownHostsPath");
  // also accept snake_case from some callers
  if (p.knownHostsPath.empty()) {
    p.knownHostsPath = GetStringProp(env, obj, "known_hosts_path");
  }
  p.useTls = GetBoolProp(env, obj, "useTls", false) || GetBoolProp(env, obj, "use_tls", false);
  return p;
}

// ---- SSH ----
napi_value SshLibAvailable(napi_env env, napi_callback_info info) {
  return MakeBool(env, hmssh::Libssh2Available());
}

napi_value SshConnect(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  auto params = ParseConnect(env, args[0]);
  auto client = std::make_unique<hmssh::SshClient>();
  std::string err = client->Connect(params);
  napi_value result;
  napi_create_object(env, &result);
  if (!err.empty()) {
    napi_set_named_property(env, result, "ok", MakeBool(env, false));
    napi_set_named_property(env, result, "error", MakeString(env, err));
    napi_set_named_property(env, result, "id", MakeInt(env, 0));
    napi_set_named_property(env, result, "hostKeyFingerprint", MakeString(env, client->LastHostKeyFingerprint()));
    return result;
  }
  std::string fp = client->LastHostKeyFingerprint();
  std::lock_guard<std::mutex> lock(gMu);
  int id = gNextId++;
  gSsh[id] = std::move(client);
  napi_set_named_property(env, result, "ok", MakeBool(env, true));
  napi_set_named_property(env, result, "error", MakeString(env, ""));
  napi_set_named_property(env, result, "id", MakeInt(env, id));
  napi_set_named_property(env, result, "hostKeyFingerprint", MakeString(env, fp));
  return result;
}

int ArgId(napi_env env, napi_callback_info info, napi_value* rest, size_t restN) {
  size_t argc = 1 + restN;
  std::vector<napi_value> args(argc);
  napi_get_cb_info(env, info, &argc, args.data(), nullptr, nullptr);
  int32_t id = 0;
  if (argc >= 1) napi_get_value_int32(env, args[0], &id);
  for (size_t i = 0; i < restN && (i + 1) < argc; ++i) rest[i] = args[i + 1];
  return id;
}

napi_value SshDisconnect(napi_env env, napi_callback_info info) {
  int id = ArgId(env, info, nullptr, 0);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gSsh.find(id);
  if (it != gSsh.end()) {
    it->second->Disconnect();
    gSsh.erase(it);
  }
  return MakeBool(env, true);
}

napi_value SshSend(napi_env env, napi_callback_info info) {
  napi_value rest[1]{};
  int id = ArgId(env, info, rest, 1);
  size_t len = 0;
  napi_get_value_string_utf8(env, rest[0], nullptr, 0, &len);
  std::string data(len, '\0');
  if (len) napi_get_value_string_utf8(env, rest[0], &data[0], len + 1, &len);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gSsh.find(id);
  if (it == gSsh.end()) return MakeString(env, "invalid session");
  return MakeString(env, it->second->Send(data));
}

napi_value SshRead(napi_env env, napi_callback_info info) {
  napi_value rest[1]{};
  int id = ArgId(env, info, rest, 1);
  int32_t maxBytes = 16384;
  if (rest[0]) napi_get_value_int32(env, rest[0], &maxBytes);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gSsh.find(id);
  if (it == gSsh.end()) return MakeString(env, "");
  return MakeString(env, it->second->Read(maxBytes));
}

napi_value SshResize(napi_env env, napi_callback_info info) {
  napi_value rest[2]{};
  int id = ArgId(env, info, rest, 2);
  int32_t cols = 80, rows = 24;
  if (rest[0]) napi_get_value_int32(env, rest[0], &cols);
  if (rest[1]) napi_get_value_int32(env, rest[1], &rows);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gSsh.find(id);
  if (it == gSsh.end()) return MakeString(env, "invalid session");
  return MakeString(env, it->second->Resize(cols, rows));
}

// ---- FTP ----
napi_value FtpConnect(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  auto params = ParseConnect(env, args[0]);
  auto client = std::make_unique<hmssh::FtpClient>();
  std::string err = client->Connect(params);
  napi_value result;
  napi_create_object(env, &result);
  if (!err.empty()) {
    napi_set_named_property(env, result, "ok", MakeBool(env, false));
    napi_set_named_property(env, result, "error", MakeString(env, err));
    napi_set_named_property(env, result, "id", MakeInt(env, 0));
    return result;
  }
  std::lock_guard<std::mutex> lock(gMu);
  int id = gNextId++;
  gFtp[id] = std::move(client);
  napi_set_named_property(env, result, "ok", MakeBool(env, true));
  napi_set_named_property(env, result, "error", MakeString(env, ""));
  napi_set_named_property(env, result, "id", MakeInt(env, id));
  return result;
}

napi_value FtpDisconnect(napi_env env, napi_callback_info info) {
  int id = ArgId(env, info, nullptr, 0);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gFtp.find(id);
  if (it != gFtp.end()) {
    it->second->Disconnect();
    gFtp.erase(it);
  }
  return MakeBool(env, true);
}

napi_value FtpCd(napi_env env, napi_callback_info info) {
  napi_value rest[1]{};
  int id = ArgId(env, info, rest, 1);
  size_t len = 0;
  napi_get_value_string_utf8(env, rest[0], nullptr, 0, &len);
  std::string path(len, '\0');
  if (len) napi_get_value_string_utf8(env, rest[0], &path[0], len + 1, &len);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gFtp.find(id);
  if (it == gFtp.end()) return MakeString(env, "invalid session");
  return MakeString(env, it->second->Cd(path));
}

napi_value FtpCwd(napi_env env, napi_callback_info info) {
  int id = ArgId(env, info, nullptr, 0);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gFtp.find(id);
  if (it == gFtp.end()) return MakeString(env, "/");
  return MakeString(env, it->second->GetCwd());
}

napi_value FtpList(napi_env env, napi_callback_info info) {
  int id = ArgId(env, info, nullptr, 0);
  std::vector<hmssh::FtpListEntry> entries;
  std::string err;
  {
    std::lock_guard<std::mutex> lock(gMu);
    auto it = gFtp.find(id);
    if (it == gFtp.end()) err = "invalid session";
    else err = it->second->List(entries);
  }
  napi_value result;
  napi_create_object(env, &result);
  napi_set_named_property(env, result, "error", MakeString(env, err));
  napi_value arr;
  napi_create_array_with_length(env, entries.size(), &arr);
  for (size_t i = 0; i < entries.size(); ++i) {
    napi_value item;
    napi_create_object(env, &item);
    napi_set_named_property(env, item, "name", MakeString(env, entries[i].name));
    napi_set_named_property(env, item, "path", MakeString(env, entries[i].path));
    napi_set_named_property(env, item, "isDirectory", MakeBool(env, entries[i].isDirectory));
    napi_value sizeV;
    napi_create_int64(env, entries[i].size, &sizeV);
    napi_set_named_property(env, item, "size", sizeV);
    napi_value modV;
    napi_create_int64(env, entries[i].modifiedAt, &modV);
    napi_set_named_property(env, item, "modifiedAt", modV);
    napi_set_element(env, arr, i, item);
  }
  napi_set_named_property(env, result, "entries", arr);
  return result;
}

napi_value FtpRetr(napi_env env, napi_callback_info info) {
  napi_value rest[2]{};
  int id = ArgId(env, info, rest, 2);
  auto getStr = [&](napi_value v) {
    size_t len = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &len);
    std::string s(len, '\0');
    if (len) napi_get_value_string_utf8(env, v, &s[0], len + 1, &len);
    return s;
  };
  std::string remote = getStr(rest[0]);
  std::string local = getStr(rest[1]);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gFtp.find(id);
  if (it == gFtp.end()) return MakeString(env, "invalid session");
  return MakeString(env, it->second->Retr(remote, local));
}

napi_value FtpStor(napi_env env, napi_callback_info info) {
  napi_value rest[2]{};
  int id = ArgId(env, info, rest, 2);
  auto getStr = [&](napi_value v) {
    size_t len = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &len);
    std::string s(len, '\0');
    if (len) napi_get_value_string_utf8(env, v, &s[0], len + 1, &len);
    return s;
  };
  std::string remote = getStr(rest[0]);
  std::string local = getStr(rest[1]);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gFtp.find(id);
  if (it == gFtp.end()) return MakeString(env, "invalid session");
  return MakeString(env, it->second->Stor(remote, local));
}

// ---- VNC ----
napi_value VncConnect(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  auto params = ParseConnect(env, args[0]);
  auto client = std::make_unique<hmssh::VncClient>();
  std::string err = client->Connect(params);
  napi_value result;
  napi_create_object(env, &result);
  if (!err.empty()) {
    napi_set_named_property(env, result, "ok", MakeBool(env, false));
    napi_set_named_property(env, result, "error", MakeString(env, err));
    napi_set_named_property(env, result, "id", MakeInt(env, 0));
    return result;
  }
  std::lock_guard<std::mutex> lock(gMu);
  int id = gNextId++;
  gVnc[id] = std::move(client);
  napi_set_named_property(env, result, "ok", MakeBool(env, true));
  napi_set_named_property(env, result, "error", MakeString(env, ""));
  napi_set_named_property(env, result, "id", MakeInt(env, id));
  return result;
}

napi_value VncDisconnect(napi_env env, napi_callback_info info) {
  int id = ArgId(env, info, nullptr, 0);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gVnc.find(id);
  if (it != gVnc.end()) {
    it->second->Disconnect();
    gVnc.erase(it);
  }
  return MakeBool(env, true);
}

napi_value VncFramebuffer(napi_env env, napi_callback_info info) {
  int id = ArgId(env, info, nullptr, 0);
  hmssh::VncFramebuffer fb;
  std::string err;
  {
    std::lock_guard<std::mutex> lock(gMu);
    auto it = gVnc.find(id);
    if (it == gVnc.end()) err = "invalid session";
    else {
      it->second->PollUpdate();
      err = it->second->GetFramebuffer(fb);
    }
  }
  napi_value result;
  napi_create_object(env, &result);
  napi_set_named_property(env, result, "error", MakeString(env, err));
  napi_set_named_property(env, result, "width", MakeInt(env, fb.width));
  napi_set_named_property(env, result, "height", MakeInt(env, fb.height));
  napi_value ab;
  void* data = nullptr;
  napi_create_arraybuffer(env, fb.rgba.size(), &data, &ab);
  if (data && !fb.rgba.empty()) {
    std::memcpy(data, fb.rgba.data(), fb.rgba.size());
  }
  napi_set_named_property(env, result, "rgba", ab);
  return result;
}

napi_value VncPointerEvent(napi_env env, napi_callback_info info) {
  napi_value rest[3]{};
  int id = ArgId(env, info, rest, 3);
  int32_t x = 0, y = 0, buttons = 0;
  if (rest[0]) napi_get_value_int32(env, rest[0], &x);
  if (rest[1]) napi_get_value_int32(env, rest[1], &y);
  if (rest[2]) napi_get_value_int32(env, rest[2], &buttons);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gVnc.find(id);
  if (it == gVnc.end()) return MakeString(env, "invalid session");
  return MakeString(env, it->second->PointerEvent(x, y, buttons));
}

napi_value VncKeyEvent(napi_env env, napi_callback_info info) {
  napi_value rest[2]{};
  int id = ArgId(env, info, rest, 2);
  int32_t keysym = 0;
  bool down = false;
  if (rest[0]) napi_get_value_int32(env, rest[0], &keysym);
  if (rest[1]) napi_get_value_bool(env, rest[1], &down);
  std::lock_guard<std::mutex> lock(gMu);
  auto it = gVnc.find(id);
  if (it == gVnc.end()) return MakeString(env, "invalid session");
  return MakeString(env, it->second->KeyEvent(static_cast<uint32_t>(keysym), down));
}

napi_value NativeAvailable(napi_env env, napi_callback_info info) {
  return MakeBool(env, true);
}

napi_value Init(napi_env env, napi_value exports) {
  struct Desc { const char* name; napi_callback cb; } defs[] = {
      {"nativeAvailable", NativeAvailable},
      {"sshLibAvailable", SshLibAvailable},
      {"sshConnect", SshConnect},
      {"sshDisconnect", SshDisconnect},
      {"sshSend", SshSend},
      {"sshRead", SshRead},
      {"sshResize", SshResize},
      {"ftpConnect", FtpConnect},
      {"ftpDisconnect", FtpDisconnect},
      {"ftpCd", FtpCd},
      {"ftpCwd", FtpCwd},
      {"ftpList", FtpList},
      {"ftpRetr", FtpRetr},
      {"ftpStor", FtpStor},
      {"vncConnect", VncConnect},
      {"vncDisconnect", VncDisconnect},
      {"vncFramebuffer", VncFramebuffer},
      {"vncPointerEvent", VncPointerEvent},
      {"vncKeyEvent", VncKeyEvent},
  };
  for (auto& d : defs) {
    napi_value fn;
    napi_create_function(env, d.name, NAPI_AUTO_LENGTH, d.cb, nullptr, &fn);
    napi_set_named_property(env, exports, d.name, fn);
  }
  return exports;
}

}  // namespace

static napi_module gModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "hmssh_native",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterHmsshNativeModule(void) {
  napi_module_register(&gModule);
}
