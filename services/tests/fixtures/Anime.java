package org.moku.acceptance;

import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource;
import eu.kanade.tachiyomi.animesource.model.*;
import java.util.*;
import okhttp3.*;

public final class Anime extends AnimeHttpSource {
    public String getName() { return "Acceptance Anime"; }
    public String getLang() { return "en"; }
    public String getBaseUrl() { return "FIXTURE_ORIGIN"; }
    public boolean getSupportsLatest() { return true; }
    protected Headers.Builder headersBuilder() {
        return new Headers.Builder().add("Referer", getBaseUrl() + "/");
    }
    private SAnime anime() {
        SAnime a = SAnime.Companion.create();
        a.setUrl("/anime/series"); a.setTitle("Acceptance Anime");
        a.setThumbnail_url(getBaseUrl() + "/cover.png");
        a.setDescription("A deterministic source description.");
        a.setAuthor("Fixture Author"); a.setGenre("Adventure, Comedy"); a.setStatus(1);
        return a;
    }
    protected Request searchAnimeRequest(int page, String query, AnimeFilterList filters) {
        return new Request.Builder().url(getBaseUrl() + "/anime/search?page=" + page).headers(getHeaders()).build();
    }
    protected AnimesPage searchAnimeParse(Response r) { r.close(); return new AnimesPage(Collections.singletonList(anime()), false); }
    protected Request popularAnimeRequest(int page) { return searchAnimeRequest(page, "", new AnimeFilterList()); }
    protected AnimesPage popularAnimeParse(Response r) { return searchAnimeParse(r); }
    protected Request latestUpdatesRequest(int page) { return popularAnimeRequest(page); }
    protected AnimesPage latestUpdatesParse(Response r) { return searchAnimeParse(r); }
    protected SAnime animeDetailsParse(Response r) { r.close(); return anime(); }
    protected List<SEpisode> episodeListParse(Response r) {
        r.close();
        SEpisode e = SEpisode.Companion.create();
        e.setUrl("/anime/episode-1"); e.setName("Episode 1"); e.setEpisode_number(1);
        e.setDate_upload(1700000000000L);
        return Collections.singletonList(e);
    }
    protected List<Video> videoListParse(Response r) {
        r.close();
        List<Track> subtitles = Collections.singletonList(new Track(getBaseUrl() + "/subtitles.vtt", "English"));
        return Arrays.asList(
            new Video(getBaseUrl() + "/video.mp4", "360p MP4", getBaseUrl() + "/video.mp4", getHeaders(), subtitles, Collections.emptyList()),
            new Video(getBaseUrl() + "/master.m3u8", "360p HLS", getBaseUrl() + "/master.m3u8", getHeaders(), subtitles, Collections.emptyList()),
            new Video(getBaseUrl() + "/video.mpd", "360p DASH", getBaseUrl() + "/video.mpd", getHeaders(), subtitles, Collections.emptyList()));
    }
}
