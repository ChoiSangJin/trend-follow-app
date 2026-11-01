import json
import unittest
from datetime import datetime, timezone
from pathlib import Path
from collect_briefing import candidates, build_briefing, TOPICS

NOW = datetime(2026, 11, 1, 6, tzinfo=timezone.utc)


def rss(title='새로운 영화가 오늘 극장에서 개봉합니다', date='Sun, 01 Nov 2026 03:00:00 GMT', language='ko', edition='KR:ko', url='https://news.google.com/rss/articles/example'):
    return f'''<rss><channel><language>{language}</language>
<link>https://news.google.com/search?ceid={edition}</link>
<item><title>{title} - 문화신문</title><link>{url}</link>
<source url="https://www.yna.co.kr">문화신문</source><pubDate>{date}</pubDate></item></channel></rss>'''.encode()


class BriefingTests(unittest.TestCase):
    def parse(self, payload):
        return candidates(payload, '문화', '질문', '맥락', NOW)

    def test_keeps_facts_and_dated_source_without_invented_summary(self):
        topic = self.parse(rss())[0]
        self.assertEqual(topic['title'], topic['summary'])
        self.assertEqual(topic['evidence'], 'headline')
        self.assertEqual(topic['source'], '문화신문')
        self.assertIn(topic['title'], topic['opener'])
        self.assertEqual(topic['published_at'], '2026-11-01T03:00:00Z')

    def test_wrong_edition_or_language_rejected(self):
        for payload in (rss(edition='US:en'), rss(language='en'), rss(edition='HK:zh')):
            with self.assertRaises(ValueError):
                self.parse(payload)

    def test_unknown_publishers_are_not_used(self):
        self.assertEqual(self.parse(rss().replace(b'https://www.yna.co.kr', b'https://unverified.example')), [])

    def test_old_future_or_missing_date_rejected(self):
        for date in ('Wed, 01 Oct 2025 00:00:00 GMT', 'Mon, 02 Nov 2026 00:00:00 GMT', ''):
            self.assertEqual(self.parse(rss(date=date)), [])

    def test_sensitive_topics_and_unsafe_sources_rejected(self):
        for title in ('대통령의 새로운 발표와 국회 논란', '유명 인사 사망 사건 소식'):
            self.assertEqual(self.parse(rss(title=title)), [])
        for url in ('javascript:alert(1)', 'https://example.com/story', 'http://news.google.com/story'):
            self.assertEqual(self.parse(rss(url=url)), [])

    def test_one_story_per_category_and_deduplication(self):
        feed = build_briefing([rss()] * 5, NOW)
        self.assertEqual(len(feed['cards']), 1)
        self.assertEqual(feed['region'], 'KR')
        self.assertEqual(feed['edition'], 'daily')

    def test_five_distinct_topics_and_partial_feed_without_padding(self):
        titles = ['영화관에서 만나는 새 한국 작품', '신메뉴로 등장한 제철 과일 디저트',
                  '한강공원에서 열리는 주말 산책 행사', '우주 탐사선이 보내온 화성 관측 소식', '프로농구 팀들의 새로운 시즌 경기']
        feeds = [rss(title=title, url=f'https://news.google.com/rss/articles/{i}') for i, title in enumerate(titles)]
        self.assertEqual(len(build_briefing(feeds, NOW)['cards']), 5)
        feeds[0] = None
        self.assertEqual(len(build_briefing(feeds, NOW)['cards']), 4)

    def test_no_valid_news_does_not_produce_a_fake_daily_edition(self):
        with self.assertRaises(ValueError):
            build_briefing([None] * len(TOPICS), NOW)

    def test_packaged_practice_is_explicitly_not_news(self):
        feed = json.loads((Path(__file__).parents[1] / 'assets/practice.json').read_text())
        self.assertEqual(feed['edition'], 'practice')
        self.assertEqual(len(feed['cards']), 5)
        for card in feed['cards']:
            self.assertIsNone(card['published_at'])
            self.assertEqual(card['evidence'], 'practice')


if __name__ == '__main__':
    unittest.main()
