#import "BTCompressionBridge.h"
#include <zlib.h>

static NSString * const BTCompressionErrorDomain = @"Blocktopograph.Compression";

@implementation BTCompressionBridge

+ (nullable NSData *)inflateRawData:(NSData *)data expectedSize:(NSUInteger)expectedSize error:(NSError * _Nullable __autoreleasing *)error {
    z_stream stream = {};
    stream.next_in = const_cast<Bytef *>(reinterpret_cast<const Bytef *>(data.bytes));
    stream.avail_in = static_cast<uInt>(MIN(data.length, UINT_MAX));
    int result = inflateInit2(&stream, -MAX_WBITS);
    if (result != Z_OK) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:result userInfo:@{NSLocalizedDescriptionKey: @"初始化 Deflate 解压失败"}];
        return nil;
    }

    NSMutableData *output = [NSMutableData dataWithLength:MAX(expectedSize, 64 * 1024)];
    do {
        if (stream.total_out >= output.length) {
            [output increaseLengthBy:MAX(output.length / 2, 64 * 1024)];
        }
        stream.next_out = reinterpret_cast<Bytef *>(output.mutableBytes) + stream.total_out;
        stream.avail_out = static_cast<uInt>(MIN(output.length - stream.total_out, UINT_MAX));
        result = inflate(&stream, Z_NO_FLUSH);
    } while (result == Z_OK);

    inflateEnd(&stream);
    if (result != Z_STREAM_END) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:result userInfo:@{NSLocalizedDescriptionKey: @"Deflate 数据损坏或不完整"}];
        return nil;
    }
    output.length = stream.total_out;
    return output;
}

+ (nullable NSData *)inflateWrappedData:(NSData *)data expectedSize:(NSUInteger)expectedSize error:(NSError * _Nullable __autoreleasing *)error {
    z_stream stream = {};
    stream.next_in = const_cast<Bytef *>(reinterpret_cast<const Bytef *>(data.bytes));
    stream.avail_in = static_cast<uInt>(MIN(data.length, UINT_MAX));
    // MAX_WBITS + 32 lets zlib accept both gzip and zlib wrappers.
    int result = inflateInit2(&stream, MAX_WBITS + 32);
    if (result != Z_OK) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:result userInfo:@{NSLocalizedDescriptionKey: @"初始化 GZip／Zlib 解压失败"}];
        return nil;
    }

    NSMutableData *output = [NSMutableData dataWithLength:MAX(expectedSize, 64 * 1024)];
    do {
        if (stream.total_out >= output.length) {
            [output increaseLengthBy:MAX(output.length / 2, 64 * 1024)];
        }
        stream.next_out = reinterpret_cast<Bytef *>(output.mutableBytes) + stream.total_out;
        stream.avail_out = static_cast<uInt>(MIN(output.length - stream.total_out, UINT_MAX));
        result = inflate(&stream, Z_NO_FLUSH);
    } while (result == Z_OK);

    inflateEnd(&stream);
    if (result != Z_STREAM_END) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:result userInfo:@{NSLocalizedDescriptionKey: @"GZip／Zlib 数据损坏或不完整"}];
        return nil;
    }
    output.length = stream.total_out;
    return output;
}

+ (nullable NSData *)deflateRawData:(NSData *)data compressionLevel:(NSInteger)level error:(NSError * _Nullable __autoreleasing *)error {
    z_stream stream = {};
    stream.next_in = const_cast<Bytef *>(reinterpret_cast<const Bytef *>(data.bytes));
    stream.avail_in = static_cast<uInt>(MIN(data.length, UINT_MAX));
    int normalizedLevel = (level < -1 || level > 9) ? Z_DEFAULT_COMPRESSION : static_cast<int>(level);
    int result = deflateInit2(&stream, normalizedLevel, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
    if (result != Z_OK) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:result userInfo:@{NSLocalizedDescriptionKey: @"初始化 Deflate 压缩失败"}];
        return nil;
    }

    NSMutableData *output = [NSMutableData dataWithLength:MAX(data.length / 2, 64 * 1024)];
    do {
        if (stream.total_out >= output.length) {
            [output increaseLengthBy:MAX(output.length / 2, 64 * 1024)];
        }
        stream.next_out = reinterpret_cast<Bytef *>(output.mutableBytes) + stream.total_out;
        stream.avail_out = static_cast<uInt>(MIN(output.length - stream.total_out, UINT_MAX));
        result = deflate(&stream, Z_FINISH);
    } while (result == Z_OK);

    deflateEnd(&stream);
    if (result != Z_STREAM_END) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:result userInfo:@{NSLocalizedDescriptionKey: @"Deflate 压缩失败"}];
        return nil;
    }
    output.length = stream.total_out;
    return output;
}

+ (uint32_t)crc32ForData:(NSData *)data {
    uLong value = crc32(0L, Z_NULL, 0);
    value = crc32(value, reinterpret_cast<const Bytef *>(data.bytes), static_cast<uInt>(MIN(data.length, UINT_MAX)));
    return static_cast<uint32_t>(value);
}

@end
