import unittest
import json
from pathlib import Path
from aggregate_trends import build_feed, parse_keywords, traffic_count

RSS = '''<rss xmlns:ht="https://trends.google.com/trending/rss"><channel>
<link>https://trends.google.com/trending?geo=KR</link>
<item><title>한국 소식</title><ht:approx_traffic>2K+</ht:approx_traffic></item>
<item><title>한국 소식</title><ht:approx_traffic>2K+</ht:approx_traffic></item>
<item><title>sl vs hk</title><ht:approx_traffic>100K+</ht:approx_traffic></item>
<item><title>해외 경기</title><ht:approx_traffic>200+</ht:approx_traffic></item>
</channel></rss>'''.encode()

class AggregationTests(unittest.TestCase):
    def test_only_filtered_korean_region_items(self):
        result = parse_keywords(RSS)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['keyword'], '한국 소식')
        self.assertEqual(result[0]['search_volume'], '2K+')

    def test_wrong_or_missing_region_is_rejected(self):
        for geo in (b'geo=US', b'geo=LK', b'geo=HK', b'hl=ko'):
            with self.assertRaises(ValueError):
                parse_keywords(RSS.replace(b'geo=KR', geo))

    def test_no_qualifying_items_fails(self):
        with self.assertRaises(ValueError):
            parse_keywords(RSS.replace('한국 소식'.encode(), b'foreign'))

    def test_traffic_units(self):
        for text, expected in [('1,000+',1000),('1.5K+',1500),('1M+',1000000),('bad',0)]:
            self.assertEqual(traffic_count(text),expected)

    def test_populated_guides_preserved(self):
        editorial=json.loads((Path(__file__).parents[1]/'data/editorial.json').read_text())
        feed=build_feed(RSS,editorial,'2026-11-01T00:00:00Z')
        self.assertEqual(feed['region'],'KR')
        for name in ('memes','hotplaces'):
            self.assertGreaterEqual(len(feed['categories'][name]),3)
        for place in editorial['hotplaces']:
            self.assertEqual(place['age_20s_ratio'],'미제공')

    def test_invalid_editorial(self):
        with self.assertRaises(ValueError):
            build_feed(RSS, {'memes':'bad'}, 'now')

if __name__ == '__main__':
    unittest.main()
