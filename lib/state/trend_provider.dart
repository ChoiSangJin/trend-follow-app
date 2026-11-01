import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/trend_repository.dart';
import '../data/trends.dart';

const trendEndpoint = String.fromEnvironment('TREND_ENDPOINT', defaultValue:
  'https://raw.githubusercontent.com/ChoiSangJin/trend-follow-app/main/data/trends.json');

final repositoryProvider = Provider<TrendRepository>((ref) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12), sendTimeout: const Duration(seconds: 8)));
  ref.onDispose(() => dio.close(force: true));
  return TrendRepository(dio, endpoint: trendEndpoint);
});

final trendProvider = AsyncNotifierProvider<TrendController, TrendFeed>(TrendController.new);

class TrendController extends AsyncNotifier<TrendFeed> {
  Future<void>? _refreshing;
  @override
  Future<TrendFeed> build() => ref.watch(repositoryProvider).fetch();

  Future<void> refresh() {
    if (_refreshing != null) return _refreshing!;
    final operation = _refresh();
    _refreshing = operation;
    return operation.whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final previous = state.valueOrNull;
    state = const AsyncLoading<TrendFeed>().copyWithPrevious(state);
    final result = await AsyncValue.guard(() => ref.read(repositoryProvider).fetch(force: true));
    // Retain the last successful feed when a manual refresh fails.
    state = result.hasError && previous != null
      ? result.copyWithPrevious(AsyncData(previous)) : result;
  }
}
