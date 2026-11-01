import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'briefing.dart';
import 'briefing_store.dart';

enum FeedMode { live, cached, practice }

class FeedResult {
  const FeedResult(this.briefing, this.mode);
  final Briefing briefing;
  final FeedMode mode;
}

class BriefingRepository {
  BriefingRepository(
    this.dio,
    this.store, {
    required this.endpoint,
    Future<String> Function()? practiceLoader,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : loadPractice =
           practiceLoader ??
           (() => rootBundle.loadString('assets/practice.json')),
       now = now ?? DateTime.now,
       delay = delay ?? Future<void>.delayed;
  final Dio dio;
  final BriefingStore store;
  final String endpoint;
  final Future<String> Function() loadPractice;
  final DateTime Function() now;
  final Future<void> Function(Duration) delay;
  FeedResult? _memory;
  DateTime? _fetched;
  Future<FeedResult>? _pending;

  Future<FeedResult> load({bool force = false}) {
    if (_pending != null) return _pending!;
    if (!force &&
        _memory?.mode == FeedMode.live &&
        _fetched != null &&
        now().difference(_fetched!) < const Duration(minutes: 5)) {
      return Future.value(_memory);
    }
    final pending = _load();
    _pending = pending;
    return pending.whenComplete(() => _pending = null);
  }

  Future<FeedResult> _load() async {
    try {
      final uri = safeLink(endpoint);
      if (uri == null) throw const FormatException('HTTPS required');
      dynamic body;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final response = await dio.getUri<dynamic>(
            uri.replace(
              queryParameters: {
                ...uri.queryParameters,
                '_refresh': '${now().millisecondsSinceEpoch}',
              },
            ),
            options: Options(
              headers: {'Cache-Control': 'no-cache'},
              responseType: ResponseType.json,
            ),
          );
          body = response.data;
          break;
        } on DioException catch (error) {
          final code = error.response?.statusCode;
          final transient =
              [
                DioExceptionType.connectionError,
                DioExceptionType.connectionTimeout,
                DioExceptionType.receiveTimeout,
                DioExceptionType.sendTimeout,
              ].contains(error.type) ||
              code == 429 ||
              (code != null && code >= 500);
          if (!transient || attempt == 2) rethrow;
          await delay(Duration(milliseconds: 400 * (1 << attempt)));
        }
      }
      final encoded = body is String ? body : jsonEncode(body);
      final feed = Briefing.decode(encoded);
      if (feed.practice) {
        throw const FormatException('Remote feed must be daily news');
      }
      try {
        await store.write('briefing-v3', encoded);
      } catch (_) {
        /* Keep valid news in memory. */
      }
      _fetched = now();
      return _memory = FeedResult(feed, FeedMode.live);
    } catch (_) {
      if (_memory != null && !_memory!.briefing.practice) {
        return _memory = FeedResult(_memory!.briefing, FeedMode.cached);
      }
      try {
        final saved = store.read('briefing-v3');
        if (saved != null) {
          final feed = Briefing.decode(saved);
          if (!feed.practice) {
            return _memory = FeedResult(feed, FeedMode.cached);
          }
        }
      } catch (_) {
        /* A corrupt cache must not break the app. */
      }
      final practice = Briefing.decode(await loadPractice());
      return _memory = FeedResult(practice, FeedMode.practice);
    }
  }
}
