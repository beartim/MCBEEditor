cmake_minimum_required(VERSION 3.20)
project(MCBEEditorPortableLauncher LANGUAGES CXX RC)

if(NOT WIN32)
    message(FATAL_ERROR "The portable launcher is Windows-only.")
endif()
if(NOT DEFINED MCBE_PAYLOAD_PATH OR NOT EXISTS "${MCBE_PAYLOAD_PATH}")
    message(FATAL_ERROR "MCBE_PAYLOAD_PATH must point to the published MCBEEditor payload executable.")
endif()
if(NOT DEFINED MCBE_OUTPUT_DIR)
    set(MCBE_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/dist")
endif()

string(REPLACE "\\" "\\\\" MCBE_PAYLOAD_PATH_RC "${MCBE_PAYLOAD_PATH}")
set(MCBE_ICON_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../Resources/MCBEEditor.ico")
if(NOT EXISTS "${MCBE_ICON_PATH}")
    message(FATAL_ERROR "MCBEEditor icon was not found: ${MCBE_ICON_PATH}")
endif()
string(REPLACE "\\" "\\\\" MCBE_ICON_PATH_RC "${MCBE_ICON_PATH}")
configure_file(payload.rc.in "${CMAKE_CURRENT_BINARY_DIR}/payload.rc" @ONLY)

add_executable(MCBEEditor WIN32 launcher.cpp "${CMAKE_CURRENT_BINARY_DIR}/payload.rc")
target_compile_features(MCBEEditor PRIVATE cxx_std_17)
if(MSVC)
    target_compile_options(MCBEEditor PRIVATE /utf-8)
endif()
target_compile_definitions(MCBEEditor PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(MCBEEditor PRIVATE shell32)
set_property(TARGET MCBEEditor PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set_source_files_properties("${CMAKE_CURRENT_BINARY_DIR}/payload.rc" PROPERTIES OBJECT_DEPENDS "${MCBE_PAYLOAD_PATH}")
set_target_properties(MCBEEditor PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${MCBE_OUTPUT_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${MCBE_OUTPUT_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${MCBE_OUTPUT_DIR}"
    OUTPUT_NAME "MCBEEditor")
