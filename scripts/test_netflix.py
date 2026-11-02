import csv
import io
import json
import unittest
from datetime import datetime, timezone
from collect_netflix import build, page_chart, title_metadata, graph_data, apply_editorial


def tsv():
    output = io.StringIO()
    writer = csv.writer(output, delimiter='\t')
    writer.writerow(['country_name', 'week', 'category', 'weekly_rank', 'show_title', 'season_title', 'cumulative_weeks_in_top_10'])
    for week in ('2026-10-25', '2026-10-18'):
        for category in ('TV', 'Films'):
            for rank in range(1, 11):
                writer.writerow(['South Korea', week, category, rank, 'Show ' + str(rank), 'Season 1' if category == 'TV' else 'N/A', 2])
    writer.writerow(['Japan', '2026-11-01', 'TV', 1, 'Not Korean chart', 'Season 1', 1])
    return output.getvalue()


def chart_html(category='SERIES', country='KR'):
    data = {}
    for rank in range(1, 11):
        data['PulseTop10ItemEntity:' + str(rank)] = {
            'top10': {'category': category, 'weekEndDate': '2026-10-25', 'weeklyRank': rank, 'cumulativeWeeksInTop10': 2},
            'top10Video': {'title': 'Film ' + str(rank), 'videoId': rank, 'parentShow': None},
            'displayVideo': {'video': {'videoId': rank}},
            'countryRanks': [{'countryId': country, 'rank': rank}],
        }
    encoded = json.dumps({'data': data}).replace('\\', '\\\\').replace("'", "\\'")
    return '<h1>South Korea</h1><script>netflix.reactContext.models.graphql = JSON.parse(\'' + encoded + '\');</script>'


class NetflixTests(unittest.TestCase):
    def test_country_and_comparison_use_exact_series_identity(self):
        feed = build(tsv(), datetime(2026, 11, 2, tzinfo=timezone.utc))
        self.assertEqual(feed['weeks'][0]['week'], '2026-10-25')
        self.assertTrue(feed['weeks'][0]['previous_available'])
        self.assertEqual(feed['weeks'][0]['charts']['TV'][0]['previous_rank'], 1)
        self.assertIsNone(feed['weeks'][0]['charts']['Films'][0]['season'])
        self.assertFalse(feed['weeks'][1]['previous_available'])

    def test_partial_or_duplicate_charts_and_changed_columns_fail(self):
        lines = tsv().splitlines()
        for text in ('wrong\tcolumns\n', '\n'.join(lines[:10] + lines[11:]), '\n'.join(lines + [lines[1]])):
            with self.assertRaises(ValueError):
                build(text, datetime(2026, 11, 2, tzinfo=timezone.utc))

    def test_public_chart_is_country_specific_and_rejects_ambiguous_ranks(self):
        week, items = page_chart(chart_html('FILM'), 'Films')
        self.assertEqual(week, '2026-10-25')
        self.assertEqual(len(items), 10)
        with self.assertRaises(ValueError): page_chart(chart_html('FILM', 'US'), 'Films')
        with self.assertRaises(ValueError): page_chart(chart_html('FILM').replace('"weeklyRank": 10', '"weeklyRank": 9'), 'Films')
        with self.assertRaises(ValueError): graph_data('<script>dangerous()</script>')

    def test_translation_is_bound_to_the_exact_season_and_original_text(self):
        feed = build(tsv(), datetime(2026, 11, 2, tzinfo=timezone.utc))
        item = feed['weeks'][0]['charts']['TV'][0]
        item['metadata'] = {'synopsis': 'Verified original', 'synopsis_language': 'en'}
        translations = {item['id']: {'source_synopsis': 'A different original', 'translation': '잘못된 번역'}}
        apply_editorial(feed, {}, translations)
        self.assertEqual(item['metadata']['synopsis'], 'Verified original')
        translations[item['id']]['source_synopsis'] = 'Verified original'
        translations[item['id']]['translation'] = '확인한 원문의 번역'
        apply_editorial(feed, {}, translations)
        self.assertEqual(item['metadata']['synopsis'], '확인한 원문의 번역')
        self.assertEqual(item['metadata']['synopsis_credit'], 'Netflix 공식 소개 · 말문 번역')

    def test_korean_title_metadata_uses_only_the_identified_public_title(self):
        node = {'@type': 'TVSeries', 'name': '작품 이름', 'description': '공식 작품 소개', 'url': 'https://www.netflix.com/kr/title/123', 'genre': '리얼리티 프로그램'}
        html = '<script type="application/ld+json">' + json.dumps(node) + '</script>'
        result = title_metadata(html, 'https://www.netflix.com/kr/title/123?locale=ko-KR')
        self.assertEqual(result['local_title'], '작품 이름')
        self.assertEqual(result['kind'], '예능')
        self.assertEqual(result['synopsis_language'], 'ko')
        with self.assertRaises(ValueError): title_metadata(html, 'https://www.netflix.com/kr/title/456')


if __name__ == '__main__':
    unittest.main()
