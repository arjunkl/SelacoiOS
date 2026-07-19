cmake_minimum_required(VERSION 3.25)
project(SelacoiOSShellProbe LANGUAGES C CXX OBJCXX)

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
  message(FATAL_ERROR "This shell targets physical-device iPhoneOS, not the simulator")
endif()

if(NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
  message(FATAL_ERROR "This shell requires CMAKE_OSX_ARCHITECTURES=arm64")
endif()

set(GZSELACO_SOURCE_DIR "" CACHE PATH "Path to the pinned GZSelaco source checkout")
if(NOT GZSELACO_SOURCE_DIR)
  message(FATAL_ERROR "GZSELACO_SOURCE_DIR is required")
endif()
get_filename_component(GZSELACO_SOURCE_DIR "${GZSELACO_SOURCE_DIR}" ABSOLUTE)

foreach(required_path
    src/version.h
    src/common/thirdparty/superfasthash.h
    src/common/thirdparty/superfasthash.cpp)
  if(NOT EXISTS "${GZSELACO_SOURCE_DIR}/${required_path}")
    message(FATAL_ERROR "Pinned source is missing ${required_path}")
  endif()
endforeach()

find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(COREGRAPHICS_FRAMEWORK CoreGraphics REQUIRED)
find_library(UIKIT_FRAMEWORK UIKit REQUIRED)
find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
find_library(METAL_FRAMEWORK Metal REQUIRED)
find_library(METALKIT_FRAMEWORK MetalKit REQUIRED)

add_library(selaco-engine-boundary STATIC
  "${CMAKE_CURRENT_SOURCE_DIR}/SelacoEngineBoundary.cpp"
  "${GZSELACO_SOURCE_DIR}/src/common/thirdparty/superfasthash.cpp")

target_include_directories(selaco-engine-boundary PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${GZSELACO_SOURCE_DIR}/src"
  "${GZSELACO_SOURCE_DIR}/src/common/thirdparty")

target_compile_options(selaco-engine-boundary PRIVATE
  -Wall
  -Wextra
  -Wno-unused-parameter)

add_executable(SelacoiOSShell MACOSX_BUNDLE
  "${CMAKE_CURRENT_SOURCE_DIR}/AppMain.mm")

target_include_directories(SelacoiOSShell PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}")

target_compile_options(SelacoiOSShell PRIVATE
  -Wall
  -Wextra
  -Wno-unused-parameter
  -fobjc-arc)

target_link_libraries(SelacoiOSShell PRIVATE
  selaco-engine-boundary
  "${FOUNDATION_FRAMEWORK}"
  "${COREGRAPHICS_FRAMEWORK}"
  "${UIKIT_FRAMEWORK}"
  "${QUARTZCORE_FRAMEWORK}"
  "${METAL_FRAMEWORK}"
  "${METALKIT_FRAMEWORK}")

set_target_properties(SelacoiOSShell PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.m0shell"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
  XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
  XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
  XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ""
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1"
  XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos"
  XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
  XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH "YES"
  XCODE_ATTRIBUTE_STRIP_INSTALLED_PRODUCT "NO"
  XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING "NO")

add_custom_target(selaco-ios-shell-boundary ALL
  DEPENDS SelacoiOSShell)
