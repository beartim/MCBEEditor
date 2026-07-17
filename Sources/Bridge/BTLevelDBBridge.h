#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BTLevelDBEntry : NSObject
@property(nonatomic, readonly) NSData *key;
@property(nonatomic, readonly, nullable) NSData *value;
- (instancetype)initWithKey:(NSData *)key value:(nullable NSData *)value;
@end

/// A read result that distinguishes a missing LevelDB key from a real error.
///
/// Returning nil from an Objective-C method that also has an NSError** parameter
/// is interpreted by Swift as a thrown failure. LevelDB uses "not found" as a
/// normal lookup result, so it must be represented explicitly instead.
@interface BTLevelDBReadResult : NSObject
@property(nonatomic, readonly) BOOL found;
@property(nonatomic, readonly, nullable) NSData *value;
@property(nonatomic, readonly, nullable) NSError *error;
- (instancetype)initWithFound:(BOOL)found
                         value:(nullable NSData *)value
                         error:(nullable NSError *)error;
@end

@interface BTLevelDBBridge : NSObject {
@public
    void *_state; // implementation-only C++ state; do not access from Swift
}

- (nullable instancetype)initWithPath:(NSString *)path
                             readOnly:(BOOL)readOnly
                                error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Reads a key without using the NSError** object-return convention, so a
/// missing key remains a normal optional result in Swift rather than becoming
/// Foundation._GenericObjCError error 0.
- (BTLevelDBReadResult *)readResultForKey:(NSData *)key NS_SWIFT_NAME(readResult(forKey:));

- (BOOL)putData:(NSData *)value forKey:(NSData *)key sync:(BOOL)sync error:(NSError * _Nullable * _Nullable)error;
- (BOOL)deleteKey:(NSData *)key sync:(BOOL)sync error:(NSError * _Nullable * _Nullable)error;

/// Applies puts and deletes atomically using one LevelDB WriteBatch.
- (BOOL)applyBatchWithPuts:(NSArray<BTLevelDBEntry *> *)puts
               deleteKeys:(NSArray<NSData *> *)deleteKeys
                      sync:(BOOL)sync
                     error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(applyBatch(puts:deleteKeys:sync:));

/// Returns keys in LevelDB byte-order. Pass nil for a full scan.
- (nullable NSArray<BTLevelDBEntry *> *)entriesWithPrefix:(nullable NSData *)prefix
                                             includeValue:(BOOL)includeValue
                                                    limit:(NSUInteger)limit
                                                    error:(NSError * _Nullable * _Nullable)error;
- (void)close;

@end

NS_ASSUME_NONNULL_END
