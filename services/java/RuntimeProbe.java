package org.moku;

import java.io.File;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;

/** Small runtime compatibility probe, not the Tsunagu extension sandbox. */
public final class RuntimeProbe {
    public static String run(String jar) throws Exception {
        String configuredTemp = System.getProperty("java.io.tmpdir");
        Path expectedParent = new File(configuredTemp).toPath().toRealPath();
        // NIO must retain the app-owned startup path despite a late property change.
        System.setProperty("java.io.tmpdir", "/var/tmp");
        Path cache = null;
        try {
            cache = Files.createTempDirectory("tsunagu_network_cache");
            if (!cache.toRealPath().getParent().equals(expectedParent)) {
                throw new IllegalStateException("NIO temp directory escaped app storage: " + cache);
            }
            Path entry = cache.resolve("probe.txt");
            Files.write(entry, new byte[] { 1, 2, 3 });
            Files.delete(entry);
        } finally {
            System.setProperty("java.io.tmpdir", configuredTemp);
            if (cache != null) Files.delete(cache);
        }
        try (URLClassLoader loader = new URLClassLoader(new URL[] { new File(jar).toURI().toURL() })) {
            Class<?> extension = Class.forName("org.moku.fixture.Extension", true, loader);
            Object value = extension.getMethod("describe").invoke(null);
            return "JVM " + System.getProperty("java.version") + "; " + value + "; app-owned NIO temp cache: PASS";
        }
    }
}
