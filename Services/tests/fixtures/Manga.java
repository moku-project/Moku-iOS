package org.moku.acceptance;

import eu.kanade.tachiyomi.source.online.HttpSource;
import eu.kanade.tachiyomi.source.model.*;
import java.util.*;
import okhttp3.*;

/** Real dynamically installed extension; only the upstream website is a fixture. */
public class Manga extends HttpSource implements eu.kanade.tachiyomi.source.ConfigurableSource {
    public void setupPreferenceScreen(androidx.preference.PreferenceScreen screen) {
        androidx.preference.EditTextPreference preference = new androidx.preference.EditTextPreference(screen.getContext());
        preference.setKey("fixture_option"); preference.setTitle("Fixture preference"); preference.setDefaultValue("default");
        screen.addPreference(preference);
    }
    public String getName() { return "Acceptance Manga"; }
    public String getLang() { return "en"; }
    public String getBaseUrl() { return "FIXTURE_ORIGIN"; }
    public boolean getSupportsLatest() { return true; }
    private Request request(String path) {
        return new Request.Builder().url(getBaseUrl() + path).headers(getHeaders()).build();
    }
    protected Headers.Builder headersBuilder() {
        return new Headers.Builder().add("Referer", getBaseUrl() + "/");
    }
    private SManga manga() {
        SManga m = SManga.Companion.create();
        m.setUrl("/manga/series"); m.setTitle("Acceptance Manga");
        m.setThumbnail_url(getBaseUrl() + "/cover.png");
        m.setDescription("A deterministic source description.");
        m.setAuthor("Fixture Author"); m.setArtist("Fixture Artist");
        m.setGenre("Adventure, Comedy"); m.setStatus(1);
        return m;
    }
    private static String encodeQuery(String query) {
        try { return java.net.URLEncoder.encode(query, "UTF-8"); }
        catch (java.io.UnsupportedEncodingException e) { throw new AssertionError(e); }
    }
    protected Request searchMangaRequest(int page, String query, FilterList filters) {
        return request("/manga/search?page=" + page + "&q=" + encodeQuery(query));
    }
    protected MangasPage searchMangaParse(Response response) {
        boolean first = "1".equals(response.request().url().queryParameter("page"));
        boolean empty = "missing".equals(response.request().url().queryParameter("q"));
        response.close();
        return new MangasPage(first && !empty ? Collections.singletonList(manga()) : Collections.emptyList(), first && !empty);
    }
    protected Request popularMangaRequest(int page) { return searchMangaRequest(page, "", new FilterList()); }
    protected MangasPage popularMangaParse(Response r) { return searchMangaParse(r); }
    protected Request latestUpdatesRequest(int page) { return popularMangaRequest(page); }
    protected MangasPage latestUpdatesParse(Response r) { return searchMangaParse(r); }
    protected SManga mangaDetailsParse(Response r) { r.close(); return manga(); }
    protected List<SChapter> chapterListParse(Response r) {
        r.close();
        SChapter c = SChapter.Companion.create();
        c.setUrl("/manga/chapter-1"); c.setName("Chapter 1"); c.setChapter_number(1);
        c.setDate_upload(1700000000000L); c.setScanlator("Fixture Group");
        return Collections.singletonList(c);
    }
    protected List<Page> pageListParse(Response r) {
        r.close();
        return Arrays.asList(new Page(0, "", getBaseUrl() + "/page-1.png", null),
                             new Page(1, "", getBaseUrl() + "/page-2.png", null));
    }
}
