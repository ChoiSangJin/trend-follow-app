import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/data/briefing_repository.dart';
import 'package:malmun/data/briefing_store.dart';
import 'fixtures.dart';

class Adapter implements HttpClientAdapter {
  int calls = 0, failures = 0, failureCode = 503;
  String body = encodedFeed;
  RequestOptions? last;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    last = options;
    return ResponseBody.fromString(
      calls <= failures ? '{}' : body,
      calls <= failures ? failureCode : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Adapter adapter;
  late MemoryStore store;
  late BriefingRepository repository;
  late DateTime now;
  setUp(() {
    adapter = Adapter();
    store = MemoryStore();
    now = DateTime.utc(2026, 11, 1);
    repository = BriefingRepository(
      Dio()..httpClientAdapter = adapter,
      store,
      endpoint: 'https://example.com/briefing.json?locale=ko',
      practiceLoader: () async => encodedPractice,
      now: () => now,
      delay: (_) async {},
    );
  });
  test('live data persists and force refresh bypasses memory cache', () async {
    expect((await repository.load()).mode, FeedMode.live);
    await repository.load();
    expect(adapter.calls, 1);
    await repository.load(force: true);
    expect(adapter.calls, 2);
    expect(store.read('briefing-v4'), isNotNull);
    expect(adapter.last!.uri.queryParameters['locale'], 'ko');
    expect(adapter.last!.headers['Cache-Control'], 'no-cache');
  });
  test('transient errors retry but 404 does not', () async {
    adapter.failures = 2;
    expect((await repository.load()).mode, FeedMode.live);
    expect(adapter.calls, 3);
    adapter
      ..failureCode = 404
      ..failures = 10;
    expect((await repository.load(force: true)).mode, FeedMode.cached);
    expect(adapter.calls, 4);
  });
  test(
    'offline startup uses persistent cache with explicit cached status',
    () async {
      await store.write('briefing-v4', encodedFeed);
      adapter.failures = 10;
      final result = await repository.load();
      expect(result.mode, FeedMode.cached);
      expect(result.briefing.topics.length, 2);
      expect(adapter.calls, 3);
    },
  );
  test(
    'corrupt cache and malformed remote data fall back to labelled practice',
    () async {
      await store.write('briefing-v4', '{bad');
      adapter.body = '{"cards":true}';
      final result = await repository.load();
      expect(result.mode, FeedMode.practice);
      expect(result.briefing.practice, isTrue);
      expect(adapter.calls, 1);
    },
  );
  test('cache expires and concurrent refreshes share a request', () async {
    await repository.load();
    now = now.add(const Duration(minutes: 6));
    await Future.wait([repository.load(), repository.load(force: true)]);
    expect(adapter.calls, 2);
  });
  test('practice recovers when connection returns', () async {
    adapter.failures = 10;
    expect((await repository.load()).mode, FeedMode.practice);
    adapter.failures = 0;
    expect((await repository.load(force: true)).mode, FeedMode.live);
  });
}
