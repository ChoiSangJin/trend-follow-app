import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/trends_repository.dart';
import 'briefing_provider.dart';

final trendsRepositoryProvider = Provider<TrendsRepository>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 8),
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return TrendsRepository(
    dio,
    ref.watch(storeProvider),
    endpoint: const String.fromEnvironment(
      'TRENDS_ENDPOINT',
      defaultValue:
          'https://raw.githubusercontent.com/ChoiSangJin/trend-follow-app/main/data/trends-v1.json',
    ),
  );
});
final trendsProvider = AsyncNotifierProvider<TrendsController, TrendsResult>(
  TrendsController.new,
);

class TrendsController extends AsyncNotifier<TrendsResult> {
  bool _refreshing = false;
  @override
  Future<TrendsResult> build() => ref.watch(trendsRepositoryProvider).load();
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    state = const AsyncLoading<TrendsResult>().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(trendsRepositoryProvider).load(force: true),
    );
    _refreshing = false;
  }
}
