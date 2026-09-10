#import "BTCompressionBridge.h"
#include <zlib.h>
#include <climits>

static NSString * const BTCompressionErrorDomain = @"MCBEEditor.Compression";

// Raw ZIP entries have an exact declared size; wrapped NBT callers pass only
// an estimate. Share the streaming loop while keeping these contracts distinct.
static NSData * _Nullable BTInflateData(NSData *data, NSUInteger expectedSize, int windowBits,
                                       BOOL exactSize, NSError * _Nullable __autoreleasing *error) {
    if (data.length > UINT_MAX) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:Z_BUF_ERROR
                                          userInfo:@{NSLocalizedDescriptionKey: @"压缩输入超过 zlib 单次输入范围"}];
        return nil;
    }
    z_stream stream = {};
    stream.next_in = const_cast<Bytef *>(reinterpret_cast<const Bytef *>(data.bytes));
    stream.avail_in = static_cast<uInt>(data.length);
    int result = inflateInit2(&stream, windowBits);
    if (result != Z_OK) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:result
                                          userInfo:@{NSLocalizedDescriptionKey: @"初始化 Deflate/GZip/Zlib 解压失败"}];
        return nil;
    }

    // Do not allocate the archive's claimed size before validating its stream.
    // A fixed output window also bounds how far a forged ZIP entry can expand
    // beyond its declared length before it is rejected.
    NSMutableData *output = [NSMutableData dataWithCapacity:MIN(expectedSize, 64 * 1024)];
    Bytef buffer[64 * 1024];
    BOOL sizeMismatch = NO;
    do {
        stream.next_out = buffer;
        stream.avail_out = static_cast<uInt>(sizeof(buffer));
        result = inflate(&stream, Z_NO_FLUSH);
        const NSUInteger produced = sizeof(buffer) - stream.avail_out;
        if (exactSize && (output.length > expectedSize || produced > expectedSize - output.length)) {
            sizeMismatch = YES;
            break;
        }
        if (produced > 0) [output appendBytes:buffer length:produced];
    } while (result == Z_OK);
    inflateEnd(&stream);

    if (sizeMismatch || (exactSize && result == Z_STREAM_END && output.length != expectedSize)) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:Z_DATA_ERROR
                                          userInfo:@{NSLocalizedDescriptionKey: @"ZIP 解压长度与声明长度不匹配"}];
        return nil;
    }
    if (result != Z_STREAM_END) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:result
                                          userInfo:@{NSLocalizedDescriptionKey: @"Deflate/GZip/Zlib 数据损坏或不完整"}];
        return nil;
    }
    return output;
}

@implementation BTCompressionBridge

+ (nullable NSData *)inflateRawData:(NSData *)data expectedSize:(NSUInteger)expectedSize error:(NSError * _Nullable __autoreleasing *)error {
    return BTInflateData(data, expectedSize, -MAX_WBITS, YES, error);
}

+ (nullable NSData *)inflateWrappedData:(NSData *)data expectedSize:(NSUInteger)expectedSize error:(NSError * _Nullable __autoreleasing *)error {
    // MAX_WBITS + 32 accepts both gzip and zlib wrappers.
    return BTInflateData(data, expectedSize, MAX_WBITS + 32, NO, error);
}

+ (nullable NSData *)deflateRawData:(NSData *)data compressionLevel:(NSInteger)level error:(NSError * _Nullable __autoreleasing *)error {
    if (data.length > UINT_MAX) {
        if (error) *error = [NSError errorWithDomain:BTCompressionErrorDomain code:Z_BUF_ERROR
                                          userInfo:@{NSLocalizedDescriptionKey: @"压缩输入超过 zlib 单次输入范围"}];
        return nil;
    }
    z_stream stream = {};
    stream.next_in = const_cast<Bytef *>(reinterpret_cast<const Bytef *>(data.bytes));
    stream.avail_in = static_cast<uInt>(data.length);
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
    const Bytef *bytes = reinterpret_cast<const Bytef *>(data.bytes);
    NSUInteger offset = 0;
    while (offset < data.length) {
        const uInt count = static_cast<uInt>(MIN(data.length - offset, UINT_MAX));
        value = crc32(value, bytes + offset, count);
        offset += count;
    }
    return static_cast<uint32_t>(value);
}

@end
