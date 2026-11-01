import unittest
from aggregate_trends import build_feed, parse_keywords

RSS = b'''<rss xmlns:ht="https://trends.google.com/trending/rss"><channel>
<item><title>A &amp; B</title><ht:approx_traffic>100K+</ht:approx_traffic></item>
<item><title>A &amp; B</title></item><item><title>C</title></item>
<item><title> </title></item></channel></rss>'''


class AggregationTests(unittest.TestCase):
    def test_ranking_duplicates_and_optional_traffic(self):
        result = parse_keywords(RSS)
        self.assertEqual([r['rank'] for r in result], [1, 2])
        self.assertEqual(result[0]['keyword'], 'A & B')
        self.assertEqual(result[0]['search_volume'], '100K+')
        self.assertEqual(result[1]['search_volume'], '집계 중')

    def test_empty_feed_is_failure(self):
        with self.assertRaises(ValueError):
            parse_keywords(b'<rss><channel/></rss>')

    def test_live_feed_preserves_editorial_and_timestamp(self):
        meme = {'id': 'm1', 'title': 'Editorial'}
        feed = build_feed(RSS, {'memes': [meme]}, '2026-11-01T00:00:00Z')
        self.assertFalse(feed['is_demo'])
        self.assertEqual(feed['categories']['memes'], [meme])
        self.assertEqual(feed['categories']['hotplaces'], [])
        self.assertEqual(feed['updated_at'], '2026-11-01T00:00:00Z')

    def test_invalid_editorial_fails(self):
        with self.assertRaises(ValueError):
            build_feed(RSS, {'memes': 'invalid'}, 'now')


if __name__ == '__main__':
    unittest.main()
