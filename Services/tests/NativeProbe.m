#import <UIKit/UIKit.h>
#import <Tsunagu/Backend.objc.h>
#import "TSJavaRuntime.h"
#import "TSVideoEngine.h"

@interface Probe : UIResponder <UIApplicationDelegate>
@end
@implementation Probe
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
  @autoreleasepool {
   NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
   NSMutableDictionary *report=[NSMutableDictionary dictionary];
   NSError *error=nil;
   BackendService *service=BackendNewService();
   [service setVideoEngine:[TSVideoEngine new] error:&error];
   NSString *resources=NSBundle.mainBundle.resourcePath;
   BOOL search=[NSProcessInfo.processInfo.arguments containsObject:@"--search"];
   BOOL acceptance=[NSProcessInfo.processInfo.arguments containsObject:@"--acceptance"];
   search=search || acceptance;
   NSString *folder=search ? [@"backend-proof-" stringByAppendingString:NSUUID.UUID.UUIDString] : @"backend";
   NSUInteger resume=[NSProcessInfo.processInfo.arguments indexOfObject:@"--resume-acceptance"];
   if(acceptance && resume != NSNotFound && resume+1 < NSProcessInfo.processInfo.arguments.count) {
    NSString *saved=NSProcessInfo.processInfo.arguments[resume+1];
    if([saved hasPrefix:@"backend-proof-"] && [saved.lastPathComponent isEqualToString:saved]) folder=saved;
   }
   NSString *directory=[documents stringByAppendingPathComponent:folder];
   report[@"dataDirectory"]=folder;
   BOOL started=NO;
   NSInteger sandboxPort=0;
   NSString *sandboxToken=nil;
   if(search) {
    NSString *token=[NSUUID.UUID.UUIDString stringByAppendingString:NSUUID.UUID.UUIDString];
    NSInteger port=[TSJavaRuntime startSandboxWithRuntimeHome:resources classPath:[resources stringByAppendingPathComponent:@"Sandbox.jar"] dataDirectory:directory token:token error:&error];
    if(port>0) {
     sandboxPort=port; sandboxToken=token;
     report[@"jvm"]=@"Tsunagu sandbox started";
     started=[service startWithSandbox:directory address:[NSString stringWithFormat:@"127.0.0.1:%ld",(long)port] token:token error:&error];
    }
   } else { started=[service start:directory error:&error]; }
   if(started) {
    if(acceptance) {
     // Test host only: a fresh, private handoff lets the host-side acceptance
     // runner exercise the actual simulator service. Never log credentials.
     NSString *connection=[documents stringByAppendingPathComponent:@"acceptance-connection.json"];
     NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"baseURL":[service baseURL], @"token":[service accessToken], @"dataDirectory":folder, @"sandboxPort":@(sandboxPort), @"sandboxToken":sandboxToken} options:0 error:nil];
     [data writeToFile:connection options:NSDataWritingAtomic error:&error];
     [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:connection error:nil];
     NSString *stop=[documents stringByAppendingPathComponent:@"acceptance-stop"];
     NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:900];
     while(![[NSFileManager defaultManager] fileExistsAtPath:stop] && [deadline timeIntervalSinceNow]>0) [NSThread sleepForTimeInterval:0.2];
     [service stop:&error];
     [[NSFileManager defaultManager] removeItemAtPath:connection error:nil];
     return;
    }
    NSArray *queries=@[@"mutation { addRepository(indexUrl: \"https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb\", name: \"Keiyoushi\") { id name } }", @"{ extensions(query: \"mangadex\", limit: 10) { total items { id name packageName version installed } } }"];
    if(search) queries=[queries arrayByAddingObjectsFromArray:@[
     @"mutation { installExtension(packageName: \"eu.kanade.tachiyomi.extension.all.mangadex\") { id name version installed } }",
     @"{ search(extensionId: \"eu.kanade.tachiyomi.extension.all.mangadex\", query: \"Rent a Girlfriend\", page: 1) { results { id title } hasNextPage } }"
    ]];
    NSArray *keys=@[@"repository",@"extensions",@"installation",@"search"];
    for(NSUInteger i=0;i<queries.count;i++) {
     NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[[service baseURL] stringByAppendingString:@"/api/graphql"]]];
     request.HTTPMethod=@"POST"; request.timeoutInterval=120;
     [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
     [request setValue:[@"Bearer " stringByAppendingString:[service accessToken]] forHTTPHeaderField:@"Authorization"];
     request.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"query":queries[i]} options:0 error:nil];
     dispatch_semaphore_t done=dispatch_semaphore_create(0);
     __block id result;
     [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response,NSError *failure){
      result=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : failure.localizedDescription;
      dispatch_semaphore_signal(done);
     }] resume];
     dispatch_semaphore_wait(done,DISPATCH_TIME_FOREVER);
     report[keys[i]]=result ?: @"No response";
    }
    [service stop:&error];
   } else { report[@"backendError"]=error.localizedDescription ?: @"Sandbox startup returned no port"; }
   NSString *path=[documents stringByAppendingPathComponent:@"probe.json"];
   [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path atomically:YES];
   NSLog(@"CATALOG %@",report);
   if (![NSProcessInfo.processInfo.arguments containsObject:@"--jvm"]) return;
   NSString *jvm=[TSJavaRuntime probeWithRuntimeHome:resources classPath:[resources stringByAppendingPathComponent:@"RuntimeProbe.jar"] fixture:[resources stringByAppendingPathComponent:@"Fixture.jar"] error:&error];
   report[@"jvm"]=jvm ?: error.localizedDescription;
   [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path atomically:YES];
   NSLog(@"PROBE %@",report);
  }
 });
 return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(Probe.class)); } }
