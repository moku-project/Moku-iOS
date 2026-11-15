#import "TSJavaRuntime.h"
#include "jni.h"
#include <stdatomic.h>

static atomic_bool attempted = false;
static JavaVM *vm;

static NSString *exceptionMessage(JNIEnv *env) {
    jthrowable exception = (*env)->ExceptionOccurred(env);
    if (!exception) return @"Unknown Java failure";
    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);
    jclass type = (*env)->GetObjectClass(env, exception);
    jmethodID method = (*env)->GetMethodID(env, type, "toString", "()Ljava/lang/String;");
    jstring value = method ? (*env)->CallObjectMethod(env, exception, method) : NULL;
    NSString *message = @"Java exception";
    if (!(*env)->ExceptionCheck(env) && value) {
        const char *chars = (*env)->GetStringUTFChars(env, value, NULL);
        if (chars) { message = [NSString stringWithUTF8String:chars]; (*env)->ReleaseStringUTFChars(env,value,chars); }
    }
    (*env)->ExceptionClear(env);
    if (value) (*env)->DeleteLocalRef(env,value);
    (*env)->DeleteLocalRef(env,type);
    (*env)->DeleteLocalRef(env,exception);
    return message;
}

static JNIEnv *startVM(NSString *runtimeHome, NSString *classPath, NSString *temporaryDirectory, NSError **error) {
    if (error) *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:temporaryDirectory
                                 withIntermediateDirectories:YES attributes:nil error:error]) {
        return NULL;
    }
    if (atomic_exchange(&attempted, true)) {
        if(error) *error=[NSError errorWithDomain:@"Moku.JVM" code:1 userInfo:@{NSLocalizedDescriptionKey:@"The JVM may only be initialized once per process"}];
        return NULL;
    }
    NSArray<NSString *> *strings = @[
        [@"-Djava.home=" stringByAppendingString:[runtimeHome stringByAppendingPathComponent:@"lib"]],
        [@"-Djava.class.path=" stringByAppendingString:classPath],
        // NIO caches this at JVM initialization; setting it from Kotlin is too late.
        [@"-Djava.io.tmpdir=" stringByAppendingString:temporaryDirectory],
        // The JVM shares the app process: fix its worker count and cap NIO buffers apart from the heap.
        @"-Xms16m", @"-Xmx512m", @"-Xss2m",
        @"-XX:ActiveProcessorCount=2", @"-XX:MaxDirectMemorySize=64m",
        @"-Dkotlinx.coroutines.io.parallelism=4",
        @"-Djava.awt.headless=true",
        @"-Djava.net.preferIPv4Stack=true",
        @"-Dio.netty.transport.noNative=true",
        [@"-Djavax.net.ssl.trustStore=" stringByAppendingString:[runtimeHome stringByAppendingPathComponent:@"lib/security/cacerts"]]
    ];
    JavaVMOption options[strings.count];
    memset(options, 0, sizeof(options));
    for (NSUInteger i=0;i<strings.count;i++) options[i].optionString=(char *)strings[i].UTF8String;
    JavaVMInitArgs args = {0};
    args.version=JNI_VERSION_1_8; args.nOptions=(jint)strings.count; args.options=options; args.ignoreUnrecognized=JNI_FALSE;
    JNIEnv *env = NULL;
    jint result=JNI_CreateJavaVM(&vm,(void **)&env,&args);
    if(result!=JNI_OK) {
        if(error) *error=[NSError errorWithDomain:@"Moku.JVM" code:result userInfo:@{NSLocalizedDescriptionKey:@"JNI_CreateJavaVM failed"}];
        return NULL;
    }
    return env;
}


// MARK: Native HTTP for the sandbox (tsunagu.net.NativeHttp)

@interface TSNoRedirectDelegate : NSObject <NSURLSessionTaskDelegate>
@end
@implementation TSNoRedirectDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil); // OkHttp-side code follows redirects so cookies are saved per hop.
}
@end

static NSURLSession *nativeSession(void) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.HTTPShouldSetCookies = NO;
        config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
        config.HTTPCookieStorage = nil;
        config.URLCache = nil;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.HTTPMaximumConnectionsPerHost = 8;
        session = [NSURLSession sessionWithConfiguration:config delegate:[TSNoRedirectDelegate new] delegateQueue:nil];
    });
    return session;
}

