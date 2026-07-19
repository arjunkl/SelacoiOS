cmake_minimum_required(VERSION 3.25)
project(SelacoiOSCoreProbe LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR "This project must be configured with CMAKE_SYSTEM_NAME=iOS")
endif()
string(TOLOWER "${CMAKE_OSX_SYSROOT}" SELACOIOS_SYSROOT_LOWER)
if(NOT SELACOIOS_SYSROOT_LOWER MATCHES "iphoneos")
  message(FATAL_ERROR "This probe targets physical-device iPhoneOS, not the simulator")
endif()
if(NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
  message(FATAL_ERROR "This probe requires CMAKE_OSX_ARCHITECTURES=arm64")
endif()

set(GZSELACO_SOURCE_DIR "" CACHE PATH "Path to the pinned GZSelaco source checkout")
if(NOT GZSELACO_SOURCE_DIR)
  message(FATAL_ERROR "GZSELACO_SOURCE_DIR is required")
endif()
get_filename_component(GZSELACO_SOURCE_DIR "${GZSELACO_SOURCE_DIR}" ABSOLUTE)

foreach(required_path
    src/common/utility/engineerrors.cpp
    src/common/utility/engineerrors.h
    src/common/utility/TSQueue.cpp
    src/common/utility/TSQueue.h
    src/common/engine/stats.h
    libraries/bzip2/CMakeLists.txt
    libraries/lzma/CMakeLists.txt
    libraries/miniz/CMakeLists.txt)
  if(NOT EXISTS "${GZSELACO_SOURCE_DIR}/${required_path}")
    message(FATAL_ERROR "Pinned source is missing ${required_path}")
  endif()
endforeach()

# Bundled libraries expect this helper from the upstream root project. No flag
# rewriting is needed for the isolated static-library compile boundary.
macro(make_release_only)
endmacro()

add_subdirectory(
  "${GZSELACO_SOURCE_DIR}/libraries/bzip2"
  "${CMAKE_BINARY_DIR}/upstream/bzip2")
add_subdirectory(
  "${GZSELACO_SOURCE_DIR}/libraries/lzma"
  "${CMAKE_BINARY_DIR}/upstream/lzma")
add_subdirectory(
  "${GZSELACO_SOURCE_DIR}/libraries/miniz"
  "${CMAKE_BINARY_DIR}/upstream/miniz")

add_library(gzselaco-ios-core-probe STATIC
  "${GZSELACO_SOURCE_DIR}/src/common/utility/engineerrors.cpp"
  "${GZSELACO_SOURCE_DIR}/src/common/utility/TSQueue.cpp")

target_include_directories(gzselaco-ios-core-probe PRIVATE
  "${GZSELACO_SOURCE_DIR}/src/common/utility"
  "${GZSELACO_SOURCE_DIR}/src/common/engine")

target_compile_definitions(gzselaco-ios-core-probe PRIVATE
  HAVE_VM_JIT=0
  NO_SEND_STATS=1)

target_compile_options(gzselaco-ios-core-probe PRIVATE
  -Wall
  -Wextra
  -Wno-unused-parameter)

target_link_libraries(gzselaco-ios-core-probe PRIVATE bz2 lzma miniz)

add_custom_target(selaco-ios-core-boundary ALL
  DEPENDS gzselaco-ios-core-probe bz2 lzma miniz)
