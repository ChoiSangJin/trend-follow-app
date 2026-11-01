import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/data/briefing_store.dart';
import 'package:malmun/data/trends.dart';
import 'package:malmun/data/trends_repository.dart';
import 'repository_test.dart' show Adapter;
import 'trends_fixtures.dart';

void main() {
  test('real baseline and equal windows produce a valid 50 percent signal', () {
    final item = TrendsFeed.decode(jsonEncode(trendsJson())).items.single;
    expect(item.isGrowing, isTrue);
    expect(item.growthPercent, 50);
    expect(item.dailySources, [0, 2, 3]);
    expect(item.topic.coverage!.sources.length, 5);
  });
  test(
    'first observations cannot claim growth and empty feeds remain empty',
    () {
      final raw = trendsJson(ready: false);
      final feed = TrendsFeed.decode(jsonEncode(raw));
      expect(feed.items.single.ready, isFalse);
      expect(feed.items.single.label, '증가 비교 집계 중');
      expect(
        TrendsFeed.decode(jsonEncode({...raw, 'cards': []})).items,
        isEmpty,
      );
    },
  );
  test(
    'rejects inconsistent rates, invalid history, unsafe evidence and fake ranks',
    () {
      final good = trendsJson();
      final item = (good['cards'] as List).single as Map;
      for (final patch in [
        {'growth_percent': false},
        {'growth_percent': 500},
        {'signal': 'new'},
        {'comparison_ready': false},
        {'tracking_hours': 1},
        {
          'daily_sources': [0, 0, 3],
        },
        {'source_groups': 1},
        {'rank': 2},
        {'topic': false},
      ]) {
        expect(
          () => TrendsFeed.decode(
            jsonEncode({
              ...good,
              'cards': [
                {...item, ...patch},
              ],
            }),
          ),
          throwsFormatException,
        );
      }
      for (final patch in [
        {'region': 'US'},
        {'tracking_started_at': '2026-11-02T00:00:00Z'},
        {'snapshot_count': false},
      ]) {
        expect(
          () => TrendsFeed.decode(jsonEncode({...good, ...patch})),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'independent cache, retries, forced refresh and offline fallback preserve observations',
    () async {
      final adapter = Adapter()
        ..body = jsonEncode(trendsJson())
        ..failures = 2;
      final store = MemoryStore();
      final repository = TrendsRepository(
        Dio()..httpClientAdapter = adapter,
        store,
        endpoint: 'https://example.com/trends.json',
        delay: (_) async {},
      );
      expect((await repository.load()).cached, isFalse);
      expect(adapter.calls, 3);
      await repository.load();
      expect(adapter.calls, 3);
      expect(store.read('trends-v1'), isNotNull);
      expect(store.read('briefing-v5'), isNull);
      adapter
        ..failureCode = 404
        ..failures = 100;
      expect((await repository.load(force: true)).cached, isTrue);
      expect(adapter.calls, 4);
      final restarted = TrendsRepository(
        Dio()..httpClientAdapter = adapter,
        store,
        endpoint: 'https://example.com/trends.json',
        delay: (_) async {},
      );
      expect((await restarted.load()).feed.items.single.growthPercent, 50);
    },
  );
  test(
    'network failure without a valid cache never invents trend examples',
    () async {
      final adapter = Adapter()
        ..failureCode = 404
        ..failures = 100;
      final store = MemoryStore();
      await store.write('trends-v1', 'not json');
      final repository = TrendsRepository(
        Dio()..httpClientAdapter = adapter,
        store,
        endpoint: 'https://example.com/trends.json',
        delay: (_) async {},
      );
      await expectLater(repository.load(), throwsStateError);
      expect(adapter.calls, 1);
    },
  );
}
