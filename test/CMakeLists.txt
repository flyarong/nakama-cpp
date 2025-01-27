#
# Copyright 2019 The Nakama Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

cmake_minimum_required(VERSION 3.18.1)

if(APPLE AND (NOT DEFINED ENV{NAKAMA_TEST_DEVELOPMENT_TEAM}))
    message(FATAL_ERROR "No test development team setup. Please have an entry for NAKAMA_TEST_DEVELOPMENT_TEAM in your environment variables. See README.md for more information.")
endif()

 ## force so that gradle doesn't stomp vcpkg toolchain with the android toolchain
set(CMAKE_TOOLCHAIN_FILE $ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake CACHE FILEPATH "Vcpkg toolchain file" FORCE)

if (DEFINED ANDROID_ABI AND NOT DEFINED VCPKG_CHAINLOAD_TOOLCHAIN_FILE)
    # CmakePresets.json doesn't allow us to use cmake vars in values, so set it here
    set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE $ENV{ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake)
endif()

project(nakama-test LANGUAGES C CXX)

option(LOGS_ENABLED "Enable log output" ON)
option(REMOTE_NAKAMA_SDK "Use a remote (vcpkg) installation of Nakama" OFF)

if(REMOTE_NAKAMA_SDK)
    list(APPEND VCPKG_MANIFEST_FEATURES "nakama-sdk")
else()
    execute_process(
        COMMAND ${CMAKE_COMMAND} -S .. --preset ${PRESET_NAME}
        RESULT_VARIABLE result
    )

    if (result)
        message(FATAL_ERROR "Configuration of nakama-cpp preset ${PRESET_NAME} failed.")
    endif()

    execute_process(
        COMMAND ${CMAKE_COMMAND} --build ../build/${PRESET_NAME} --config MinSizeRel --target install
        RESULT_VARIABLE result
    )

    if (result)
        message(FATAL_ERROR "Building and installing nakama-cpp with preset ${PRESET_NAME} failed.")
    endif()
endif()

include(FetchContent)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(THREADS_PREFER_PTHREAD_FLAG ON)
    find_package(Threads REQUIRED)
    set(PTHREADS_LIB Threads::Threads)
endif()

