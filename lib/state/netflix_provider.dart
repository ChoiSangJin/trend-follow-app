import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/netflix.dart';
import '../data/netflix_repository.dart';
import '../data/briefing_store.dart';
import 'briefing_provider.dart';

final netflixRepositoryProvider = Provider<NetflixRepository>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return NetflixRepository(
    dio,
    ref.watch(storeProvider),
    endpoint: const String.fromEnvironment(
      'NETFLIX_ENDPOINT',
      defaultValue:
          'https://raw.githubusercontent.com/ChoiSangJin/trend-follow-app/main/data/netflix-kr-v1.json',
    ),
  );
});
final netflixProvider = FutureProvider<NetflixResult>(
  (ref) => ref.watch(netflixRepositoryProvider).load(),
);
final netflixClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final netflixLibraryProvider =
    StateNotifierProvider<NetflixLibrary, List<NetflixRecord>>(
      (ref) => NetflixLibrary(ref.watch(storeProvider)),
    );

class NetflixRecord {
  NetflixRecord(this.title, this.week, this.watched);
  final NetflixTitle title;
  final String week;
  final bool watched;
  Map<String, dynamic> toJson() => {
    'title': title.json,
    'category': title.category,
    'week': week,
    'watched': watched,
  };
  factory NetflixRecord.fromJson(Map<String, dynamic> json) {
    chartDate(json['week']);
    if (json['watched'] is! bool) {
      throw const FormatException('Invalid library record');
    }
    return NetflixRecord(
      NetflixTitle.fromJson(
        Map<String, dynamic>.from(json['title']),
        json['category'],
      ),
      json['week'],
      json['watched'],
    );
  }
}

class NetflixLibrary extends StateNotifier<List<NetflixRecord>> {
  NetflixLibrary(this.store) : super([]) {
    try {
      for (final raw
          in (jsonDecode(store.read('netflix-library-v1') ?? '[]') as List)
              .take(200)) {
        try {
          state = [
            ...state,
            NetflixRecord.fromJson(Map<String, dynamic>.from(raw)),
          ];
        } catch (_) {
          /* Keep other valid records. */
        }
      }
    } catch (_) {
      /* An empty collection remains usable. */
    }
  }
  final BriefingStore store;
  Future<void> _queue = Future.value();
  Future<void> set(
    NetflixTitle title,
    String week, {
    bool watched = false,
    bool remove = false,
  }) {
    final pending = _queue.then((_) async {
      final next = state.where((r) => r.title.id != title.id).toList();
      if (!remove) next.insert(0, NetflixRecord(title, week, watched));
      final limited = next.take(200).toList();
      await store.write(
        'netflix-library-v1',
        jsonEncode(limited.map((r) => r.toJson()).toList()),
      );
      if (mounted) state = limited;
    });
    _queue = pending.catchError((Object _) {});
    return pending;
  }
}
