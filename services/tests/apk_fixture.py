"""Build the fixture's binary Android manifest without an Android SDK dependency."""
import struct


def manifest(package, source):
    strings = ["manifest", "package", package, "application", "meta-data", "name", "value",
               "tachiyomi.extension.class", source, "android", "http://schemas.android.com/apk/res/android",
               "versionName", "1.0"]
    index = {value: i for i, value in enumerate(strings)}
    def words(*values):
        return struct.pack("<" + "I" * len(values), *values)
    def chunk(kind, header, body):
        return struct.pack("<HHI", kind, header, 8 + len(body)) + body
    encoded, offsets = b"", []
    for value in strings:
        data = value.encode()
        assert len(data) < 128
        offsets.append(len(encoded))
        encoded += bytes([len(value), len(data)]) + data + b"\0"
    encoded += b"\0" * (-len(encoded) % 4)
    pool = chunk(1, 28, words(len(strings), 0, 256, 28 + len(strings) * 4, 0) + words(*offsets) + encoded)
    unset = 0xffffffff
    def node(kind, body):
        return chunk(kind, 16, words(1, unset) + body)
    def tag(name, attrs=(), end=False):
        if end:
            return node(0x103, words(unset, index[name]))
        body = words(unset, index[name]) + struct.pack("<HHHHHH", 20, 20, len(attrs), 0, 0, 0)
        for namespace, key, value in attrs:
            body += words(index[namespace] if namespace else unset, index[key], index[value])
            body += struct.pack("<HBBI", 8, 0, 3, index[value])
        return node(0x102, body)
    uri = strings[10]
    namespace = words(index["android"], index[uri])
    xml = pool + node(0x100, namespace)
    xml += tag("manifest", [(None, "package", package), (uri, "versionName", "1.0")])
    xml += tag("application") + tag("meta-data", [(uri, "name", "tachiyomi.extension.class"), (uri, "value", source)])
    xml += tag("meta-data", end=True) + tag("application", end=True) + tag("manifest", end=True)
    xml += node(0x101, namespace)
    return chunk(3, 8, xml)
