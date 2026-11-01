import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/briefing.dart';
import '../data/briefing_repository.dart';
import '../data/briefing_store.dart';

final storeProvider = Provider<BriefingStore>((ref) => MemoryStore());
final repositoryProvider = Provider<BriefingRepository>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 8),
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return BriefingRepository(
    dio,
    ref.watch(storeProvider),
    endpoint: const String.fromEnvironment(
      'BRIEFING_ENDPOINT',
      defaultValue:
          'https://raw.githubusercontent.com/ChoiSangJin/trend-follow-app/main/data/briefing-v5.json',
    ),
  );
});
final briefingProvider = AsyncNotifierProvider<BriefingController, FeedResult>(
  BriefingController.new,
);

class BriefingController extends AsyncNotifier<FeedResult> {
  bool _refreshing = false;
  @override
  Future<FeedResult> build() => ref.watch(repositoryProvider).load();
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    state = const AsyncLoading<FeedResult>().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(repositoryProvider).load(force: true),
    );
    _refreshing = false;
  }
}

final savedProvider = StateNotifierProvider<SavedTopics, List<Topic>>(
  (ref) => SavedTopics(ref.watch(storeProvider)),
);

class SavedTopics extends StateNotifier<List<Topic>> {
  SavedTopics(this.store) : super([]) {
    try {
      final raw = jsonDecode(store.read('saved-topics-v2') ?? '[]');
      if (raw is List) {
        state = raw
            .take(100)
            .map((x) => Topic.fromJson(Map<String, dynamic>.from(x)))
            .toList();
      }
    } catch (_) {
      state = [];
    }
  }
  final BriefingStore store;
  Future<void> toggle(Topic topic) async {
    final previous = state;
    state = state.any((x) => x.id == topic.id)
        ? state.where((x) => x.id != topic.id).toList()
        : [topic, ...state].take(100).toList();
    try {
      await store.write(
        'saved-topics-v2',
        jsonEncode(state.map((x) => x.toJson()).toList()),
      );
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}
