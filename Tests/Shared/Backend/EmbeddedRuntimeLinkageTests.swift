import Darwin
import Testing

struct EmbeddedRuntimeLinkageTests {
    @Test func jvmBootstrapSymbolsAreVisibleAcrossAppImages() throws {
        // Match the iOS OpenJDK process handle: Debug stores JNI symbols in
        // Moku.debug.dylib, while Release stores them in the main executable.
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
