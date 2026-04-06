# Copyright (C) 2023 - 2024 Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.16)

include(${CMAKE_CURRENT_LIST_DIR}/../../gem0_probe_app/src/Empty_applicationExample.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/UserConfig.cmake)

set(APP_NAME ax7020_official_net_test_app)
project(${APP_NAME})

set(CMAKE_NINJA_FORCE_RESPONSE_FILE ON)
set(CMAKE_C_USE_RESPONSE_FILE_FOR_INCLUDES ON)
set(CMAKE_C_USE_RESPONSE_FILE_FOR_OBJECTS ON)
set(CMAKE_C_USE_RESPONSE_FILE_FOR_LIBRARIES ON)

find_package(common)
enable_language(C ASM CXX)
collect(PROJECT_LIB_DEPS lwip220;xilstandalone;xiltimer)
collect(PROJECT_LIB_DEPS xil)
collect(PROJECT_LIB_DEPS gcc)
collect(PROJECT_LIB_DEPS c)

set(OFFICIAL_BSP_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../ax7020_official_net_test/design_1_wrapper/ps7_cortexa9_0/standalone_domain/bsp/ps7_cortexa9_0")
set(OFFICIAL_EXPORT_INCLUDE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../ax7020_official_net_test/design_1_wrapper/export/design_1_wrapper/sw/design_1_wrapper/standalone_domain/bspinclude/include")
set(STANDALONE_SRC_DIR "${OFFICIAL_BSP_ROOT}/libsrc/standalone_v9_1/src")
set(STANDALONE_ARM_DIR "${STANDALONE_SRC_DIR}/arm/cortexa9")
set(SCUGIC_SRC_DIR "${OFFICIAL_BSP_ROOT}/libsrc/scugic_v5_3/src")
set(SCUTIMER_SRC_DIR "${OFFICIAL_BSP_ROOT}/libsrc/scutimer_v2_6/src")
set(EMACPS_SRC_DIR "${OFFICIAL_BSP_ROOT}/libsrc/emacps_v3_20/src")
set(LWIP_SRC_DIR "${OFFICIAL_BSP_ROOT}/libsrc/lwip220_v1_0/src")
set(LWIP_CORE_INCLUDE_DIR "${LWIP_SRC_DIR}/lwip-2.2.0/src/include")
set(LWIP_CORE_FLAT_INCLUDE_DIR "${LWIP_CORE_INCLUDE_DIR}/lwip")
set(LWIP_PORT_INCLUDE_DIR "${LWIP_SRC_DIR}/lwip-2.2.0/contrib/ports/xilinx/include")
set(APP_SOURCES
    "${CMAKE_CURRENT_LIST_DIR}/main.c"
    "${CMAKE_CURRENT_LIST_DIR}/udp_crypto_gateway.c"
    "${CMAKE_CURRENT_LIST_DIR}/platform_zynq.c"
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
    "${OFFICIAL_EXPORT_INCLUDE_DIR}"
    "${OFFICIAL_BSP_ROOT}/include"
    "${STANDALONE_SRC_DIR}"
    "${STANDALONE_ARM_DIR}"
    "${SCUGIC_SRC_DIR}"
    "${SCUTIMER_SRC_DIR}"
    "${EMACPS_SRC_DIR}"
    "${LWIP_CORE_INCLUDE_DIR}"
    "${LWIP_CORE_FLAT_INCLUDE_DIR}"
    "${LWIP_PORT_INCLUDE_DIR}"
)
print_elf_size(CMAKE_SIZE ${APP_NAME})
