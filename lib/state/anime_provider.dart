import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/anime_repository.dart';
import 'briefing_provider.dart';

final animeRepositoryProvider = Provider<AnimeRepository>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return AnimeRepository(
    dio,
    ref.watch(storeProvider),
    endpoint: const String.fromEnvironment(
      'ANIME_ENDPOINT',
      defaultValue:
          'https://raw.githubusercontent.com/ChoiSangJin/trend-follow-app/main/data/anime-v1.json',
    ),
  );
});
final animeProvider = FutureProvider<AnimeResult>(
  (ref) => ref.watch(animeRepositoryProvider).load(),
);
final animeClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
