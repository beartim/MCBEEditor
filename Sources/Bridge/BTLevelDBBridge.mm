#import "BTLevelDBBridge.h"

#include <cstring>
#include <memory>
#include <string>

// leveldb-mcpe decorates public declarations with DLLX. The static-library
// target defines it through build settings, but this bridge is compiled in
// the application target, so keep a local fallback as well.
#ifndef DLLX
#define DLLX
#endif

#include "leveldb/cache.h"
#include "leveldb/db.h"
#include "leveldb/env.h"  // Complete definition of leveldb::Logger.
#include "leveldb/decompress_allocator.h"
#include "leveldb/filter_policy.h"
#include "leveldb/iterator.h"
#include "leveldb/options.h"
#include "leveldb/zlib_compressor.h"
#include "leveldb/write_batch.h"

static NSString * const BTLevelDBErrorDomain = @"Blocktopograph.LevelDB";

static NSError *BTStatusError(const leveldb::Status &status, NSString *operation) {
    NSString *message = [NSString stringWithUTF8String:status.ToString().c_str()] ?: @"Unknown LevelDB error";
    return [NSError errorWithDomain:BTLevelDBErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %@", operation, message]}];
}

class BTNullLogger final : public leveldb::Logger {
public:
    void Logv(const char *, va_list) override {}
};

struct BTLevelDBState final {
    std::unique_ptr<const leveldb::FilterPolicy> filterPolicy;
    std::unique_ptr<leveldb::Cache> blockCache;
    BTNullLogger logger;
    leveldb::ZlibCompressorRaw zlibRaw;
    leveldb::ZlibCompressor zlib;
    leveldb::DecompressAllocator decompressAllocator;
    leveldb::Options options;
    leveldb::ReadOptions readOptions;
    std::unique_ptr<leveldb::DB> db;
    bool readOnly;

    explicit BTLevelDBState(bool isReadOnly) : zlibRaw(-1), readOnly(isReadOnly) {
        filterPolicy.reset(leveldb::NewBloomFilterPolicy(10));
        blockCache.reset(leveldb::NewLRUCache(16 * 1024 * 1024));

        options.create_if_missing = false;
        options.error_if_exists = false;
        options.paranoid_checks = false;
        options.filter_policy = filterPolicy.get();
        options.block_cache = blockCache.get();
        options.write_buffer_size = 4 * 1024 * 1024;
        options.block_size = 163840;
        options.max_open_files = 128;
        options.info_log = &logger;
        options.compressors[0] = &zlibRaw;
        options.compressors[1] = &zlib;

        readOptions.verify_checksums = true;
        readOptions.fill_cache = true;
        readOptions.decompress_allocator = &decompressAllocator;
    }
};

static BTLevelDBState *BTState(BTLevelDBBridge *bridge) {
    return reinterpret_cast<BTLevelDBState *>(bridge->_state);
}

@implementation BTLevelDBEntry
- (instancetype)initWithKey:(NSData *)key value:(NSData * _Nullable)value {
    self = [super init];
    if (self) {
        _key = [key copy];
        _value = [value copy];
    }
    return self;
}
@end

@implementation BTLevelDBReadResult
- (instancetype)initWithFound:(BOOL)found
                         value:(NSData * _Nullable)value
                         error:(NSError * _Nullable)error {
    self = [super init];
    if (self) {
        _found = found;
        _value = [value copy];
        _error = [error copy];
    }
    return self;
}
@end

@implementation BTLevelDBBridge

- (nullable instancetype)initWithPath:(NSString *)path
                             readOnly:(BOOL)readOnly
                                error:(NSError * _Nullable __autoreleasing *)error {
    self = [super init];
    if (!self) { return nil; }

    std::unique_ptr<BTLevelDBState> state(new BTLevelDBState(readOnly));
    leveldb::DB *database = nullptr;
    leveldb::Status status = leveldb::DB::Open(state->options, path.fileSystemRepresentation, &database);
    if (!status.ok()) {
        if (error) { *error = BTStatusError(status, @"打开数据库"); }
        return nil;
    }
    state->db.reset(database);
    _state = state.release();
    return self;
}

- (BTLevelDBReadResult *)readResultForKey:(NSData *)key {
    BTLevelDBState *state = BTState(self);
    if (!state || !state->db) {
        NSError *error = [NSError errorWithDomain:BTLevelDBErrorDomain
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"数据库已经关闭"}];
        return [[BTLevelDBReadResult alloc] initWithFound:NO value:nil error:error];
    }

    std::string value;
    leveldb::Slice keySlice(reinterpret_cast<const char *>(key.bytes), key.length);
    leveldb::Status status = state->db->Get(state->readOptions, keySlice, &value);
    if (status.IsNotFound()) {
        return [[BTLevelDBReadResult alloc] initWithFound:NO value:nil error:nil];
    }
    if (!status.ok()) {
        return [[BTLevelDBReadResult alloc] initWithFound:NO
                                                   value:nil
                                                   error:BTStatusError(status, @"读取键")];
    }

    NSData *data = [NSData dataWithBytes:value.data() length:value.size()];
    return [[BTLevelDBReadResult alloc] initWithFound:YES value:data error:nil];
}

