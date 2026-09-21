#import <UIKit/UIKit.h>
#import "TSVideoEngine.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <libavformat/avformat.h>

@interface MediaObserver : NSObject <BackendVideoObserver>
@end
@implementation MediaObserver
- (BOOL)cancelled { return NO; }
- (void)progress:(double)fraction bytes:(int64_t)bytes bytesPerSecond:(double)speed {}
@end
static int serveFixtures(void) {
 int listener=socket(AF_INET,SOCK_STREAM,0);
 struct sockaddr_in address={.sin_len=sizeof(address),.sin_family=AF_INET,.sin_port=0,.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
 if(bind(listener,(struct sockaddr*)&address,sizeof(address)) || listen(listener,8)) abort();
 socklen_t length=sizeof(address); getsockname(listener,(struct sockaddr*)&address,&length);
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
  while(1) {
   int client=accept(listener,NULL,NULL); if(client<0) break;
   dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
    char buffer[8192]={0}; ssize_t size=read(client,buffer,sizeof(buffer)-1);
    if(size<=0){close(client);return;}
    NSString *request=[[NSString alloc] initWithBytes:buffer length:size encoding:NSUTF8StringEncoding];
    NSString *name=[[request componentsSeparatedByString:@" "] objectAtIndex:1];
    name=name.lastPathComponent;
    NSData *data=[NSData dataWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:name]];
    if(!data){close(client);return;}
    NSUInteger start=0,end=data.length-1;int status=200;
    NSRange range=[request rangeOfString:@"Range: bytes=" options:NSCaseInsensitiveSearch];
    if(range.location!=NSNotFound){
     NSString *value=[[request substringFromIndex:NSMaxRange(range)] componentsSeparatedByString:@"\r\n"].firstObject;
     NSArray *parts=[value componentsSeparatedByString:@"-"];start=[parts[0] longLongValue];
     if(parts.count>1 && [parts[1] length])end=MIN(end,[parts[1] longLongValue]);status=206;
    }
    if(start>end){close(client);return;}
    NSString *extra=status==206?[NSString stringWithFormat:@"Content-Range: bytes %lu-%lu/%lu\r\n",start,end,data.length]:@"";
    NSString *header=[NSString stringWithFormat:@"HTTP/1.1 %d OK\r\nContent-Length: %lu\r\nAccept-Ranges: bytes\r\n%@Connection: close\r\n\r\n",status,end-start+1,extra];
    int yes=1;setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    write(client,header.UTF8String,strlen(header.UTF8String));
    const char *bytes=data.bytes;NSUInteger at=start;
    while(at<=end){ssize_t count=write(client,bytes+at,end-at+1);if(count<=0)break;at+=count;}
    close(client);
   });
  }
 });
 return ntohs(address.sin_port);
}
@interface MediaProbe : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation MediaProbe
- (BOOL)application:(UIApplication*)app didFinishLaunchingWithOptions:(NSDictionary*)options {
 self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
 self.window.rootViewController=[UIViewController new];[self.window makeKeyAndVisible];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  int port=serveFixtures();NSMutableArray *results=[NSMutableArray array];BOOL success=YES;
  for(NSString *name in @[@"input.mp4",@"convert.avi"]) {
   NSError *error=nil;NSString *output=[NSTemporaryDirectory() stringByAppendingPathComponent:[name stringByAppendingString:@".mp4"]];
   BOOL ok=[[TSVideoEngine new] process:[NSString stringWithFormat:@"http://127.0.0.1:%d/%@",port,name] headersJSON:@"{}" outputPath:output observer:[MediaObserver new] error:&error];
   if(ok){AVFormatContext *context=NULL;ok=avformat_open_input(&context,output.UTF8String,NULL,NULL)>=0 && avformat_find_stream_info(context,NULL)>=0 && context->duration>=1800000;avformat_close_input(&context);}
   [results addObject:@{@"case":name,@"passed":@(ok),@"error":error.localizedDescription?:@""}];success&=ok;
   [[NSFileManager defaultManager] removeItemAtPath:output error:nil];
  }
  NSData *json=[NSJSONSerialization dataWithJSONObject:results options:0 error:nil];
  printf("MEDIA_DEVICE_RESULT %s\n",[[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);fflush(stdout);
  exit(success?0:1);
 });return YES;
}
@end
int main(int argc,char**argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(MediaProbe.class));}}
