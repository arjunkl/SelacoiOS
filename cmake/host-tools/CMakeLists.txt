cmake_minimum_required(VERSION 3.16)
project(SelacoiOSHostTools LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(GZSELACO_SOURCE_DIR "" CACHE PATH "Path to the pinned GZSelaco source checkout")
if(NOT GZSELACO_SOURCE_DIR)
  message(FATAL_ERROR "GZSELACO_SOURCE_DIR is required")
endif()
get_filename_component(GZSELACO_SOURCE_DIR "${GZSELACO_SOURCE_DIR}" ABSOLUTE)

foreach(required_path
    CMakeLists.txt
    tools/re2c/CMakeLists.txt
    tools/lemon/CMakeLists.txt
    tools/zipdir/CMakeLists.txt
    libraries/bzip2/CMakeLists.txt
    libraries/lzma/CMakeLists.txt
    libraries/miniz/CMakeLists.txt)
  if(NOT EXISTS "${GZSELACO_SOURCE_DIR}/${required_path}")
    message(FATAL_ERROR "Pinned source is missing ${required_path}")
  endif()
endforeach()

# Bundled library projects expect this helper from the upstream root project.
# Host tools do not need special release-only flag rewriting, so the helper is
# intentionally a no-op in this isolated native build.
macro(make_release_only)
endmacro()

set(BZIP2_INCLUDE_DIR "${GZSELACO_SOURCE_DIR}/libraries/bzip2")
set(BZIP2_LIBRARIES bz2)
set(LZMA_INCLUDE_DIR "${GZSELACO_SOURCE_DIR}/libraries/lzma/C")

add_subdirectory(
  "${GZSELACO_SOURCE_DIR}/libraries/bzip2"
  "${CMAKE_BINARY_DIR}/upstream/bzip2")
add_subdirectory(
  "${GZSELACO_SOURCE_DIR}/libraries/lzma"
  "${CMAKE_BINARY_DIR}/upstream/lzma")
add_subdirectory(
  "${GZSELACO_SOURCE_DIR}/libraries/miniz"
  "${CMAKE_BINARY_DIR}/upstream/miniz")

add_subdirectory(
  "${GZSELACO_SOURCE_DIR}/tools/re2c"
  "${CMAKE_BINARY_DIR}/upstream/re2c")
add_subdirectory(
  "${GZSELACO_SOURCE_DIR}/tools/lemon"
  "${CMAKE_BINARY_DIR}/upstream/lemon")
add_subdirectory(
  "${GZSELACO_SOURCE_DIR}/tools/zipdir"
  "${CMAKE_BINARY_DIR}/upstream/zipdir")

add_custom_target(selaco-host-tools ALL DEPENDS re2c lemon zipdir)
