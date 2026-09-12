#include "mcbe_leveldb.h"

#include <cstdarg>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <memory>
#include <new>
#include <string>

#ifndef DLLX
#define DLLX
#endif

#include "leveldb/cache.h"
#include "leveldb/db.h"
#include "leveldb/decompress_allocator.h"
#include "leveldb/env.h"
#include "leveldb/filter_policy.h"
#include "leveldb/iterator.h"
#include "leveldb/options.h"
#include "leveldb/write_batch.h"
#include "leveldb/zlib_compressor.h"

namespace {

char* duplicate_error(const std::string& value) {
    const size_t size = value.size() + 1;
    auto* output = static_cast<char*>(std::malloc(size));
    if (!output) return nullptr;
    std::memcpy(output, value.c_str(), size);
    return output;
}

void set_error(char** output, const std::string& value) {
    if (!output) return;
    *output = duplicate_error(value);
}

void clear_error(char** output) {
    if (output) *output = nullptr;
}

class NullLogger final : public leveldb::Logger {
public:
    void Logv(const char*, va_list) override {}
};

struct DatabaseState final {
    std::unique_ptr<const leveldb::FilterPolicy> filter_policy;
    std::unique_ptr<leveldb::Cache> block_cache;
    NullLogger logger;
    leveldb::ZlibCompressorRaw zlib_raw;
    leveldb::ZlibCompressor zlib;
    leveldb::DecompressAllocator decompress_allocator;
    leveldb::Options options;
    leveldb::ReadOptions read_options;
    std::unique_ptr<leveldb::DB> db;
    bool read_only;

    explicit DatabaseState(bool readOnly) : zlib_raw(-1), read_only(readOnly) {
        filter_policy.reset(leveldb::NewBloomFilterPolicy(10));
        block_cache.reset(leveldb::NewLRUCache(16 * 1024 * 1024));

        options.create_if_missing = false;
        options.error_if_exists = false;
        options.paranoid_checks = false;
        options.filter_policy = filter_policy.get();
        options.block_cache = block_cache.get();
        options.write_buffer_size = 4 * 1024 * 1024;
        options.block_size = 163840;
        options.max_open_files = 128;
        options.info_log = &logger;

        // Match the iOS bridge exactly: write legacy-compatible zlib ID 2,
        // while keeping raw-deflate ID 4 registered for modern Bedrock reads.
        options.compressors[0] = &zlib;
        options.compressors[1] = &zlib_raw;

        read_options.verify_checksums = true;
        read_options.fill_cache = true;
        read_options.decompress_allocator = &decompress_allocator;
    }
};

struct IteratorState final {
    DatabaseState* owner = nullptr;
    std::unique_ptr<leveldb::Iterator> iterator;
    std::string prefix;
    bool use_prefix = false;
    bool include_values = false;

    bool key_matches_prefix() const {
        if (!iterator || !iterator->Valid()) return false;
        if (!use_prefix) return true;
        const auto key = iterator->key();
        return key.size() >= prefix.size() &&
               std::memcmp(key.data(), prefix.data(), prefix.size()) == 0;
    }
};

struct BatchState final {
    leveldb::WriteBatch batch;
};

DatabaseState* database(mcbe_db_t handle) {
    return reinterpret_cast<DatabaseState*>(handle);
}
IteratorState* iterator(mcbe_iter_t handle) {
    return reinterpret_cast<IteratorState*>(handle);
}
BatchState* batch(mcbe_batch_t handle) {
    return reinterpret_cast<BatchState*>(handle);
}

bool valid_bytes(const uint8_t* data, size_t length) {
    return length == 0 || data != nullptr;
}

int require_database(mcbe_db_t handle, DatabaseState** output, char** error) {
    clear_error(error);
    auto* state = database(handle);
    if (!state || !state->db) {
        set_error(error, "database is closed");
        return -1;
    }
    *output = state;
    return 0;
}

int require_writable(mcbe_db_t handle, DatabaseState** output, char** error) {
    if (require_database(handle, output, error) != 0) return -1;
    if ((*output)->read_only) {
        set_error(error, "database was opened read-only");
        return -1;
    }
    return 0;
}

leveldb::Slice slice(const uint8_t* data, size_t length) {
    static const char empty = 0;
    return leveldb::Slice(length == 0 ? &empty : reinterpret_cast<const char*>(data), length);
}

} // namespace

