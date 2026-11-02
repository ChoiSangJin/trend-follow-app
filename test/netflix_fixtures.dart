import 'dart:convert';
import 'package:malmun/data/netflix.dart';

Map<String, dynamic> netflixJson({String week = '2026-11-01'}) => {
  'schema_version': 1,
  'country': 'KR',
  'source_url': netflixDataUrl,
  'chart_url': netflixChartUrl,
  'fetched_at': '2026-11-03T12:00:00Z',
  'weeks': [
    {
      'week': week,
      'previous_available': true,
      'charts': {
        for (final category in ['TV', 'Films'])
          category: [
            for (var i = 1; i <= 10; i++)
              {
                'id': '$category:show$i|season1',
                'title': '$category Show $i',
                'season': category == 'TV' ? 'Season 1' : null,
                'rank': i,
                'previous_rank': i == 1
                    ? 3
                    : i == 2
                    ? null
                    : i,
                'weeks_in_top10': i == 2 ? 1 : 3,
                'metadata': {
                  'source_url': 'https://www.netflix.com/kr/title/$i',
                  'local_title': '${category == 'TV' ? '한국 작품' : '영화'} $i',
                  'synopsis': '작품 $i의 공식 소개입니다.',
                  'kind': i.isEven ? '예능' : '드라마',
                },
              },
          ],
      },
    },
  ],
};
NetflixFeed netflixFeed() => NetflixFeed.decode(jsonEncode(netflixJson()));
