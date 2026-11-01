import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:follow_mz/data/trend_repository.dart';

class FakeAdapter implements HttpClientAdapter {
  int calls = 0;
  int failures = 0;
  int status = 503;
  String body = '{"categories":{"keywords":[{"rank":1,"keyword":"성수"}]}}';
  RequestOptions? lastRequest;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls++;
    lastRequest = options;
    return ResponseBody.fromString(calls <= failures ? '{}' : body,
      calls <= failures ? status : 200,
      headers: {Headers.contentTypeHeader: ['application/json']});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeAdapter adapter;
  late TrendRepository repository;
  late DateTime now;
  setUp(() {
    adapter = FakeAdapter();
    now = DateTime.utc(2026, 11, 1);
    repository = TrendRepository(Dio()..httpClientAdapter = adapter,
      endpoint: 'https://example.com/trends.json?locale=ko', now: () => now,
      delay: (_) async {});
  });

  test('caches requests, expires after five minutes and force bypasses cache', () async {
    await repository.fetch();
    await repository.fetch();
    expect(adapter.calls, 1);
    now = now.add(const Duration(minutes: 6));
    await repository.fetch();
    expect(adapter.calls, 2);
    await repository.fetch(force: true);
    expect(adapter.calls, 3);
    expect(adapter.lastRequest!.headers['Cache-Control'], 'no-cache');
    expect(adapter.lastRequest!.uri.queryParameters['locale'], 'ko');
    expect(adapter.lastRequest!.uri.queryParameters['_refresh'], '${now.millisecondsSinceEpoch}');
  });

  test('transient server failures retry and then succeed', () async {
    adapter.failures = 2;
    expect((await repository.fetch()).keywords.single.keyword, '성수');
    expect(adapter.calls, 3);
  });

  test('persistent server failures stop after three attempts', () async {
    adapter.failures = 10;
    await expectLater(repository.fetch(), throwsA(isA<DioException>()));
    expect(adapter.calls, 3);
  });

  test('404 is not retried', () async {
    adapter..failures = 10..status = 404;
    await expectLater(repository.fetch(), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
  });

  test('bad JSON schema fails without retries', () async {
    adapter.body = '{"categories":42}';
    await expectLater(repository.fetch(), throwsFormatException);
    expect(adapter.calls, 1);
  });

  test('concurrent requests share one network call', () async {
    await Future.wait([repository.fetch(), repository.fetch(force: true)]);
    expect(adapter.calls, 1);
  });
}
