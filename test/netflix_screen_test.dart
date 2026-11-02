import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/main.dart';
import 'package:malmun/data/briefing_store.dart';
import 'package:malmun/data/netflix_repository.dart';
import 'package:malmun/state/briefing_provider.dart';
import 'package:malmun/state/netflix_provider.dart';
import 'netflix_fixtures.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    MemoryStore store, {
    NetflixOrigin origin = NetflixOrigin.network,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          netflixProvider.overrideWith(
            (ref) async => NetflixResult(netflixFeed(), origin),
          ),
          netflixClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 11, 20),
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
      220,
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
    'default app shows dated Korean charts, exact ranks and category search',
    (tester) async {
      await mount(tester, MemoryStore());
      expect(find.text('넷플릭스에서\n요즘 뭐 볼까?'), findsOneWidget);
      expect(find.text('2026.10.26 – 11.1'), findsOneWidget);
      await reveal(tester, find.text('작품 찾기 · 다른 주간'));
      await tester.tap(find.text('작품 찾기 · 다른 주간'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('netflix-search')));
      await tester.enterText(
        find.byKey(const ValueKey('netflix-search')),
        '작품 2',
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('한국 작품 2'));
      expect(find.text('02'), findsOneWidget);
      expect(find.text('첫 진입'), findsOneWidget);
      expect(find.text('한국 작품 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'detail saves a title, marks it watched and restores the library',
    (tester) async {
      final store = MemoryStore();
      await mount(tester, store);
      await reveal(tester, find.text('한국 작품 1'));
      await tester.tap(find.text('한국 작품 1'));
      await tester.pumpAndSettle();
      expect(find.text('한국 Netflix 1위 · 2026-11-01 종료 주간'), findsOneWidget);
      await reveal(tester, find.text('보고 싶어요'));
      await tester.tap(find.text('보고 싶어요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('봤어요'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('내 목록'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('봤어요'));
      await tester.pumpAndSettle();
      expect(find.text('한국 작품 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, store);
      await tester.tap(find.text('내 목록'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('봤어요'));
      await tester.pumpAndSettle();
      expect(find.text('한국 작품 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'offline and stale data are explicit; large text keeps controls usable',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mount(tester, MemoryStore(), origin: NetflixOrigin.bundled);
      await reveal(tester, find.textContaining('새 순위를 확인하지 못해'));
      expect(find.textContaining('최신 주간 자료가 아닐 수'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('netflix-Films')));
      await tester.tap(find.byKey(const ValueKey('netflix-Films')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('영화 1'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('legacy saved news remains accessible from the new library', (
    tester,
  ) async {
    await mount(tester, MemoryStore());
    await tester.tap(find.text('내 목록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이전 뉴스 보관함·메모'));
    await tester.pumpAndSettle();
    expect(find.text('저장한 뉴스가 없어요.'), findsOneWidget);
    expect(find.text('내가 남긴 이야기 · 0개'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
