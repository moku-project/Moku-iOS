#import <Foundation/Foundation.h>
#import "TSVideoEngine.h"
@interface VideoObserver : NSObject <BackendVideoObserver>
@property double deadline;
@end
@implementation VideoObserver
- (BOOL)cancelled { return self.deadline>0 && NSDate.date.timeIntervalSince1970>=self.deadline; }
- (void)progress:(double)fraction bytes:(int64_t)bytes bytesPerSecond:(double)speed {
 if (fraction<0 || fraction>=1 || bytes<0 || speed<0) abort();
}
@end
int main(int argc,const char **argv) {
 @autoreleasepool {
  if (argc<4) return 2;
  VideoObserver *observer=[VideoObserver new];
  if(argc>4) observer.deadline=NSDate.date.timeIntervalSince1970+atof(argv[4]);
  NSError *error=nil;
  BOOL ok=[[TSVideoEngine new] process:@(argv[1]) headersJSON:@(argv[2]) outputPath:@(argv[3]) observer:observer error:&error];
  if(!ok) fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);
  return ok?0:1;
 }
}