static NSString *javaString(JNIEnv *env, jstring value) {
    if (!value) return nil;
    const char *chars = (*env)->GetStringUTFChars(env, value, NULL);
    NSString *result = chars ? [NSString stringWithUTF8String:chars] : nil;
    if (chars) (*env)->ReleaseStringUTFChars(env, value, chars);
    return result;
}

static void throwJava(JNIEnv *env, const char *type, NSString *message) {
    jclass cls = (*env)->FindClass(env, type);
    if (cls) (*env)->ThrowNew(env, cls, message.UTF8String ?: "native HTTP failed");
}

static NSString *setCookieLine(NSHTTPCookie *cookie) {
    NSMutableString *line = [NSMutableString stringWithFormat:@"%@=%@; Path=%@", cookie.name, cookie.value, cookie.path ?: @"/"];
    if ([cookie.domain hasPrefix:@"."]) [line appendFormat:@"; Domain=%@", [cookie.domain substringFromIndex:1]];
    if (cookie.expiresDate) {
        NSDateFormatter *format = [NSDateFormatter new];
        format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        format.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        format.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss 'GMT'";
        [line appendFormat:@"; Expires=%@", [format stringFromDate:cookie.expiresDate]];
    }
    if (cookie.isSecure) [line appendString:@"; Secure"];
    if (cookie.isHTTPOnly) [line appendString:@"; HttpOnly"];
    return line;
}

