import 'package:flutter_test/flutter_test.dart';
import 'package:follow_mz/data/trends.dart';

void main() {
  test('parses all categories, optional fields and numeric string ranks', () {
    final feed = TrendFeed.fromJson({
      'updated_at': '2026-10-30T09:00:00Z',
      'categories': {
        'memes': [{'id': 'm1', 'title': '밈', 'tags': ['태그', 5], 'source_url': 'javascript:alert(1)'}],
        'hotplaces': [{'name': '성수'}],
        'keywords': [{'rank': '2', 'keyword': '둘'}, {'rank': 1, 'keyword': '하나'}],
      },
    });
    expect(feed.updatedAt!.isUtc, isTrue);
    expect(feed.memes.single.tags, ['태그']);
    expect(feed.memes.single.sourceUrl, isNull);
    expect(feed.places.single.mapQuery, '성수');
    expect(feed.places.single.age20sRatio, '정보 없음');
    expect(feed.keywords.first.keyword, '하나');
  });

  test('missing optional categories and invalid timestamp are safe', () {
    final feed = TrendFeed.fromJson({'categories': {}, 'updated_at': 'bad'});
    expect(feed.updatedAt, isNull);
    expect(feed.keywords, isEmpty);
    expect(feed.isDemo, isFalse);
  });

  test('invalid envelope and category types fail instead of appearing empty', () {
    expect(() => TrendFeed.fromJson({}), throwsFormatException);
    expect(() => TrendFeed.fromJson({'categories': {'keywords': {}}}), throwsFormatException);
  });

  test('news links open the publisher feed link instead of a search', () {
    final item = Keyword.fromJson({'keyword': '국내 소식', 'source_url': 'https://news.google.com/rss/articles/example'});
    expect(item.searchUri.host, 'news.google.com');
  });

  test('only http(s) links can launch', () {
    expect(webUri('https://example.com/article'), isNotNull);
    expect(webUri('file:///etc/passwd'), isNull);
    expect(webUri('https://user:password@example.com'), isNull);
    expect(webUri('not a url'), isNull);
  });
}
