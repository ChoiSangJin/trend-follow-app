import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/data/briefing_store.dart';
import 'package:malmun/data/netflix.dart';
import 'package:malmun/data/netflix_repository.dart';
import 'package:malmun/state/netflix_provider.dart';
import 'netflix_fixtures.dart';
import 'repository_test.dart' show Adapter;

class FailingNetflixStore extends MemoryStore {
  bool fail = true;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('disk full');
    await super.write(key, value);
  }
}

void main() {
  test(
    'bundled offline snapshot contains complete official country charts',
    () {
      final feed = NetflixFeed.decode(
        File('assets/netflix-kr.json').readAsStringSync(),
      );
      expect(feed.weeks.first.charts['TV']!.length, 10);
      expect(feed.weeks.first.charts['Films']!.length, 10);
    },
  );
  test(
    'country, ranks, duplicate titles, dates and source identity are validated',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['country'] = 'US',
        (j) => j['chart_url'] = 'https://example.com',
        (j) => j['weeks'][0]['charts']['TV'].removeLast(),
        (j) => j['weeks'][0]['charts']['TV'][1]['rank'] = 1,
        (j) => j['weeks'][0]['charts']['TV'][1]['id'] =
            j['weeks'][0]['charts']['TV'][0]['id'],
        (j) => j['weeks'][0]['week'] = '2026-11-02',
        (j) => j['weeks'][0]['charts']['TV'][0]['previous_rank'] = 0,
        (j) => j['weeks'][0]['charts']['TV'][0]['metadata']['source_url'] =
            'https://evil.test',
      ]) {
        final raw = netflixJson();
        mutate(raw);
        expect(
          () => NetflixFeed.decode(jsonEncode(raw)),
          throwsFormatException,
        );
      }
      expect(() => chartDate('2026-02-31'), throwsFormatException);
    },
  );
  test(
    'new entries, reentries and movement never imply a Korean view count',
    () {
      final items = netflixFeed().weeks.first.charts['TV']!;
      expect(items[0].movement(true), '↑ 2');
      expect(items[1].movement(true), '첫 진입');
      final raw = Map<String, dynamic>.from(items[1].json)
        ..['weeks_in_top10'] = 4;
      expect(NetflixTitle.fromJson(raw, 'TV').movement(true), '재진입');
      expect(items[1].movement(false), '이전 주 비교 자료 없음');
      expect(netflixFeed().stale(DateTime.utc(2026, 11, 17)), isTrue);
    },
  );
  test(
    'network success, failure and malformed responses retain a dated chart',
    () async {
      final adapter = Adapter()..body = jsonEncode(netflixJson());
      final store = MemoryStore();
      final repo = NetflixRepository(
        Dio()..httpClientAdapter = adapter,
        store,
        endpoint: 'https://example.com/feed.json',
        bundled: () async => jsonEncode(netflixJson(week: '2026-10-25')),
      );
      expect((await repo.load()).origin, NetflixOrigin.network);
      adapter.failures = 100;
      final fallback = await repo.load();
      expect(fallback.origin, NetflixOrigin.cache);
      expect(fallback.feed.weeks.first.key, '2026-11-01');
      final offline = NetflixRepository(
        Dio()..httpClientAdapter = adapter,
        MemoryStore(),
        endpoint: 'https://example.com/feed.json',
        bundled: () async => jsonEncode(netflixJson()),
      );
      expect((await offline.load()).origin, NetflixOrigin.bundled);
    },
  );
  test('an older remote snapshot cannot replace a newer saved chart', () async {
    final adapter = Adapter()
      ..body = jsonEncode(netflixJson(week: '2026-10-25'));
    final store = MemoryStore();
    await store.write('netflix-chart-v1', jsonEncode(netflixJson()));
    final repo = NetflixRepository(
      Dio()..httpClientAdapter = adapter,
      store,
      endpoint: 'https://example.com/feed.json',
    );
    expect((await repo.load()).feed.weeks.first.key, '2026-11-01');
  });
  test('a newer bundle wins over an older disk cache while offline', () async {
    final adapter = Adapter()..failures = 100;
    final store = MemoryStore();
    await store.write(
      'netflix-chart-v1',
      jsonEncode(netflixJson(week: '2026-10-25')),
    );
    final repo = NetflixRepository(
      Dio()..httpClientAdapter = adapter,
      store,
      endpoint: 'https://example.com/feed.json',
      bundled: () async => jsonEncode(netflixJson()),
    );
    final result = await repo.load();
    expect(result.feed.weeks.first.key, '2026-11-01');
    expect(result.origin, NetflixOrigin.bundled);
  });
  test(
    'watchlist updates persist in order, survive restart and leave legacy records alone',
    () async {
      final store = MemoryStore();
      await store.write('saved-topics-v2', 'legacy news');
      await store.write('conversation-learning-v1', 'legacy notes');
      final lib = NetflixLibrary(store);
      final items = netflixFeed().weeks.first.charts['TV']!;
      await Future.wait([
        lib.set(items[0], '2026-11-01'),
        lib.set(items[1], '2026-11-01'),
        lib.set(items[0], '2026-11-01', watched: true),
      ]);
      final restored = NetflixLibrary(store);
      expect(restored.state.length, 2);
      expect(restored.state.first.watched, isTrue);
      expect(store.read('saved-topics-v2'), 'legacy news');
      expect(store.read('conversation-learning-v1'), 'legacy notes');
      lib.dispose();
      restored.dispose();
    },
  );
  test(
    'failed library writes keep the previous state and allow later saves',
    () async {
      final store = FailingNetflixStore();
      final lib = NetflixLibrary(store);
      final item = netflixFeed().weeks.first.charts['TV']!.first;
      await expectLater(lib.set(item, '2026-11-01'), throwsStateError);
      expect(lib.state, isEmpty);
      store.fail = false;
      await lib.set(item, '2026-11-01');
      expect(lib.state.single.title.id, item.id);
      lib.dispose();
    },
  );
}
