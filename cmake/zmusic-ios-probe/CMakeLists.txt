cmake_minimum_required(VERSION 3.25)
project(SelacoiOSZMusicProbe LANGUAGES C CXX OBJCXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR "This probe must be configured for iOS")
endif()

string(TOLOWER "${CMAKE_OSX_SYSROOT}" SELACOIOS_SYSROOT_LOWER)
if(NOT SELACOIOS_SYSROOT_LOWER MATCHES "iphoneos")
  message(FATAL_ERROR "This probe targets physical-device iPhoneOS")
endif()

if(NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
  message(FATAL_ERROR "This probe requires arm64")
endif()

set(ZMUSIC_SOURCE_DIR "" CACHE PATH "Path to the pinned ZMusic checkout")
set(SELACOIOS_REPOSITORY_ROOT "" CACHE PATH "Path to the SelacoiOS checkout")
foreach(required_var ZMUSIC_SOURCE_DIR SELACOIOS_REPOSITORY_ROOT)
  if(NOT ${required_var})
    message(FATAL_ERROR "${required_var} is required")
  endif()
endforeach()

get_filename_component(ZMUSIC_SOURCE_DIR "${ZMUSIC_SOURCE_DIR}" ABSOLUTE)
get_filename_component(SELACOIOS_REPOSITORY_ROOT "${SELACOIOS_REPOSITORY_ROOT}" ABSOLUTE)

if(NOT EXISTS "${ZMUSIC_SOURCE_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "Pinned ZMusic source is missing CMakeLists.txt")
endif()
if(NOT EXISTS "${SELACOIOS_REPOSITORY_ROOT}/probes/zmusic-api-contract.cpp")
  message(FATAL_ERROR "SelacoiOS ZMusic API contract source is missing")
endif()

# The first iOS dependency gate deliberately avoids desktop-style runtime
# loading of optional decoder libraries. Vendored synth and tracker backends
# remain enabled so this is a meaningful full ZMusic static-library compile.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(ZMUSIC_INSTALL OFF CACHE BOOL "" FORCE)
set(DYN_SNDFILE OFF CACHE BOOL "" FORCE)
set(DYN_MPG123 OFF CACHE BOOL "" FORCE)

add_subdirectory(
  "${ZMUSIC_SOURCE_DIR}"
  "${CMAKE_BINARY_DIR}/upstream/zmusic")

add_library(selaco-zmusic-api-contract STATIC
  "${SELACOIOS_REPOSITORY_ROOT}/probes/zmusic-api-contract.cpp")
target_compile_definitions(selaco-zmusic-api-contract PRIVATE ZMUSIC_STATIC)
target_link_libraries(selaco-zmusic-api-contract PRIVATE ZMusic::zmusic)

target_compile_options(selaco-zmusic-api-contract PRIVATE
  -Wall
  -Wextra
  -Werror=return-type)

add_custom_target(selaco-zmusic-ios-boundary ALL
  DEPENDS zmusic selaco-zmusic-api-contract)
