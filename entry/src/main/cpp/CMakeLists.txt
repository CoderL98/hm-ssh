# DevEco 入口：编译 native/hmssh_native
cmake_minimum_required(VERSION 3.16)
project(entry_native)

set(HMSSH_NATIVE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../native/hmssh_native")
if(NOT EXISTS "${HMSSH_NATIVE_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "hmssh_native not found at ${HMSSH_NATIVE_DIR}")
endif()

add_subdirectory("${HMSSH_NATIVE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/hmssh_native")
