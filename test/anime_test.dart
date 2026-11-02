import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/data/anime.dart';
import 'package:malmun/data/anime_repository.dart';
import 'package:malmun/data/briefing_store.dart';
import 'anime_fixtures.dart';
import 'repository_test.dart' show Adapter;

void main() {
  test(
    'bundled snapshot is verified AniList discovery and contains sourced updates',
    () {
      final feed = AnimeFeed.decode(
        File('assets/anime.json').readAsStringSync(),
      );
      expect(feed.trending, isNotEmpty);
      expect(feed.seasonal, isNotEmpty);
      expect(feed.trending.every((i) => i.airing), isTrue);
      expect(feed.news.isNotEmpty || feed.updates.isNotEmpty, isTrue);
    },
  );
  test(
    'source identity, scores, ranking, duplicates and seasonal membership are checked',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['source'] = 'MyAnimeList',
        (j) => j['rank_basis'] = 'Korean viewers',
        (j) => j['trending'][0]['score'] = 101,
        (j) => j['trending'][0]['url'] = 'https://evil.test/anime/1',
        (j) => j['trending'][0]['airing'] = false,
        (j) => j['trending'][1]['id'] = j['trending'][0]['id'],
        (j) => j['trending'][1]['position'] = j['trending'][0]['position'],
        (j) => j['seasonal'][0]['season'] = 'wrong',
        (j) => j['trending'][0]['image_url'] = 'https://evil.test/a.png',
      ]) {
        final raw = animeJson();
        mutate(raw);
        expect(() => AnimeFeed.decode(jsonEncode(raw)), throwsFormatException);
      }
    },
  );
  test('news and schedule links must be sourced and have consistent dates', () {
    final raw = animeJson();
    raw['updates'] = [
      {
        'kind': 'trailer',
        'anime_id': raw['trending'][0]['id'],
        'anime_title': 'Test',
        'title': 'Trailer',
        'url': 'https://evil.test/watch?v=abcdefghijk',
        'airing_at': null,
      },
    ];
    expect(() => AnimeFeed.decode(jsonEncode(raw)), throwsFormatException);
    raw['updates'] = [];
    raw['news'] = [
      {
        'source': 'Anime News Network',
        'title': 'Future article',
        'url': 'https://www.animenewsnetwork.com/news/a',
        'published_at': DateTime.parse(
          raw['fetched_at'],
        ).add(const Duration(days: 1)).toIso8601String(),
      },
    ];
    raw['news_available'] = true;
    expect(() => AnimeFeed.decode(jsonEncode(raw)), throwsFormatException);
    expect(
      animeFeed().stale(animeFeed().fetchedAt.add(const Duration(days: 3))),
      isTrue,
    );
  });
  test(
    'remote failure uses independent cached or bundled anime data and can recover',
    () async {
      final adapter = Adapter()..body = jsonEncode(animeJson());
      final store = MemoryStore();
      await store.write('netflix-chart-v1', 'leave Netflix cache alone');
      final repo = AnimeRepository(
        Dio()..httpClientAdapter = adapter,
        store,
        endpoint: 'https://example.com/anime.json',
        bundled: () async => jsonEncode(animeJson()),
      );
      expect((await repo.load()).origin, AnimeOrigin.network);
      adapter.failures = 100;
      expect((await repo.load()).origin, AnimeOrigin.cache);
      expect(store.read('netflix-chart-v1'), 'leave Netflix cache alone');
      final offline = AnimeRepository(
        Dio()..httpClientAdapter = adapter,
        MemoryStore(),
        endpoint: 'https://example.com/anime.json',
        bundled: () async => jsonEncode(animeJson()),
      );
      expect((await offline.load()).origin, AnimeOrigin.bundled);
      adapter.failures = 0;
      expect((await offline.load()).origin, AnimeOrigin.network);
    },
  );
  test(
    'a malformed response and missing snapshots fail explicitly instead of inventing ranks',
    () async {
      final adapter = Adapter()..body = '{}';
      final repo = AnimeRepository(
        Dio()..httpClientAdapter = adapter,
        MemoryStore(),
        endpoint: 'https://example.com/anime.json',
        bundled: () async => '{}',
      );
      await expectLater(repo.load(), throwsFormatException);
    },
  );
}