### This needs to be one of the first commands in order to prevent code signing issues.
if (${CMAKE_SYSTEM_NAME} STREQUAL "iOS" OR ${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
    # CMake needs to implement a cleaner way of doing this: https://gitlab.kitware.com/cmake/cmake/-/issues/22997 &&
    # https://gitlab.kitware.com/cmake/cmake/-/issues/22240
    set(CMAKE_BUILD_WITH_INSTALL_RPATH YES)
endif()

find_package(RapidJSON CONFIG REQUIRED)
find_package(optional-lite)

### CMakePresets.json doesn't seem to pass the ${installDir} to the CMake file, so we have to reconstitute it.
string(REPLACE ${CMAKE_SOURCE_DIR}/ "" CMAKE_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}")
get_filename_component(_NAKAMA_PROJECT "${CMAKE_SOURCE_DIR}" DIRECTORY)

if (NOT REMOTE_NAKAMA_SDK)
    set(nakama-sdk_DIR ${_NAKAMA_PROJECT}/${CMAKE_INSTALL_DIR}/share/nakama-sdk)
endif()

find_package(nakama-sdk CONFIG REQUIRED)

if (ADDRESS_SANITIZER)
    # In the top level CMakeLists we used `add_compile_options` to globally add
    # Asan instrumentation to everything we compile, but we dont' want it
    # to be in the test binary, to replicate exactly how asan-enabled dll/so shared
    # library behaves. So here we remove address sanitizer from test.
    get_directory_property(_compile_options COMPILE_OPTIONS)
    list(REMOVE_ITEM _compile_options -fsanitize=address)
    set_directory_properties(PROPERTIES COMPILE_OPTIONS "${_compiler_options}")
    unset(_compile_options)
endif()

file(
    GLOB SRCS
    LIST_DIRECTORIES false
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.c*"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h*"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/realtime/*.c*"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/realtime/*.h*"
)

# following this guide: https://medium.com/androiddevelopers/getting-started-with-c-and-android-native-activities-2213b402ffff
# alternatively we could do this in `Android.mk` but we already use CMake.
if (ANDROID)
    find_library(log-lib log)

    add_library(nakama-test ${SRCS})

    target_link_libraries(nakama-test
        PUBLIC
            ${log-lib}
            android
    )
else()
    add_executable(nakama-test MACOSX_BUNDLE ${SRCS})
endif()

if (LOGS_ENABLED)
    target_compile_definitions(nakama-test PRIVATE "NLOGS_ENABLED")
endif()

target_link_libraries(nakama-test
    INTERFACE rapidjson
    PRIVATE nakama-sdk
)

target_include_directories(nakama-test
    PRIVATE src
    ${rapidjson_SOURCE_DIR}/include ### rapidjson probably not setup correctly by its authors, because target_link_libraries should handle this
)

target_compile_features(nakama-test PRIVATE cxx_std_14)

get_target_property(NAKAMA_TGT_TYPE nakama-sdk TYPE)
if(${CMAKE_SYSTEM_NAME} STREQUAL "Windows" AND ${NAKAMA_TGT_TYPE} STREQUAL "SHARED_LIBRARY")
    # Copy DLL so that nakama-test.exe can find it
    add_custom_command(TARGET nakama-test POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_RUNTIME_DLLS:nakama-test> $<TARGET_FILE_DIR:nakama-test>
            COMMAND_EXPAND_LISTS
            )
endif()

# no ZERO_CHECK target for Xcode
set(CMAKE_SUPPRESS_REGENERATION true)

set(NAKAMA_SDK_FRAMEWORK_LOCATION "")

if (REMOTE_NAKAMA_SDK)
    set(NAKAMA_SDK_FRAMEWORK_LOCATION ${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib/nakama-sdk.framework)
else()
    set(NAKAMA_SDK_FRAMEWORK_LOCATION ${_NAKAMA_PROJECT}/${CMAKE_INSTALL_DIR}/lib/nakama-sdk.framework)
endif()

set_target_properties(nakama-test PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.test"
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/test.plist
    XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.heroiclabs.test"
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "YES"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "Apple Development"
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "$ENV{NAKAMA_TEST_DEVELOPMENT_TEAM}"
    XCODE_LINK_BUILD_PHASE_MODE KNOWN_LOCATION
    XCODE_EMBED_FRAMEWORKS ${NAKAMA_SDK_FRAMEWORK_LOCATION} ## todo figure out why passing target doesn't work
    XCODE_EMBED_FRAMEWORKS_CODE_SIGN_ON_COPY		"YES"		# frameworks must be signed by the same developer as the binary
	XCODE_EMBED_FRAMEWORKS_REMOVE_HEADERS_ON_COPY	"YES"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
)

if(${CMAKE_SYSTEM_NAME} STREQUAL "iOS")
    set_target_properties(nakama-test PROPERTIES
        INSTALL_RPATH @executable_path/Frameworks
    )
elseif(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
    set_target_properties(nakama-test PROPERTIES
        INSTALL_RPATH @executable_path/../Frameworks
    )
elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
    set_target_properties(nakama-test PROPERTIES
        INSTALL_RPATH $ORIGIN
    )
endif()

set(_TEST_OUT_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS nakama-test
    BUNDLE DESTINATION ${_TEST_OUT_DIR}
    RUNTIME DESTINATION ${_TEST_OUT_DIR}
)

install(IMPORTED_RUNTIME_ARTIFACTS nakama-sdk
    RUNTIME DESTINATION ${_TEST_OUT_DIR}
    LIBRARY DESTINATION ${_TEST_OUT_DIR}
    FRAMEWORK DESTINATION ${_TEST_OUT_DIR}
)


if (CMAKE_SYSTEM_NAME MATCHES "Windows" OR CMAKE_SYSTEM_NAME MATCHES "Linux")
    add_custom_target(run
        COMMAND ${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_BINDIR}/nakama-test
        USES_TERMINAL
    )
elseif (CMAKE_SYSTEM_NAME MATCHES "Darwin")
    add_custom_target(run
        COMMAND $<TARGET_BUNDLE_DIR:nakama-test>/Contents/MacOS/nakama-test
        USES_TERMINAL
    )
endif()