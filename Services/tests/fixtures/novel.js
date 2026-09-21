module.exports.default = {
  id: 'org.moku.acceptance.novel', name: 'Acceptance Novel',
  site: 'FIXTURE_ORIGIN', lang: 'en', version: '1.0',
  async searchNovels(query, page) { return page === 1 ? [{ name: this.name, path: '/novel/series', cover: this.site + '/cover.png' }] : []; },
  async popularNovels(page) { return this.searchNovels('', page); },
  async parseNovel(path) {
    return { name: this.name, path, cover: this.site + '/cover.png',
      summary: 'A deterministic source description.', author: 'Fixture Author',
      genres: 'Adventure, Comedy', status: 'Ongoing',
      chapters: [{ name: 'Chapter 1', path: '/novel/chapter-1', chapterNumber: 1 }] };
  },
  async parseChapter(path) {
    const response = await require('@libs/fetch').fetchApi(this.site + '/novel-text.html', { headers: { Referer: this.site + '/' } });
    if (!response.ok) throw new Error('Novel HTTP ' + response.status);
    return response.text();
  }
};
