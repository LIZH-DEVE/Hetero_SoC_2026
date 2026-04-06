# Copyright (C) 2023 - 2024 Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.16)

include(${CMAKE_CURRENT_LIST_DIR}/../../gem0_probe_app/src/Empty_applicationExample.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/UserConfig.cmake)

set(APP_NAME ax7020_official_uart_smoke_app)
project(${APP_NAME})

find_package(common)
enable_language(C ASM CXX)
collect(PROJECT_LIB_DEPS xilstandalone;xiltimer)
collect(PROJECT_LIB_DEPS xil)
collect(PROJECT_LIB_DEPS gcc)
collect(PROJECT_LIB_DEPS c)

if(NOT DEFINED OFFICIAL_BSP_ROOT)
    message(FATAL_ERROR "OFFICIAL_BSP_ROOT must be provided by the build script.")
endif()

file(GLOB OFFICIAL_STANDALONE_SRC_DIRS "${OFFICIAL_BSP_ROOT}/libsrc/standalone_v*/src")
file(GLOB OFFICIAL_STANDALONE_COMMON_DIRS "${OFFICIAL_BSP_ROOT}/libsrc/standalone_v*/src/common")
file(GLOB OFFICIAL_UARTPS_DIRS "${OFFICIAL_BSP_ROOT}/libsrc/uartps_v*/src")

if(NOT OFFICIAL_STANDALONE_SRC_DIRS)
    message(FATAL_ERROR "Could not find official standalone headers under ${OFFICIAL_BSP_ROOT}/libsrc.")
endif()

if(NOT OFFICIAL_STANDALONE_COMMON_DIRS)
    message(FATAL_ERROR "Could not find official standalone common headers under ${OFFICIAL_BSP_ROOT}/libsrc.")
endif()

if(NOT OFFICIAL_UARTPS_DIRS)
    message(FATAL_ERROR "Could not find official uartps headers under ${OFFICIAL_BSP_ROOT}/libsrc.")
endif()

set(APP_SOURCES
    "${CMAKE_CURRENT_LIST_DIR}/main.c"
)

collector_list(_deps PROJECT_LIB_DEPS)
list(APPEND _deps ${USER_LINK_LIBRARIES})

if(CMAKE_EXPORT_COMPILE_COMMANDS)
    set(CMAKE_CXX_STANDARD_INCLUDE_DIRECTORIES ${CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES})
    set(CMAKE_C_STANDARD_INCLUDE_DIRECTORIES ${CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES})
endif()

if(DEFINED ENV{ESW_REPO})
    set(LINKER_TEMPLATE_DIR "$ENV{ESW_REPO}/scripts/linker_files")
else()
    set(LINKER_TEMPLATE_DIR "${CMAKE_SOURCE_DIR}/linker_files")
endif()
linker_gen("${LINKER_TEMPLATE_DIR}")

string(APPEND CMAKE_C_FLAGS ${USER_COMPILE_OPTIONS})
string(APPEND CMAKE_CXX_FLAGS ${USER_COMPILE_OPTIONS})
string(APPEND CMAKE_C_LINK_FLAGS ${USER_LINK_OPTIONS})
string(APPEND CMAKE_CXX_LINK_FLAGS ${USER_LINK_OPTIONS})

add_dependency_on_bsp(APP_SOURCES)
add_executable(${APP_NAME}.elf ${APP_SOURCES})
set_target_properties(${APP_NAME}.elf PROPERTIES LINK_DEPENDS ${USER_LINKER_SCRIPT})
target_link_libraries(${APP_NAME}.elf
    -Wl,-T
    -Wl,\"${USER_LINKER_SCRIPT}\"
    -L\"${CMAKE_SOURCE_DIR}/\"
    -L\"${CMAKE_LIBRARY_PATH}/\"
    -L\"${USER_LINK_DIRECTORIES}/\"
    -Wl,--start-group,-l${_deps}
    -Wl,--end-group
)
target_compile_definitions(${APP_NAME}.elf PUBLIC ${USER_COMPILE_DEFINITIONS})
target_include_directories(${APP_NAME}.elf PUBLIC
    ${USER_INCLUDE_DIRECTORIES}
    "${OFFICIAL_BSP_ROOT}/include"
    ${OFFICIAL_STANDALONE_SRC_DIRS}
    ${OFFICIAL_STANDALONE_COMMON_DIRS}
    ${OFFICIAL_UARTPS_DIRS}
)
print_elf_size(CMAKE_SIZE ${APP_NAME})
