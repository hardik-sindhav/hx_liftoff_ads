cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "hx_liftoff_ads")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "hx_liftoff_ads_plugin")

# --- Liftoff Windows SDK (NuGet, Win32 x64) --------------------------------
# The SDK is under Liftoff's commercial license, so it is downloaded at build
# time instead of being redistributed with this package.
set(LIFTOFF_SDK_VERSION "7.1.1")
set(LIFTOFF_SDK_DIR "${CMAKE_BINARY_DIR}/liftoff_sdk_${LIFTOFF_SDK_VERSION}")
if(NOT EXISTS "${LIFTOFF_SDK_DIR}/build/native/include/LiftoffAds.h")
  set(LIFTOFF_NUPKG "${CMAKE_BINARY_DIR}/liftoff_sdk_${LIFTOFF_SDK_VERSION}.zip")
  message(STATUS "Downloading Liftoff Windows SDK ${LIFTOFF_SDK_VERSION}...")
  file(DOWNLOAD
    "https://api.nuget.org/v3-flatcontainer/vunglesdkforwindowsdesktopnative/${LIFTOFF_SDK_VERSION}/vunglesdkforwindowsdesktopnative.${LIFTOFF_SDK_VERSION}.nupkg"
    "${LIFTOFF_NUPKG}"
    STATUS LIFTOFF_DL_STATUS
    TLS_VERIFY ON)
  list(GET LIFTOFF_DL_STATUS 0 LIFTOFF_DL_CODE)
  if(NOT LIFTOFF_DL_CODE EQUAL 0)
    message(FATAL_ERROR "Could not download the Liftoff Windows SDK: ${LIFTOFF_DL_STATUS}")
  endif()
  file(ARCHIVE_EXTRACT INPUT "${LIFTOFF_NUPKG}" DESTINATION "${LIFTOFF_SDK_DIR}")
endif()

# The Release import library and DLL are used for every configuration so the
# bundled DLL always matches what we link against.
set(LIFTOFF_LIB_ROOT "${LIFTOFF_SDK_DIR}/build/native/lib/x64")

list(APPEND PLUGIN_SOURCES
  "hx_liftoff_ads_plugin.cpp"
  "hx_liftoff_ads_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/hx_liftoff_ads/hx_liftoff_ads_plugin_c_api.h"
  "hx_liftoff_ads_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${LIFTOFF_SDK_DIR}/build/native/include")
target_link_directories(${PLUGIN_NAME} PRIVATE
  "${LIFTOFF_LIB_ROOT}/Release")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin
  LiftoffSDK.Win32.lib)

# DLLs bundled next to the app executable (the SDK needs WebView2Loader.dll;
# the WebView2 Runtime itself must be installed on the user's machine).
set(hx_liftoff_ads_bundled_libraries
  "${LIFTOFF_LIB_ROOT}/Release/LiftoffSDK.Win32.dll"
  "${LIFTOFF_LIB_ROOT}/Release/WebView2Loader.dll"
  PARENT_SCOPE
)
