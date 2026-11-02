import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'briefing_store.dart';
import 'briefing.dart';
import 'netflix.dart';

enum NetflixOrigin { network, cache, bundled }

class NetflixResult {
  const NetflixResult(this.feed, this.origin);
  final NetflixFeed feed;
  final NetflixOrigin origin;
}

class NetflixRepository {
  NetflixRepository(
    this.dio,
    this.store, {
    required this.endpoint,
    Future<String> Function()? bundled,
  }) : bundled =
           bundled ?? (() => rootBundle.loadString('assets/netflix-kr.json'));
  final Dio dio;
  final BriefingStore store;
  final String endpoint;
  final Future<String> Function() bundled;
  NetflixFeed? _memory;
  Future<NetflixResult>? _pending;
  Future<NetflixResult> load() =>
      _pending ??= _load().whenComplete(() => _pending = null);
  Future<NetflixResult> _load() async {
    // A cache is optional. Never substitute old news/practice questions for a chart.
    NetflixFeed? fallback = _memory;
    var fallbackOrigin = NetflixOrigin.cache;
    for (final candidate in [
      (store.read('netflix-chart-v1'), NetflixOrigin.cache),
      (await bundled().catchError((Object _) => ''), NetflixOrigin.bundled),
    ]) {
      try {
        final feed = NetflixFeed.decode(candidate.$1 ?? '');
        if (fallback == null ||
            feed.weeks.first.end.isAfter(fallback.weeks.first.end)) {
          fallback = feed;
          fallbackOrigin = candidate.$2;
        }
      } catch (_) {
        /* Keep the best valid snapshot. */
      }
    }
    try {
      final uri = safeLink(endpoint);
      if (uri == null) throw const FormatException('HTTPS required');
      final response = await dio.getUri<dynamic>(
        uri.replace(
          queryParameters: {
            '_refresh': '${DateTime.now().millisecondsSinceEpoch}',
          },
        ),
      );
      final text = response.data is String
          ? response.data as String
          : jsonEncode(response.data);
      final feed = NetflixFeed.decode(text);
      if (fallback != null &&
          feed.weeks.first.end.isBefore(fallback.weeks.first.end)) {
        return NetflixResult(fallback, fallbackOrigin);
      }
      _memory = feed;
      try {
        await store.write('netflix-chart-v1', text);
      } catch (_) {
        /* Valid live feed still works. */
      }
      return NetflixResult(feed, NetflixOrigin.network);
    } catch (_) {
      if (fallback != null) {
        _memory = fallback;
        return NetflixResult(fallback, fallbackOrigin);
      }
      rethrow;
    }
  }
}
