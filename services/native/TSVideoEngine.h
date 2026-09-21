#import <Foundation/Foundation.h>
#import <Tsunagu/Backend.objc.h>
NS_ASSUME_NONNULL_BEGIN
/// Synchronous media worker; Go calls it on a download worker, never the main queue.
@interface TSVideoEngine : NSObject <BackendVideoEngine>
@end
NS_ASSUME_NONNULL_END