- (BOOL)putData:(NSData *)value forKey:(NSData *)key sync:(BOOL)sync error:(NSError * _Nullable __autoreleasing *)error {
    BTLevelDBState *state = BTState(self);
    if (!state || !state->db) {
        if (error) { *error = [NSError errorWithDomain:BTLevelDBErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"数据库已经关闭"}]; }
        return NO;
    }
    if (state->readOnly) {
        if (error) { *error = [NSError errorWithDomain:BTLevelDBErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"数据库以只读方式打开"}]; }
        return NO;
    }
    leveldb::WriteOptions options;
    options.sync = sync;
    leveldb::Slice keySlice(reinterpret_cast<const char *>(key.bytes), key.length);
    leveldb::Slice valueSlice(reinterpret_cast<const char *>(value.bytes), value.length);
    leveldb::Status status = state->db->Put(options, keySlice, valueSlice);
    if (!status.ok()) {
        if (error) { *error = BTStatusError(status, @"写入键"); }
        return NO;
    }
    return YES;
}

- (BOOL)deleteKey:(NSData *)key sync:(BOOL)sync error:(NSError * _Nullable __autoreleasing *)error {
    BTLevelDBState *state = BTState(self);
    if (!state || !state->db) {
        if (error) { *error = [NSError errorWithDomain:BTLevelDBErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"数据库已经关闭"}]; }
        return NO;
    }
    if (state->readOnly) {
        if (error) { *error = [NSError errorWithDomain:BTLevelDBErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"数据库以只读方式打开"}]; }
        return NO;
    }
    leveldb::WriteOptions options;
    options.sync = sync;
    leveldb::Slice keySlice(reinterpret_cast<const char *>(key.bytes), key.length);
    leveldb::Status status = state->db->Delete(options, keySlice);
    if (!status.ok()) {
        if (error) { *error = BTStatusError(status, @"删除键"); }
        return NO;
    }
    return YES;
}


- (BOOL)applyBatchWithPuts:(NSArray<BTLevelDBEntry *> *)puts
               deleteKeys:(NSArray<NSData *> *)deleteKeys
                      sync:(BOOL)sync
                     error:(NSError * _Nullable __autoreleasing *)error {
    BTLevelDBState *state = BTState(self);
    if (!state || !state->db) {
        if (error) { *error = [NSError errorWithDomain:BTLevelDBErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"数据库已经关闭"}]; }
        return NO;
    }
    if (state->readOnly) {
        if (error) { *error = [NSError errorWithDomain:BTLevelDBErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"数据库以只读方式打开"}]; }
        return NO;
    }

    leveldb::WriteBatch batch;
    // Deletes are added before puts so a copy operation can atomically replace
    // destination keys that have the same byte representation as new records.
    for (NSData *key in deleteKeys) {
        leveldb::Slice keySlice(reinterpret_cast<const char *>(key.bytes), key.length);
        batch.Delete(keySlice);
    }
    for (BTLevelDBEntry *entry in puts) {
        if (!entry.value) {
            if (error) { *error = [NSError errorWithDomain:BTLevelDBErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey: @"批量写入条目缺少 value"}]; }
            return NO;
        }
        leveldb::Slice keySlice(reinterpret_cast<const char *>(entry.key.bytes), entry.key.length);
        leveldb::Slice valueSlice(reinterpret_cast<const char *>(entry.value.bytes), entry.value.length);
        batch.Put(keySlice, valueSlice);
    }

    leveldb::WriteOptions options;
    options.sync = sync;
    leveldb::Status status = state->db->Write(options, &batch);
    if (!status.ok()) {
        if (error) { *error = BTStatusError(status, @"批量写入数据库"); }
        return NO;
    }
    return YES;
}

- (nullable NSArray<BTLevelDBEntry *> *)entriesWithPrefix:(NSData * _Nullable)prefix
                                             includeValue:(BOOL)includeValue
                                                    limit:(NSUInteger)limit
                                                    error:(NSError * _Nullable __autoreleasing *)error {
    BTLevelDBState *state = BTState(self);
    if (!state || !state->db) {
        if (error) { *error = [NSError errorWithDomain:BTLevelDBErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"数据库已经关闭"}]; }
        return nil;
    }

    std::string prefixString;
    if (prefix) { prefixString.assign(reinterpret_cast<const char *>(prefix.bytes), prefix.length); }

    leveldb::ReadOptions options = state->readOptions;
    options.fill_cache = includeValue;
    std::unique_ptr<leveldb::Iterator> iterator(state->db->NewIterator(options));
    if (prefix) { iterator->Seek(leveldb::Slice(prefixString)); }
    else { iterator->SeekToFirst(); }

    NSMutableArray<BTLevelDBEntry *> *entries = [NSMutableArray array];
    while (iterator->Valid() && (limit == 0 || entries.count < limit)) {
        leveldb::Slice key = iterator->key();
        if (prefix && (key.size() < prefixString.size() || std::memcmp(key.data(), prefixString.data(), prefixString.size()) != 0)) { break; }
        NSData *keyData = [NSData dataWithBytes:key.data() length:key.size()];
        NSData *valueData = nil;
        if (includeValue) {
            leveldb::Slice value = iterator->value();
            valueData = [NSData dataWithBytes:value.data() length:value.size()];
        }
        [entries addObject:[[BTLevelDBEntry alloc] initWithKey:keyData value:valueData]];
        iterator->Next();
    }
    if (!iterator->status().ok()) {
        if (error) { *error = BTStatusError(iterator->status(), @"遍历数据库"); }
        return nil;
    }
    return entries;
}

- (void)close {
    BTLevelDBState *state = BTState(self);
    if (state) {
        delete state;
        _state = nullptr;
    }
}

- (void)dealloc { [self close]; }

@end
