import io.grpc.*;
import io.grpc.stub.MetadataUtils;
import sandbox.v1.Sandbox.*;
import sandbox.v1.ExtensionServiceGrpc;
import java.nio.file.*;
import java.util.concurrent.TimeUnit;
import org.json.*;

/** The client runs on the host; every source operation executes in the iOS JVM. */
public final class JvmContract {
    interface Check { void run() throws Exception; }
    static JSONArray results = new JSONArray();
    static void require(boolean ok, String message) { if (!ok) throw new AssertionError(message); }
    static void check(String name, Check test) {
        long start = System.nanoTime();
        JSONObject result = new JSONObject().put("name", "jvm." + name);
        try { test.run(); result.put("status", "PASS"); }
        catch (Throwable error) { result.put("status", "FAIL").put("detail", error.toString()); }
        result.put("seconds", (System.nanoTime() - start) / 1e9); results.put(result);
    }
    public static void main(String[] args) throws Exception {
        JSONObject connection = new JSONObject(Files.readString(Path.of(args[0])));
        Metadata headers = new Metadata();
        headers.put(Metadata.Key.of("authorization", Metadata.ASCII_STRING_MARSHALLER), "Bearer " + connection.getString("sandboxToken"));
        ManagedChannel channel = io.grpc.netty.shaded.io.grpc.netty.NettyChannelBuilder.forAddress("127.0.0.1", connection.getInt("sandboxPort")).usePlaintext().build();
        var base = ExtensionServiceGrpc.newBlockingStub(channel).withInterceptors(MetadataUtils.newAttachHeadersInterceptor(headers));
        try {
            if (args.length == 3 && args[2].equals("cookies-restored")) {
                check("browser.cookies_survive_app_restart", () -> {
                    var state = base.withDeadlineAfter(10, TimeUnit.SECONDS).browserCookies(BrowserCookiesRequest.newBuilder().setUrl("https://source.example/").build());
                    JSONObject restored = new JSONObject(state.getStateJson());
                    require(restored.getString("userAgent").equals("Acceptance Browser"), "user agent was not persisted");
                    require(restored.getJSONArray("cookies").getJSONObject(0).getString("value").equals("fixture-clearance"), "persistent cookie was lost");
                });
                Files.writeString(Path.of(args[1]), results.toString(2));
                return;
            }
            if (args.length == 4) {
                EntryRequest entry = EntryRequest.newBuilder().setExtensionId(args[2]).setSourceEntryId(args[3]).build();
                check("live.mangadex.details", () -> {
                    var details = base.withDeadlineAfter(45, TimeUnit.SECONDS).getDetails(entry);
                    require(!details.getTitle().isBlank(), "live title missing");
                    require(!details.getDescription().isBlank(), "live description missing");
                    require(details.getAuthorsCount() > 0, "live author missing");
                });
                check("live.mangadex.chapters", () -> {
                    var chapters = base.withDeadlineAfter(45, TimeUnit.SECONDS).getChapters(entry);
                    require(chapters.getChaptersCount() > 0, "no live chapters");
                    require(!chapters.getChapters(0).getSourceChapterId().isBlank(), "live chapter ID missing");
                });
                Files.writeString(Path.of(args[1]), results.toString(2));
                return;
            }
            for (String kind : new String[]{"manga", "anime", "novel"}) {
                String id = kind.equals("anime") ? "eu.kanade.tachiyomi.animeextension.en.acceptance" : "org.moku.acceptance." + kind;
                EntryRequest entry = EntryRequest.newBuilder().setExtensionId(id).setSourceEntryId("/" + kind + "/series").build();
                check(kind + ".details", () -> {
                    var d = base.withDeadlineAfter(30, TimeUnit.SECONDS).getDetails(entry);
                    require(d.getDescription().equals("A deterministic source description."), "description mismatch");
                    require(d.getAuthorsList().contains("Fixture Author"), "author missing");
                    require(d.getGenresList().contains("Adventure"), "genres missing");
                });
                check(kind + ".chapters", () -> {
                    if (kind.equals("anime")) {
                        var c = base.withDeadlineAfter(30, TimeUnit.SECONDS).getEpisodes(entry);
                        require(c.getEpisodesCount() == 1 && c.getEpisodes(0).getSourceEpisodeId().equals("/anime/episode-1"), "episodes mismatch");
                    } else {
                        var c = base.withDeadlineAfter(30, TimeUnit.SECONDS).getChapters(entry);
                        require(c.getChaptersCount() == 1 && c.getChapters(0).getSourceChapterId().equals("/" + kind + "/chapter-1"), "chapters mismatch");
                    }
                });
            }
            check("manga.pages_and_image_bytes", () -> {
                var pages = base.withDeadlineAfter(30, TimeUnit.SECONDS).getPages(ChapterRequest.newBuilder().setExtensionId("org.moku.acceptance.manga").setSourceEntryId("/manga/series").setSourceChapterId("/manga/chapter-1").build());
                require(pages.getPageUrlsCount() == 2, "expected two ordered pages");
                for (int i = 0; i < 2; i++) {
                    require(pages.getPageUrls(i).endsWith("/page-" + (i + 1) + ".png"), "page ordering");
                    var image = base.withDeadlineAfter(30, TimeUnit.SECONDS).getImageBytes(ImageRequest.newBuilder().setExtensionId("org.moku.acceptance.manga").setImageUrl(pages.getPageUrls(i)).build());
                    byte[] bytes = image.getData().toByteArray();
                    require(image.getContentType().startsWith("image/png") && bytes.length > 30 && bytes[0] == (byte)137 && bytes[1] == 80, "expected PNG bytes, not just an image URL");
                    require(java.util.Arrays.equals(bytes, Files.readAllBytes(Path.of(args[1]).getParent().resolve("page-" + (i + 1) + ".png"))), "image bytes or page order differ from fixture");
                }
            });
            check("anime.stream_sources_and_subtitles", () -> {
                var stream = base.withDeadlineAfter(30, TimeUnit.SECONDS).getVideoStream(EpisodeRequest.newBuilder().setExtensionId("eu.kanade.tachiyomi.animeextension.en.acceptance").setSourceEntryId("/anime/series").setSourceEpisodeId("/anime/episode-1").build());
                require(stream.getSourcesCount() == 3, "MP4 and HLS sources missing");
                require(stream.getSources(0).getHeadersMap().containsKey("Referer"), "source headers lost");
                require(stream.getSources(0).getSubtitlesCount() == 1, "subtitles missing");
            });
            check("browser.cookie_transfer_and_domain_isolation", () -> {
                String state = new JSONObject().put("userAgent","Acceptance Browser").put("cookies",new JSONArray().put(new JSONObject()
                    .put("name","cf_clearance").put("value","fixture-clearance").put("domain","source.example").put("path","/")
                    .put("hostOnly",true).put("secure",true).put("httpOnly",true).put("persistent",true).put("expiresAt",System.currentTimeMillis()+600000))).toString();
                var saved = base.withDeadlineAfter(10, TimeUnit.SECONDS).browserCookies(BrowserCookiesRequest.newBuilder().setUrl("https://source.example/").setApply(true).setStateJson(state).build());
                JSONObject returned = new JSONObject(saved.getStateJson());
                require(returned.getString("userAgent").equals("Acceptance Browser"), "browser user agent was lost");
                require(returned.getJSONArray("cookies").getJSONObject(0).getString("path").equals("/"), "cookie wire defaults missing");
                var unrelated = base.withDeadlineAfter(10,TimeUnit.SECONDS).browserCookies(BrowserCookiesRequest.newBuilder().setUrl("https://evilsource.example/").build());
                require(new JSONObject(unrelated.getStateJson()).getJSONArray("cookies").isEmpty(), "cookie leaked to unrelated domain");
            });
            check("novel.text", () -> {
                var text = base.withDeadlineAfter(30, TimeUnit.SECONDS).getChapterText(ChapterRequest.newBuilder().setExtensionId("org.moku.acceptance.novel").setSourceEntryId("/novel/series").setSourceChapterId("/novel/chapter-1").build());
                require(text.getContent().contains("Acceptance novel text."), "novel text missing");
            });
        } finally { channel.shutdownNow().awaitTermination(5, TimeUnit.SECONDS); }
        Files.writeString(Path.of(args[1]), results.toString(2));
    }
}
