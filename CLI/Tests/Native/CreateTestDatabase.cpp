#include <iostream>
#include <memory>
#include "leveldb/db.h"
#include "leveldb/options.h"

// Test fixture tool only. Production still opens existing worlds with create_if_missing=false.
int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Usage: mcbe_cli_create_test_db db-directory\n";
        return 2;
    }
    leveldb::Options options;
    options.create_if_missing = true;
    options.error_if_exists = true;
    leveldb::DB* raw = nullptr;
    const auto status = leveldb::DB::Open(options, argv[1], &raw);
    std::unique_ptr<leveldb::DB> database(raw);
    if (!status.ok()) {
        std::cerr << status.ToString() << '\n';
        return 1;
    }
    return 0;
}
