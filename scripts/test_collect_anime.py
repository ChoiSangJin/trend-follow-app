import copy
import unittest
from datetime import datetime, timedelta, timezone

from collect_anime import build, parse_news, parse_title


class AnimeCollectorTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 11, 2, tzinfo=timezone.utc)
        self.title = dict(id=1, isAdult=False, title=dict(english='A &amp; B', romaji='Original'),
                          siteUrl='https://anilist.co/anime/1', averageScore=80, popularity=500,
                          status='RELEASING', season='FALL', seasonYear=2026, genres=['Drama'],
                          nextAiringEpisode=dict(episode=4, airingAt=int((self.now + timedelta(days=1)).timestamp())),
                          trailer=dict(site='youtube', id='abcdefghijk'))

    def payload(self):
        return {name: {'media': [copy.deepcopy(self.title)]} for name in ('trending', 'seasonal')}

    def test_interest_order_is_preserved_and_updates_deduplicate(self):
        payload = self.payload()
        other = dict(self.title, id=2, siteUrl='https://anilist.co/anime/2', averageScore=99)
        payload['trending']['media'].append(other)
        result = build(payload, self.now)
        self.assertEqual([a['id'] for a in result['trending']], [1, 2])
        self.assertEqual(result['trending'][0]['title'], 'A & B')
        self.assertEqual(len(result['updates']), 4)
        self.assertEqual(result['updates'][0]['kind'], 'airing')
        self.assertFalse(result['news_available'])

    def test_rejects_adult_wrong_identity_and_invalid_score(self):
        for patch in [dict(isAdult=True), dict(siteUrl='https://anilist.co/anime/2'),
                      dict(siteUrl='https://example.com/anime/1'), dict(averageScore=101)]:
            self.assertIsNone(parse_title(dict(self.title, **patch)))

    def test_filters_duplicates_wrong_season_and_finished_titles(self):
        payload = self.payload()
        payload['trending']['media'] *= 2
        self.assertEqual(len(build(payload, self.now)['trending']), 1)
        for section, patch in [('trending', dict(status='FINISHED')), ('seasonal', dict(season='SPRING'))]:
            payload = self.payload()
            payload[section]['media'][0].update(patch)
            with self.assertRaises(ValueError):
                build(payload, self.now)

    def test_schedule_is_bounded_and_trailer_id_is_validated(self):
        payload = self.payload()
        for section in payload.values():
            section['media'][0].update(nextAiringEpisode=dict(episode=4, airingAt=int((self.now + timedelta(days=15)).timestamp())),
                                       trailer=dict(site='youtube', id='bad/path'))
        self.assertEqual(build(payload, self.now)['updates'], [])

    def test_korean_quarter_boundary(self):
        now = datetime(2026, 12, 31, 16, tzinfo=timezone.utc)
        payload = self.payload()
        for section in payload.values():
            section['media'][0].update(season='WINTER', seasonYear=2027)
        result = build(payload, now)
        self.assertEqual((result['season_year'], result['season']), (2027, 'winter'))

    def test_news_requires_source_date_and_recent_article(self):
        def item(url, date):
            return f'<item><title>News &amp; details</title><link>{url}</link><pubDate>{date}</pubDate><description>&lt;b&gt;Text&lt;/b&gt;</description></item>'
        valid = item('http://www.animenewsnetwork.com/news/2026-11-01/story', 'Sun, 01 Nov 2026 00:00:00 GMT')
        xml = '<rss><channel>' + valid + valid + item('https://evil.com/news', 'Sun, 01 Nov 2026 00:00:00 GMT') + item('https://www.animenewsnetwork.com/old', 'Wed, 01 Jan 2020 00:00:00 GMT') + item('https://www.animenewsnetwork.com/future', 'Sun, 01 Nov 2027 00:00:00 GMT') + '</channel></rss>'
        articles = parse_news(xml, self.now)
        self.assertEqual(len(articles), 1)
        self.assertTrue(articles[0]['url'].startswith('https://'))
        self.assertEqual(articles[0]['excerpt'], 'Text')


if __name__ == '__main__':
    unittest.main()
