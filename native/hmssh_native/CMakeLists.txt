# hmssh_native — HarmonyOS Node-API 协议后端（SSH / FTP / VNC）
# 在 DevEco 的 entry/src/main/cpp/CMakeLists.txt 中 add_subdirectory 本目录。
cmake_minimum_required(VERSION 3.16)
project(hmssh_native)

set(HMSSH_NATIVE_SOURCES
  src/napi_init.cpp
  src/ssh_client.cpp
  src/ftp_client.cpp
  src/vnc_client.cpp
)

add_library(hmssh_native SHARED ${HMSSH_NATIVE_SOURCES})

target_include_directories(hmssh_native PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# OpenHarmony / HarmonyOS NAPI
target_link_libraries(hmssh_native PUBLIC libace_napi.z.so)

# 可选：libssh2（+ OpenSSL / mbedTLS）。未找到时仍编译，运行时 sshConnect 返回明确错误。
option(HMSSH_ENABLE_LIBSSH2 "Link libssh2 for real SSH" ON)
set(HMSSH_LIBSSH2_ROOT "" CACHE PATH "Optional vendored libssh2 root (include/ + lib/)")

if(HMSSH_ENABLE_LIBSSH2)
  if(HMSSH_LIBSSH2_ROOT)
    set(LIBSSH2_INCLUDE_DIR "${HMSSH_LIBSSH2_ROOT}/include")
    set(LIBSSH2_LIBRARY "${HMSSH_LIBSSH2_ROOT}/lib/libssh2.a")
  endif()
  find_path(LIBSSH2_INCLUDE_DIR NAMES libssh2.h
    HINTS ${HMSSH_LIBSSH2_ROOT}/include ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libssh2/include)
  find_library(LIBSSH2_LIBRARY NAMES ssh2 libssh2
    HINTS ${HMSSH_LIBSSH2_ROOT}/lib ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libssh2/lib)
  if(LIBSSH2_INCLUDE_DIR AND LIBSSH2_LIBRARY)
    message(STATUS "hmssh_native: libssh2 found — enabling HMSSH_HAS_LIBSSH2")
    target_compile_definitions(hmssh_native PRIVATE HMSSH_HAS_LIBSSH2=1)
    target_include_directories(hmssh_native PRIVATE ${LIBSSH2_INCLUDE_DIR})
    target_link_libraries(hmssh_native PRIVATE ${LIBSSH2_LIBRARY})
    # OpenSSL if present (libssh2 often needs it)
    find_package(OpenSSL QUIET)
    if(OpenSSL_FOUND)
      target_link_libraries(hmssh_native PRIVATE OpenSSL::SSL OpenSSL::Crypto)
    endif()
  else()
    message(WARNING "hmssh_native: libssh2 NOT found — SSH NAPI builds but Connect returns link error. See native/README.md")
  endif()
endif()

# OHOS libc socket
if(DEFINED OHOS)
  target_link_libraries(hmssh_native PUBLIC libhilog_ndk.z.so)
endif()

set_target_properties(hmssh_native PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
)
