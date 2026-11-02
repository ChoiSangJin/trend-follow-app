import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'briefing_store.dart';
import 'briefing.dart';
import 'anime.dart';

enum AnimeOrigin { network, cache, bundled }

class AnimeResult {
  const AnimeResult(this.feed, this.origin);
  final AnimeFeed feed;
  final AnimeOrigin origin;
}

class AnimeRepository {
  AnimeRepository(
    this.dio,
    this.store, {
    required this.endpoint,
    Future<String> Function()? bundled,
  }) : bundled = bundled ?? (() => rootBundle.loadString('assets/anime.json'));
  final Dio dio;
  final BriefingStore store;
  final String endpoint;
  final Future<String> Function() bundled;
  AnimeFeed? _memory;
  Future<AnimeResult>? _pending;
  Future<AnimeResult> load() =>
      _pending ??= _load().whenComplete(() => _pending = null);
  Future<AnimeResult> _load() async {
    // A cache is optional. Never substitute old news/practice questions for a chart.
    AnimeFeed? fallback = _memory;
    var fallbackOrigin = AnimeOrigin.cache;
    for (final candidate in [
      (store.read('anime-chart-v1'), AnimeOrigin.cache),
      (await bundled().catchError((Object _) => ''), AnimeOrigin.bundled),
    ]) {
      try {
        final feed = AnimeFeed.decode(candidate.$1 ?? '');
        if (fallback == null || feed.fetchedAt.isAfter(fallback.fetchedAt)) {
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
      final feed = AnimeFeed.decode(text);
      if (fallback != null && feed.fetchedAt.isBefore(fallback.fetchedAt)) {
        return AnimeResult(fallback, fallbackOrigin);
      }
      _memory = feed;
      try {
        await store.write('anime-chart-v1', text);
      } catch (_) {
        /* Valid live feed still works. */
      }
      return AnimeResult(feed, AnimeOrigin.network);
    } catch (_) {
      if (fallback != null) {
        _memory = fallback;
        return AnimeResult(fallback, fallbackOrigin);
      }
      rethrow;
    }
  }
}
