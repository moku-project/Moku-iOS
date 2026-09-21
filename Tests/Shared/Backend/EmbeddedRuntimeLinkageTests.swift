import Darwin
import Testing

struct EmbeddedRuntimeLinkageTests {
    @Test func jvmBootstrapSymbolsAreVisibleInTheAppExecutable() throws {
        // Match OpenJDK's os::get_default_process_handle(), including RTLD_FIRST.
        // RTLD_DEFAULT would hide a regression by also searching Moku.debug.dylib.
        let executable = try #require(dlopen(nil, RTLD_FIRST))
        defer { dlclose(executable) }

        for symbol in [
            "JNI_CreateJavaVM",
            "Java_java_lang_System_registerNatives",
            "Java_java_lang_ClassLoader_registerNatives",
        ] {
            #expect(
                dlsym(executable, symbol) != nil,
                "JVM bootstrap requires this symbol in the app executable: \(symbol)")
        }
    }
}