extern "C" {

int mcbe_db_open(const char* path_utf8, int read_only, mcbe_db_t* out_db, char** out_error) {
    clear_error(out_error);
    if (out_db) *out_db = nullptr;
    if (!path_utf8 || !out_db) {
        set_error(out_error, "invalid path or output handle");
        return -1;
    }

    try {
        std::unique_ptr<DatabaseState> state(new DatabaseState(read_only != 0));
        leveldb::DB* raw = nullptr;
        const auto status = leveldb::DB::Open(state->options, path_utf8, &raw);
        if (!status.ok()) {
            set_error(out_error, status.ToString());
            return -1;
        }
        state->db.reset(raw);
        *out_db = state.release();
        return 0;
    } catch (const std::exception& error) {
        set_error(out_error, error.what());
        return -1;
    } catch (...) {
        set_error(out_error, "unknown native exception while opening database");
        return -1;
    }
}

void mcbe_db_close(mcbe_db_t db) {
    delete database(db);
}

int mcbe_db_get(mcbe_db_t db, const uint8_t* key, size_t key_len,
                uint8_t** out_value, size_t* out_value_len, char** out_error) {
    if (out_value) *out_value = nullptr;
    if (out_value_len) *out_value_len = 0;
    DatabaseState* state = nullptr;
    if (require_database(db, &state, out_error) != 0) return -1;
    if (!out_value || !out_value_len || !valid_bytes(key, key_len)) {
        set_error(out_error, "invalid get arguments");
        return -1;
    }

    std::string value;
    const auto status = state->db->Get(state->read_options, slice(key, key_len), &value);
    if (status.IsNotFound()) return 0;
    if (!status.ok()) {
        set_error(out_error, status.ToString());
        return -1;
    }

    if (!value.empty()) {
        auto* buffer = static_cast<uint8_t*>(std::malloc(value.size()));
        if (!buffer) {
            set_error(out_error, "out of memory while copying LevelDB value");
            return -1;
        }
        std::memcpy(buffer, value.data(), value.size());
        *out_value = buffer;
    }
    *out_value_len = value.size();
    return 1;
}

int mcbe_db_put(mcbe_db_t db, const uint8_t* key, size_t key_len,
                const uint8_t* value, size_t value_len, int sync, char** out_error) {
    DatabaseState* state = nullptr;
    if (require_writable(db, &state, out_error) != 0) return -1;
    if (!valid_bytes(key, key_len) || !valid_bytes(value, value_len)) {
        set_error(out_error, "invalid put arguments");
        return -1;
    }
    leveldb::WriteOptions options;
    options.sync = sync != 0;
    const auto status = state->db->Put(options, slice(key, key_len), slice(value, value_len));
    if (!status.ok()) {
        set_error(out_error, status.ToString());
        return -1;
    }
    return 0;
}

int mcbe_db_delete(mcbe_db_t db, const uint8_t* key, size_t key_len,
                   int sync, char** out_error) {
    DatabaseState* state = nullptr;
    if (require_writable(db, &state, out_error) != 0) return -1;
    if (!valid_bytes(key, key_len)) {
        set_error(out_error, "invalid delete arguments");
        return -1;
    }
    leveldb::WriteOptions options;
    options.sync = sync != 0;
    const auto status = state->db->Delete(options, slice(key, key_len));
    if (!status.ok()) {
        set_error(out_error, status.ToString());
        return -1;
    }
    return 0;
}

mcbe_batch_t mcbe_batch_create(void) {
    try { return new BatchState(); }
    catch (...) { return nullptr; }
}

void mcbe_batch_destroy(mcbe_batch_t handle) {
    delete batch(handle);
}

int mcbe_batch_put(mcbe_batch_t handle, const uint8_t* key, size_t key_len,
                   const uint8_t* value, size_t value_len, char** out_error) {
    clear_error(out_error);
    auto* state = batch(handle);
    if (!state || !valid_bytes(key, key_len) || !valid_bytes(value, value_len)) {
        set_error(out_error, "invalid batch put arguments");
        return -1;
    }
    state->batch.Put(slice(key, key_len), slice(value, value_len));
    return 0;
}

int mcbe_batch_delete(mcbe_batch_t handle, const uint8_t* key, size_t key_len, char** out_error) {
    clear_error(out_error);
    auto* state = batch(handle);
    if (!state || !valid_bytes(key, key_len)) {
        set_error(out_error, "invalid batch delete arguments");
        return -1;
    }
    state->batch.Delete(slice(key, key_len));
    return 0;
}

int mcbe_db_write_batch(mcbe_db_t db, mcbe_batch_t handle, int sync, char** out_error) {
    DatabaseState* state = nullptr;
    if (require_writable(db, &state, out_error) != 0) return -1;
    auto* write_batch = batch(handle);
    if (!write_batch) {
        set_error(out_error, "invalid write batch");
        return -1;
    }
    leveldb::WriteOptions options;
    options.sync = sync != 0;
    const auto status = state->db->Write(options, &write_batch->batch);
    if (!status.ok()) {
        set_error(out_error, status.ToString());
        return -1;
    }
    return 0;
}

mcbe_iter_t mcbe_iter_create(mcbe_db_t db, const uint8_t* prefix, size_t prefix_len,
                             int include_values, char** out_error) {
    DatabaseState* owner = nullptr;
    if (require_database(db, &owner, out_error) != 0) return nullptr;
    if (!valid_bytes(prefix, prefix_len)) {
        set_error(out_error, "invalid iterator prefix");
        return nullptr;
    }
    try {
        std::unique_ptr<IteratorState> state(new IteratorState());
        state->owner = owner;
        state->include_values = include_values != 0;
        state->use_prefix = prefix_len != 0;
        if (prefix_len != 0)
            state->prefix.assign(reinterpret_cast<const char*>(prefix), prefix_len);

        leveldb::ReadOptions options = owner->read_options;
        options.fill_cache = state->include_values;
        state->iterator.reset(owner->db->NewIterator(options));
        if (state->use_prefix) state->iterator->Seek(leveldb::Slice(state->prefix));
        else state->iterator->SeekToFirst();
        return state.release();
    } catch (const std::exception& error) {
        set_error(out_error, error.what());
        return nullptr;
    } catch (...) {
        set_error(out_error, "unknown native exception while creating iterator");
        return nullptr;
    }
}

void mcbe_iter_destroy(mcbe_iter_t handle) {
    delete iterator(handle);
}

int mcbe_iter_valid(mcbe_iter_t handle) {
    auto* state = iterator(handle);
    return state && state->key_matches_prefix() ? 1 : 0;
}

void mcbe_iter_next(mcbe_iter_t handle) {
    auto* state = iterator(handle);
    if (state && state->iterator && state->iterator->Valid()) state->iterator->Next();
}

const uint8_t* mcbe_iter_key(mcbe_iter_t handle, size_t* out_len) {
    if (out_len) *out_len = 0;
    auto* state = iterator(handle);
    if (!state || !state->key_matches_prefix() || !out_len) return nullptr;
    const auto value = state->iterator->key();
    *out_len = value.size();
    return reinterpret_cast<const uint8_t*>(value.data());
}

const uint8_t* mcbe_iter_value(mcbe_iter_t handle, size_t* out_len) {
    if (out_len) *out_len = 0;
    auto* state = iterator(handle);
    if (!state || !state->key_matches_prefix() || !out_len || !state->include_values) return nullptr;
    const auto value = state->iterator->value();
    *out_len = value.size();
    return reinterpret_cast<const uint8_t*>(value.data());
}

int mcbe_iter_status(mcbe_iter_t handle, char** out_error) {
    clear_error(out_error);
    auto* state = iterator(handle);
    if (!state || !state->iterator) {
        set_error(out_error, "iterator is closed");
        return -1;
    }
    const auto status = state->iterator->status();
    if (!status.ok()) {
        set_error(out_error, status.ToString());
        return -1;
    }
    return 0;
}

void mcbe_free(void* pointer) {
    std::free(pointer);
}

} // extern "C"
