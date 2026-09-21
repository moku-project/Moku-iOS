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
        @"-Xmx512m", @"-Xss2m", @"-Djava.awt.headless=true",
        @"-Djava.net.preferIPv4Stack=true",
        @"-Dio.netty.transport.noNative=true",
        [@"-Djavax.net.ssl.trustStore=" stringByAppendingString:[runtimeHome stringByAppendingPathComponent:@"lib/security/cacerts"]]
    ];
    JavaVMOption options[9] = {0};
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
    jclass cls=(*env)->FindClass(env,"tsunagu/Embedded");
    jmethodID method=cls ? (*env)->GetStaticMethodID(env,cls,"start","(Ljava/lang/String;Ljava/lang/String;)I") : NULL;
    jstring path=NULL, credential=NULL;
    jint port=0;
    if (method && !(*env)->ExceptionCheck(env)) {
        path=(*env)->NewStringUTF(env,directory.UTF8String);
        credential=(*env)->NewStringUTF(env,token.UTF8String);
        if(path && credential) port=(*env)->CallStaticIntMethod(env,cls,method,path,credential);
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
@end