static jobjectArray JNICALL nativeExecute(JNIEnv *env, jclass cls, jstring jmethod, jstring jurl, jobjectArray jheaders,
                                          jbyteArray jbody, jint readTimeout, jint callTimeout) {
    NSURL *url = [NSURL URLWithString:javaString(env, jurl)];
    if (!url) { throwJava(env, "java/io/IOException", @"invalid URL"); return NULL; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = javaString(env, jmethod) ?: @"GET";
    request.HTTPShouldHandleCookies = NO;
    request.timeoutInterval = readTimeout > 0 ? readTimeout / 1000.0 : 60;
    jsize count = jheaders ? (*env)->GetArrayLength(env, jheaders) : 0;
    NSSet *skipped = [NSSet setWithArray:@[@"host", @"content-length", @"connection", @"accept-encoding", @"transfer-encoding"]];
    for (jsize i = 0; i + 1 < count; i += 2) {
        jstring name = (*env)->GetObjectArrayElement(env, jheaders, i), value = (*env)->GetObjectArrayElement(env, jheaders, i + 1);
        NSString *key = javaString(env, name), *text = javaString(env, value);
        if (key && text && ![skipped containsObject:key.lowercaseString]) [request addValue:text forHTTPHeaderField:key];
        (*env)->DeleteLocalRef(env, name);
        (*env)->DeleteLocalRef(env, value);
    }
    if (jbody) {
        jsize length = (*env)->GetArrayLength(env, jbody);
        NSMutableData *body = [NSMutableData dataWithLength:length];
        (*env)->GetByteArrayRegion(env, jbody, 0, length, body.mutableBytes);
        request.HTTPBody = body;
    }

    __block NSData *data;
    __block NSHTTPURLResponse *response;
    __block NSError *failure;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [nativeSession() dataTaskWithRequest:request
                                                    completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        data = d; response = (NSHTTPURLResponse *)r; failure = e;
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    dispatch_time_t limit = callTimeout > 0 ? dispatch_time(DISPATCH_TIME_NOW, (int64_t)callTimeout * NSEC_PER_MSEC) : DISPATCH_TIME_FOREVER;
    if (dispatch_semaphore_wait(done, limit) != 0) {
        [task cancel];
        throwJava(env, "java/net/SocketTimeoutException", @"call timed out");
        return NULL;
    }
    if (failure.code == NSURLErrorAppTransportSecurityRequiresSecureConnection || failure.code == NSURLErrorSecureConnectionFailed
        || failure.code == NSURLErrorServerCertificateHasBadDate || failure.code == NSURLErrorServerCertificateUntrusted
        || failure.code == NSURLErrorServerCertificateHasUnknownRoot) {
        throwJava(env, "tsunagu/net/NativeHttp$Refused", failure.localizedDescription); // OkHttp retries with its own TLS.
        return NULL;
    }
    if (failure || ![response isKindOfClass:NSHTTPURLResponse.class]) {
        const char *type = "java/io/IOException";
        if (failure.code == NSURLErrorTimedOut) type = "java/net/SocketTimeoutException";
        else if (failure.code == NSURLErrorCannotFindHost || failure.code == NSURLErrorDNSLookupFailed) type = "java/net/UnknownHostException";
        throwJava(env, type, failure.localizedDescription ?: @"no HTTP response");
        return NULL;
    }

    // allHeaderFields folds repeated Set-Cookie headers into one, so cookies are re-split here.
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    [response.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        NSString *lower = key.lowercaseString;
        if ([lower isEqualToString:@"set-cookie"] || [lower isEqualToString:@"content-encoding"] || [lower isEqualToString:@"content-length"]) return;
        [pairs addObject:key];
        [pairs addObject:[value description]];
    }];
    for (NSHTTPCookie *cookie in [NSHTTPCookie cookiesWithResponseHeaderFields:response.allHeaderFields forURL:response.URL ?: url]) {
        [pairs addObject:@"Set-Cookie"];
        [pairs addObject:setCookieLine(cookie)];
    }

    jclass stringClass = (*env)->FindClass(env, "java/lang/String");
    jobjectArray headers = (*env)->NewObjectArray(env, (jsize)pairs.count, stringClass, NULL);
    for (NSUInteger i = 0; headers && i < pairs.count; i++) {
        jstring item = (*env)->NewStringUTF(env, pairs[i].UTF8String);
        (*env)->SetObjectArrayElement(env, headers, (jsize)i, item);
        (*env)->DeleteLocalRef(env, item);
    }
    jbyteArray bytes = (*env)->NewByteArray(env, (jsize)data.length);
    if (bytes && data.length) (*env)->SetByteArrayRegion(env, bytes, 0, (jsize)data.length, data.bytes);
    jclass integerClass = (*env)->FindClass(env, "java/lang/Integer");
    jmethodID valueOf = (*env)->GetStaticMethodID(env, integerClass, "valueOf", "(I)Ljava/lang/Integer;");
    jobject status = (*env)->CallStaticObjectMethod(env, integerClass, valueOf, (jint)response.statusCode);
    jclass objectClass = (*env)->FindClass(env, "java/lang/Object");
    jobjectArray result = (*env)->NewObjectArray(env, 3, objectClass, NULL);
    if (!result || (*env)->ExceptionCheck(env)) return NULL;
    (*env)->SetObjectArrayElement(env, result, 0, status);
    (*env)->SetObjectArrayElement(env, result, 1, headers);
    (*env)->SetObjectArrayElement(env, result, 2, bytes);
    return result;
}

// Registers the native transport and turns it on; an older sandbox jar without the class keeps OkHttp sockets.
static void enableNativeHttp(JNIEnv *env) {
    jclass cls = (*env)->FindClass(env, "tsunagu/net/NativeHttp");
    if (!cls) { (*env)->ExceptionDescribe(env); (*env)->ExceptionClear(env); fprintf(stderr, "native HTTP: class missing\n"); return; }
    JNINativeMethod method = {"execute", "(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;[BII)[Ljava/lang/Object;", (void *)nativeExecute};
    if ((*env)->RegisterNatives(env, cls, &method, 1) != 0) { (*env)->ExceptionDescribe(env); (*env)->ExceptionClear(env); fprintf(stderr, "native HTTP: register failed\n"); return; }
    jclass system = (*env)->FindClass(env, "java/lang/System");
    jmethodID set = system ? (*env)->GetStaticMethodID(env, system, "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;") : NULL;
    jstring key = (*env)->NewStringUTF(env, "tsunagu.nativeHttp"), value = (*env)->NewStringUTF(env, "true");
    if (set) (*env)->CallStaticObjectMethod(env, system, set, key, value);
    if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionDescribe(env); (*env)->ExceptionClear(env); }
}

