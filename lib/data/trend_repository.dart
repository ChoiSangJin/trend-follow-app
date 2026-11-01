import 'dart:convert';
import 'package:dio/dio.dart';
import 'trends.dart';

class TrendRepository {
  TrendRepository(this._dio, {required this.endpoint,
    DateTime Function()? now, Future<void> Function(Duration)? delay})
    : _now = now ?? DateTime.now,
      _delay = delay ?? Future<void>.delayed;

  final Dio _dio;
  final String endpoint;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  TrendFeed? _cached;
  DateTime? _cachedAt;
  Future<TrendFeed>? _inFlight;

  Future<TrendFeed> fetch({bool force = false}) {
    if (_inFlight != null) return _inFlight!;
    if (!force && _cached != null &&
        _now().difference(_cachedAt!) < const Duration(minutes: 5)) {
      return Future.value(_cached);
    }
    final request = _load();
    _inFlight = request;
    return request.whenComplete(() => _inFlight = null);
  }

  Future<TrendFeed> _load() async {
    final base = webUri(endpoint);
    if (base == null || base.scheme != 'https') {
      throw const FormatException('데이터 주소는 HTTPS여야 합니다.');
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final uri = base.replace(queryParameters: {
          ...base.queryParameters,
          '_refresh': '${_now().millisecondsSinceEpoch}',
        });
        final response = await _dio.getUri<dynamic>(uri,
          options: Options(headers: {'Cache-Control': 'no-cache'},
            responseType: ResponseType.json));
        final dynamic body = response.data is String
          ? jsonDecode(response.data as String) : response.data;
        if (body is! Json) throw const FormatException('JSON 객체가 아닙니다.');
        final feed = TrendFeed.fromJson(body);
        _cached = feed;
        _cachedAt = _now();
        return feed;
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        final transient = error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          status == 429 || (status != null && status >= 500);
        if (!transient || attempt == 2) rethrow;
        await _delay(Duration(milliseconds: 400 * (1 << attempt)));
      }
    }
    throw StateError('Unreachable');
  }
}
