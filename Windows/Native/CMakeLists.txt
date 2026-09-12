cmake_minimum_required(VERSION 3.20)
project(MCBEEditorLevelDBNative LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS OFF)
if(MSVC)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

set(LEVELDB_MCPE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/leveldb-mcpe" CACHE PATH "Path to Amulet-Team/leveldb-mcpe")
set(ZLIB_SOURCE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/zlib" CACHE PATH "Path to zlib source")

if(NOT EXISTS "${LEVELDB_MCPE_ROOT}/include/leveldb/db.h")
    message(FATAL_ERROR "leveldb-mcpe source missing. Run bootstrap-native.ps1 first.")
endif()
if(NOT EXISTS "${ZLIB_SOURCE_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR "zlib source missing. Run bootstrap-native.ps1 first.")
endif()

set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SKIP_INSTALL_ALL ON CACHE BOOL "" FORCE)
add_subdirectory("${ZLIB_SOURCE_ROOT}" "${CMAKE_BINARY_DIR}/zlib" EXCLUDE_FROM_ALL)

set(LEVELDB_SOURCES
    "${LEVELDB_MCPE_ROOT}/db/builder.cc"
    "${LEVELDB_MCPE_ROOT}/db/db_impl.cc"
    "${LEVELDB_MCPE_ROOT}/db/db_iter.cc"
    "${LEVELDB_MCPE_ROOT}/db/dbformat.cc"
    "${LEVELDB_MCPE_ROOT}/db/filename.cc"
    "${LEVELDB_MCPE_ROOT}/db/log_reader.cc"
    "${LEVELDB_MCPE_ROOT}/db/log_writer.cc"
    "${LEVELDB_MCPE_ROOT}/db/memtable.cc"
    "${LEVELDB_MCPE_ROOT}/db/repair.cc"
    "${LEVELDB_MCPE_ROOT}/db/table_cache.cc"
    "${LEVELDB_MCPE_ROOT}/db/version_edit.cc"
    "${LEVELDB_MCPE_ROOT}/db/version_set.cc"
    "${LEVELDB_MCPE_ROOT}/db/write_batch.cc"
    "${LEVELDB_MCPE_ROOT}/db/zlib_compressor.cc"
    "${LEVELDB_MCPE_ROOT}/table/block.cc"
    "${LEVELDB_MCPE_ROOT}/table/block_builder.cc"
    "${LEVELDB_MCPE_ROOT}/table/filter_block.cc"
    "${LEVELDB_MCPE_ROOT}/table/format.cc"
    "${LEVELDB_MCPE_ROOT}/table/iterator.cc"
    "${LEVELDB_MCPE_ROOT}/table/merger.cc"
    "${LEVELDB_MCPE_ROOT}/table/table.cc"
    "${LEVELDB_MCPE_ROOT}/table/table_builder.cc"
    "${LEVELDB_MCPE_ROOT}/table/two_level_iterator.cc"
    "${LEVELDB_MCPE_ROOT}/util/arena.cc"
    "${LEVELDB_MCPE_ROOT}/util/bloom.cc"
    "${LEVELDB_MCPE_ROOT}/util/cache.cc"
    "${LEVELDB_MCPE_ROOT}/util/coding.cc"
    "${LEVELDB_MCPE_ROOT}/util/comparator.cc"
    "${LEVELDB_MCPE_ROOT}/util/crc32c.cc"
    "${LEVELDB_MCPE_ROOT}/util/env.cc"
    "${LEVELDB_MCPE_ROOT}/util/filter_policy.cc"
    "${LEVELDB_MCPE_ROOT}/util/hash.cc"
    "${LEVELDB_MCPE_ROOT}/util/histogram.cc"
    "${LEVELDB_MCPE_ROOT}/util/logging.cc"
    "${LEVELDB_MCPE_ROOT}/util/options.cc"
    "${LEVELDB_MCPE_ROOT}/util/status.cc"
    "${LEVELDB_MCPE_ROOT}/port/port_posix_sse.cc"
)

if(WIN32)
    list(APPEND LEVELDB_SOURCES
        "${LEVELDB_MCPE_ROOT}/port/port_win.cc"
        "${LEVELDB_MCPE_ROOT}/util/env_win.cc"
        "${LEVELDB_MCPE_ROOT}/util/win_logger.cc"
    )
else()
    list(APPEND LEVELDB_SOURCES
        "${LEVELDB_MCPE_ROOT}/port/port_posix.cc"
        "${LEVELDB_MCPE_ROOT}/util/env_posix.cc"
    )
endif()

add_library(mcbe_leveldb_core STATIC ${LEVELDB_SOURCES})
target_include_directories(mcbe_leveldb_core
    PUBLIC "${LEVELDB_MCPE_ROOT}" "${LEVELDB_MCPE_ROOT}/include"
    PRIVATE "${ZLIB_SOURCE_ROOT}" "${CMAKE_BINARY_DIR}/zlib"
)
target_link_libraries(mcbe_leveldb_core PRIVATE zlibstatic)
target_compile_definitions(mcbe_leveldb_core PRIVATE HAVE_ZLIB=1 DLLX=)

if(WIN32)
    target_compile_definitions(mcbe_leveldb_core PRIVATE
        WIN32=1 LEVELDB_PLATFORM_WINDOWS=1 _WIN32_WINNT=0x0601 NOMINMAX WIN32_LEAN_AND_MEAN)
else()
    target_compile_definitions(mcbe_leveldb_core PRIVATE LEVELDB_PLATFORM_POSIX=1)
    set_target_properties(mcbe_leveldb_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
endif()

add_library(MCBEEditor.LevelDB.Native SHARED src/mcbe_leveldb.cpp)
target_include_directories(MCBEEditor.LevelDB.Native PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
    "${LEVELDB_MCPE_ROOT}" "${LEVELDB_MCPE_ROOT}/include")
target_link_libraries(MCBEEditor.LevelDB.Native PRIVATE mcbe_leveldb_core zlibstatic)
target_compile_definitions(MCBEEditor.LevelDB.Native PRIVATE MCBE_LEVELDB_NATIVE_EXPORTS=1 DLLX=)
if(WIN32)
    target_compile_definitions(MCBEEditor.LevelDB.Native PRIVATE
        WIN32=1 LEVELDB_PLATFORM_WINDOWS=1 _WIN32_WINNT=0x0601 NOMINMAX WIN32_LEAN_AND_MEAN)
endif()

set(NATIVE_OUTPUT "${CMAKE_CURRENT_SOURCE_DIR}/bin/x64")
set_target_properties(MCBEEditor.LevelDB.Native PROPERTIES
    OUTPUT_NAME "MCBEEditor.LevelDB.Native"
    RUNTIME_OUTPUT_DIRECTORY "${NATIVE_OUTPUT}"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${NATIVE_OUTPUT}"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${NATIVE_OUTPUT}"
    LIBRARY_OUTPUT_DIRECTORY "${NATIVE_OUTPUT}"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

if(MSVC)
    target_compile_options(mcbe_leveldb_core PRIVATE /W3 /wd4244 /wd4267 /wd4996)
    target_compile_options(MCBEEditor.LevelDB.Native PRIVATE /W4 /EHsc)
endif()