@implementation TSJavaRuntime
+ (NSString *)probeWithRuntimeHome:(NSString *)runtimeHome classPath:(NSString *)classPath
                          fixture:(NSString *)fixture error:(NSError **)error {
    JNIEnv *env=startVM(runtimeHome,classPath,[NSTemporaryDirectory() stringByAppendingPathComponent:@"moku-jvm"],error);
    if (!env) return nil;
    jclass cls=(*env)->FindClass(env,"org/moku/RuntimeProbe");
    jmethodID method=cls ? (*env)->GetStaticMethodID(env,cls,"run","(Ljava/lang/String;)Ljava/lang/String;") : NULL;
    jstring input=NULL;
    jstring output=NULL;
    if(method && !(*env)->ExceptionCheck(env)) {
        input=(*env)->NewStringUTF(env,fixture.UTF8String);
        if(input) output=(*env)->CallStaticObjectMethod(env,cls,method,input);
    }
    NSString *message=nil;
    if((*env)->ExceptionCheck(env)) {
        if(error) *error=[NSError errorWithDomain:@"Moku.JVM" code:2 userInfo:@{NSLocalizedDescriptionKey:exceptionMessage(env)}];
    } else if(output) {
        const char *chars=(*env)->GetStringUTFChars(env,output,NULL);
        if(chars) { message=[NSString stringWithUTF8String:chars]; (*env)->ReleaseStringUTFChars(env,output,chars); }
    }
    if(!message && error && !*error) *error=[NSError errorWithDomain:@"Moku.JVM" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Java probe returned no result"}];
    if(input) (*env)->DeleteLocalRef(env,input);
    if(output) (*env)->DeleteLocalRef(env,output);
    if(cls) (*env)->DeleteLocalRef(env,cls);
    (*vm)->DetachCurrentThread(vm);
    // Do not destroy/recreate the JVM. Its lifetime is the app process.
    return message;
}
+ (NSInteger)startSandboxWithRuntimeHome:(NSString *)runtimeHome classPath:(NSString *)classPath
                          dataDirectory:(NSString *)directory token:(NSString *)token error:(NSError **)error {
    JNIEnv *env=startVM(runtimeHome,classPath,[directory stringByAppendingPathComponent:@"tmp"],error);
    if (!env) return 0;
    enableNativeHttp(env);
    jclass cls=(*env)->FindClass(env,"tsunagu/Embedded");
    jmethodID method=cls ? (*env)->GetStaticMethodID(env,cls,"start","(Ljava/lang/String;Ljava/lang/String;Z)I") : NULL;
    jstring path=NULL, credential=NULL;
    jint port=0;
    if (method && !(*env)->ExceptionCheck(env)) {
        path=(*env)->NewStringUTF(env,directory.UTF8String);
        credential=(*env)->NewStringUTF(env,token.UTF8String);
        // tsunagu.Embedded.start(dataDirectory, token, novelEnabled)
        if(path && credential) port=(*env)->CallStaticIntMethod(env,cls,method,path,credential,JNI_TRUE);
    }
    if ((*env)->ExceptionCheck(env)) {
        if(error) *error=[NSError errorWithDomain:@"Moku.JVM" code:4 userInfo:@{NSLocalizedDescriptionKey:exceptionMessage(env)}];
    }
    if(path) (*env)->DeleteLocalRef(env,path);
    if(credential) (*env)->DeleteLocalRef(env,credential);
    if(cls) (*env)->DeleteLocalRef(env,cls);
    (*vm)->DetachCurrentThread(vm);
    return port;
}
+ (NSInteger)restartSandboxWithDataDirectory:(NSString *)directory token:(NSString *)token error:(NSError **)error {
    if (error) *error=nil;
    JNIEnv *env=NULL;
    if (!vm || (*vm)->AttachCurrentThread(vm,(void **)&env,NULL)!=JNI_OK || !env) {
        if(error) *error=[NSError errorWithDomain:@"Moku.JVM" code:5 userInfo:@{NSLocalizedDescriptionKey:@"The JVM is not running"}];
        return 0;
    }
    jclass cls=(*env)->FindClass(env,"tsunagu/Embedded");
    jmethodID stop=cls ? (*env)->GetStaticMethodID(env,cls,"stop","()V") : NULL;
    jmethodID start=cls ? (*env)->GetStaticMethodID(env,cls,"start","(Ljava/lang/String;Ljava/lang/String;Z)I") : NULL;
    jstring path=NULL, credential=NULL;
    jint port=0;
    if (stop && start && !(*env)->ExceptionCheck(env)) {
        (*env)->CallStaticVoidMethod(env,cls,stop);
        path=(*env)->NewStringUTF(env,directory.UTF8String);
        credential=(*env)->NewStringUTF(env,token.UTF8String);
        if(!(*env)->ExceptionCheck(env) && path && credential) port=(*env)->CallStaticIntMethod(env,cls,start,path,credential,JNI_TRUE);
    }
    if ((*env)->ExceptionCheck(env)) {
        if(error) *error=[NSError errorWithDomain:@"Moku.JVM" code:6 userInfo:@{NSLocalizedDescriptionKey:exceptionMessage(env)}];
        port=0;
    }
    if(path) (*env)->DeleteLocalRef(env,path);
    if(credential) (*env)->DeleteLocalRef(env,credential);
    if(cls) (*env)->DeleteLocalRef(env,cls);
    (*vm)->DetachCurrentThread(vm);
    return port;
}
@end
