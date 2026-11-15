import Darwin
import Testing

struct EmbeddedRuntimeLinkageTests {
    @Test func jvmBootstrapSymbolsAreVisibleAcrossAppImages() throws {
        // Like the OpenJDK process handle: JNI symbols are in Moku.debug.dylib in Debug, the main executable in Release.
        let executable = try #require(dlopen(nil, RTLD_LAZY))
        defer { dlclose(executable) }

        for symbol in [
            "JNI_CreateJavaVM",
            "Java_java_lang_System_registerNatives",
            "Java_java_lang_ClassLoader_registerNatives",
        ] {
            #expect(
                dlsym(executable, symbol) != nil,
                "JVM bootstrap requires this symbol in the loaded app images: \(symbol)")
        }
    }
}
