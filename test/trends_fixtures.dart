import 'package:malmun/data/briefing.dart';
import 'fixtures.dart';

Json trendsJson({bool ready = true}) {
  final coverage = {
    ...coverageJson(),
    'source_groups': 5,
    'report_count': 5,
    'first_report_at': '2026-10-30T18:00:00Z',
    'span_hours': 33,
    'sources': [
      {
        'name': '연합뉴스',
        'group': 'yna.co.kr',
        'url': 'https://news.google.com/rss/articles/first',
        'published_at': '2026-10-30T18:00:00Z',
      },
      {
        'name': 'KBS',
        'group': 'kbs.co.kr',
        'url': 'https://news.google.com/rss/articles/b',
        'published_at': '2026-10-31T00:00:00Z',
      },
      {
        'name': '한겨레',
        'group': 'hani.co.kr',
        'url': 'https://news.google.com/rss/articles/c',
        'published_at': '2026-11-01T00:00:00Z',
      },
      {
        'name': '경향',
        'group': 'khan.co.kr',
        'url': 'https://news.google.com/rss/articles/d',
        'published_at': '2026-11-01T02:00:00Z',
      },
      (coverageJson()['sources'] as List).last,
    ],
  };
  return {
    'schema_version': 1,
    'region': 'KR',
    'updated_at': '2026-11-01T06:00:00Z',
    'tracking_started_at': ready
        ? '2026-10-30T06:00:00Z'
        : '2026-11-01T06:00:00Z',
    'snapshot_count': ready ? 9 : 1,
    'cards': [
      {
        'rank': 1,
        'topic': {...topicJson(), 'coverage': coverage},
        'source_groups': 5,
        'daily_sources': [0, 2, 3],
        'tracking_hours': ready ? 48 : 0,
        'comparison_ready': ready,
        'growth_percent': ready ? 50 : null,
        'signal': ready ? 'growing' : 'collecting',
      },
    ],
  };
}
