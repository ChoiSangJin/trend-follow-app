import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/main.dart';
import 'package:malmun/data/anime_repository.dart';
import 'package:malmun/data/netflix_repository.dart';
import 'package:malmun/data/briefing_store.dart';
import 'package:malmun/state/anime_provider.dart';
import 'package:malmun/state/netflix_provider.dart';
import 'package:malmun/state/briefing_provider.dart';
import 'anime_fixtures.dart';
import 'netflix_fixtures.dart';

void main() {
  int calls = 0;
  Future<void> mount(
    WidgetTester tester, {
    bool fail = false,
    bool offline = false,
  }) async {
    calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(MemoryStore()),
          netflixProvider.overrideWith(
            (ref) async => NetflixResult(netflixFeed(), NetflixOrigin.network),
          ),
          animeProvider.overrideWith((ref) async {
            calls++;
            if (fail) throw StateError('offline');
            return AnimeResult(
              animeFeed(),
              offline ? AnimeOrigin.bundled : AnimeOrigin.network,
            );
          }),
          animeClockProvider.overrideWithValue(
            () => animeFeed().fetchedAt.add(const Duration(days: 3)),
          ),
        ],
        child: const MalmunApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Netflix is default and anime loads only when its header tab is selected',
    (tester) async {
      await mount(tester);
      expect(find.text('넷플릭스에서\n요즘 뭐 볼까?'), findsOneWidget);
      expect(calls, 0);
      await tester.tap(find.byKey(const ValueKey('source-anime')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('애니, 지금 뭐 볼까?'), findsOneWidget);
      expect(find.text('넷플릭스에서\n요즘 뭐 볼까?'), findsNothing);
      await reveal(tester, find.textContaining('1. Test Anime 1'));
      await tester.tap(find.byKey(const ValueKey('source-netflix')));
      await tester.pumpAndSettle();
      expect(find.text('넷플릭스에서\n요즘 뭐 볼까?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('source-anime')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'seasonal titles, news and anime detail remain inside the anime context',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('source-anime')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('anime-section-1')));
      await tester.tap(find.byKey(const ValueKey('anime-section-1')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Season Anime 1'));
      await tester.tap(find.text('Season Anime 1'));
      await tester.pumpAndSettle();
      expect(find.text('애니 작품 정보'), findsOneWidget);
      expect(find.textContaining('AniList 이용자 평점'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, 1000));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('anime-section-2')));
      await tester.tap(find.byKey(const ValueKey('anime-section-2')));
      await tester.pumpAndSettle();
      expect(find.text('방영 예정·예고편과 최근 기사 · 출처별 표시'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('anime failure does not block Netflix and offers retry', (
    tester,
  ) async {
    await mount(tester, fail: true);
    await tester.tap(find.byKey(const ValueKey('source-anime')));
    await tester.pumpAndSettle();
    expect(find.textContaining('애니 정보를 불러오지 못했어요'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.tap(find.byKey(const ValueKey('source-netflix')));
    await tester.pumpAndSettle();
    expect(find.text('넷플릭스에서\n요즘 뭐 볼까?'), findsOneWidget);
  });
  testWidgets(
    'narrow large-text anime header, offline notices and controls are usable',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mount(tester, offline: true);
      await tester.tap(find.byKey(const ValueKey('source-anime')));
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('새 정보를 받지 못해'));
      expect(find.textContaining('48시간 이상 지난 자료'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('anime-section-1')));
      await tester.tap(find.byKey(const ValueKey('anime-section-1')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Season Anime 1'));
      expect(tester.takeException(), isNull);
    },
  );
}
