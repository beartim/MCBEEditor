#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BTCompressionBridge : NSObject
+ (nullable NSData *)inflateRawData:(NSData *)data expectedSize:(NSUInteger)expectedSize error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(inflateRaw(_:expectedSize:));
+ (nullable NSData *)inflateWrappedData:(NSData *)data expectedSize:(NSUInteger)expectedSize error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(inflateWrapped(_:expectedSize:));
+ (nullable NSData *)deflateRawData:(NSData *)data compressionLevel:(NSInteger)level error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(deflateRaw(_:level:));
+ (uint32_t)crc32ForData:(NSData *)data NS_SWIFT_NAME(crc32(_:));
@end

NS_ASSUME_NONNULL_END
