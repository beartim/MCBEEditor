cmake_minimum_required(VERSION 3.20)
project(MCBEEditorCLIApple LANGUAGES C CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
get_filename_component(MCBE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)

# Reuse the same pinned Mojang LevelDB sources and zlib build as Windows.
add_subdirectory("${MCBE_ROOT}/Windows/Native" "${CMAKE_BINARY_DIR}/leveldb-build" EXCLUDE_FROM_ALL)
target_compile_definitions(mcbe_leveldb_core PRIVATE OS_MACOSX=1)
set_target_properties(mcbe_leveldb_core zlibstatic PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/lib")

set_target_properties(zlibstatic PROPERTIES OUTPUT_NAME mcbe_cli_zlib)

add_library(mcbe_cli_apple_bridge STATIC
    "${MCBE_ROOT}/Sources/Bridge/BTLevelDBBridge.mm"
    "${MCBE_ROOT}/Sources/Bridge/BTCompressionBridge.mm")
target_compile_options(mcbe_cli_apple_bridge PRIVATE -fobjc-arc)
target_compile_definitions(mcbe_cli_apple_bridge PRIVATE
    OS_MACOSX=1 LEVELDB_PLATFORM_POSIX=1 HAVE_ZLIB=1 DLLX=)
target_include_directories(mcbe_cli_apple_bridge PRIVATE
    "${LEVELDB_MCPE_ROOT}" "${LEVELDB_MCPE_ROOT}/include" "${ZLIB_SOURCE_ROOT}" "${CMAKE_BINARY_DIR}/zlib")
target_link_libraries(mcbe_cli_apple_bridge PRIVATE mcbe_leveldb_core zlibstatic "-framework Foundation")
set_target_properties(mcbe_cli_apple_bridge PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/lib")

if(TARGET mcbe_cli_create_test_db)
    target_compile_definitions(mcbe_cli_create_test_db PRIVATE OS_MACOSX=1)
    set_target_properties(mcbe_cli_create_test_db PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tools"
        RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/tools")
endif()
