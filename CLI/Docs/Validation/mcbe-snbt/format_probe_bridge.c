#include <stdlib.h>
#include <limits.h>
#include "zlib.h"
int snbt_test_inflate(const unsigned char *input, size_t length, unsigned char **output, size_t *size) {
    if (length > UINT_MAX) return -1;
    z_stream stream = {0};
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)length;
    if (inflateInit2(&stream, 15 + 32) != Z_OK) return -1;
    size_t capacity = 65536;
    unsigned char *buffer = malloc(capacity);
    int code = Z_OK;
    if (!buffer) { inflateEnd(&stream); return -1; }
    while (code == Z_OK) {
        if (stream.total_out == capacity) {
            if (capacity >= 512UL * 1024 * 1024) break;
            capacity *= 2;
            unsigned char *grown = realloc(buffer, capacity);
            if (!grown) break;
            buffer = grown;
        }
        stream.next_out = buffer + stream.total_out;
        stream.avail_out = (uInt)(capacity - stream.total_out);
        code = inflate(&stream, Z_NO_FLUSH);
    }
    int success = code == Z_STREAM_END && stream.avail_in == 0;
    *size = stream.total_out;
    inflateEnd(&stream);
    if (!success) { free(buffer); return -1; }
    *output = buffer;
    return 0;
}
