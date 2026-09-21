#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Embedded interpreter prototype. Start only once per app process, off the main
/// thread. This object does not download code, create subprocesses, or enable JIT.
@interface TSJavaRuntime : NSObject
+ (nullable NSString *)probeWithRuntimeHome:(NSString *)runtimeHome
                                classPath:(NSString *)classPath
                                 fixture:(NSString *)fixture
                                   error:(NSError **)error;
+ (NSInteger)startSandboxWithRuntimeHome:(NSString *)runtimeHome
                              classPath:(NSString *)classPath
                          dataDirectory:(NSString *)directory
                                  token:(NSString *)token
                                  error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
