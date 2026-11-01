import 'dart:convert';
import 'package:malmun/data/briefing.dart';

Json topicJson([int i = 1]) => {
  'id': 't$i',
  'category': i.isEven ? '연예' : '문화·예술',
  'title': '오늘의 대화 소재 $i',
  'summary': '확인된 기사 제목 $i',
  'why_now': '최근 보도된 소식입니다.',
  'opener': '최근에 즐겁게 본 작품이 있어요?',
  'context': '결말은 말하지 마세요.',
  'source': '한국경제',
  'source_url': 'https://news.google.com/rss/articles/$i',
  'published_at': '2026-11-01T03:00:00Z',
  'evidence': 'headline',
  'coverage': coverageJson(i),
};
Json feedJson() => {
  'schema_version': 4,
  'region': 'KR',
  'edition': 'daily',
  'updated_at': '2026-11-01T06:00:00Z',
  'cards': [topicJson(), topicJson(2)],
};
String get encodedFeed => jsonEncode(feedJson());
String get encodedPractice => jsonEncode({
  'schema_version': 4,
  'region': 'KR',
  'edition': 'practice',
  'updated_at': null,
  'cards': [
    {
      ...topicJson(),
      'published_at': null,
      'source_url': null,
      'evidence': 'practice',
      'coverage': null,
    },
  ],
});

Json coverageJson([int i = 1]) => {
  'source_groups': 2,
  'report_count': 3,
  'span_hours': 15,
  'first_report_at': '2026-10-31T12:00:00Z',
  'last_report_at': '2026-11-01T03:00:00Z',
  'first_report_url': 'https://news.google.com/rss/articles/first',
  'last_report_url': 'https://news.google.com/rss/articles/$i',
  'sources': [
    {
      'name': '연합뉴스',
      'group': 'yna.co.kr',
      'url': 'https://news.google.com/rss/articles/first',
      'published_at': '2026-10-31T12:00:00Z',
    },
    {
      'name': '한국경제',
      'group': 'hankyung.com',
      'url': 'https://news.google.com/rss/articles/$i',
      'published_at': '2026-11-01T03:00:00Z',
    },
  ],
};
