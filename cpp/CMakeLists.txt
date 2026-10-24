cmake_minimum_required(VERSION 3.20)

project(reaper_airmann_faderport VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(FADERPORT_BUILD_TESTS "Build the unit tests" ON)

include(FetchContent)

# REAPER SDK (header only, no CMakeLists.txt)
FetchContent_Declare(reaper_sdk
  GIT_REPOSITORY https://github.com/justinfrankel/reaper-sdk.git
  GIT_TAG c0eafe87863b2bf69c5c822760f1b32a753b211b)
FetchContent_MakeAvailable(reaper_sdk)

# WDL/SWELL is required for macOS/Linux only. reaper_plugin.h includes
# "../WDL/swell/swell.h". The repository contains the sources in its WDL/ subfolder,
# so <wdl>/WDL is added as include directory: <wdl>/WDL/../WDL/swell/swell.h
if(NOT WIN32)
  FetchContent_Declare(wdl
    GIT_REPOSITORY https://github.com/justinfrankel/WDL.git
    GIT_TAG 61c5553aad0d257775a4dd7bf36b8be617ec8281)
  FetchContent_MakeAvailable(wdl)
endif()

set(FADERPORT_CORE_SOURCES
  src/bindings.cpp
  src/config.cpp
  src/driver.cpp
  src/midi_io.cpp
  src/params.cpp
  src/reaper_api.cpp)

function(faderport_setup target)
  target_include_directories(${target} PRIVATE src ${reaper_sdk_SOURCE_DIR}/sdk)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /utf-8)
    target_compile_definitions(${target} PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN _CRT_SECURE_NO_WARNINGS)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra)
    if(NOT WIN32)
      target_include_directories(${target} PRIVATE ${wdl_SOURCE_DIR}/WDL)
      target_compile_definitions(${target} PRIVATE SWELL_PROVIDED_BY_APP)
    endif()
  endif()
endfunction()

# REAPER extension: reaper_airmann_faderport.dll / .dylib / .so
add_library(reaper_airmann_faderport SHARED ${FADERPORT_CORE_SOURCES} src/plugin.cpp)
faderport_setup(reaper_airmann_faderport)
set_target_properties(reaper_airmann_faderport PROPERTIES
  PREFIX ""
  CXX_VISIBILITY_PRESET hidden)
if(APPLE)
  set_target_properties(reaper_airmann_faderport PROPERTIES SUFFIX ".dylib")
endif()
if(MSVC)
  # static runtime: no VC++ redistributable needed on the target machine
  set_property(TARGET reaper_airmann_faderport PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

if(FADERPORT_BUILD_TESTS)
  enable_testing()
  add_executable(faderport_tests ${FADERPORT_CORE_SOURCES} tests/mock_reaper.cpp tests/test_main.cpp)
  faderport_setup(faderport_tests)
  target_include_directories(faderport_tests PRIVATE tests)
  add_test(NAME faderport_tests COMMAND faderport_tests)
endif()
