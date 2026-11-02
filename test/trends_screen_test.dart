import 'package:malmun/state/conversation_provider.dart';
import 'conversation_fixtures.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/data/briefing_store.dart';
import 'package:malmun/data/trends.dart';
import 'package:malmun/data/trends_repository.dart';
import 'package:malmun/main.dart';
import 'package:malmun/state/briefing_provider.dart';
import 'package:malmun/state/trends_provider.dart';
import 'home_screen_test.dart' show StubRepository;
import 'trends_fixtures.dart';

class StubTrends extends TrendsRepository {
  StubTrends({bool ready = false})
    : result = TrendsResult(
        TrendsFeed.decode(jsonEncode(trendsJson(ready: ready))),
      ),
      super(Dio(), MemoryStore(), endpoint: 'https://example.com');
  TrendsResult result;
  bool fail = false;
  int calls = 0;
  @override
  Future<TrendsResult> load({bool force = false}) async {
    calls++;
    if (fail) throw StateError('offline');
    return result;
  }
}

void main() {
  Future<void> mount(WidgetTester tester, StubTrends repository) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationPoolProvider.overrideWith(
            (ref) => ConversationPool(
              ref.watch(briefingProvider).valueOrNull?.briefing.topics ?? [],
            ),
          ),
          guideCatalogProvider.overrideWith((ref) async => realCatalog()),
          repositoryProvider.overrideWithValue(StubRepository()),
          trendsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MalmunApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('최근 3일 화제'));
    await tester.pumpAndSettle();
  }

  testWidgets('independent tab, initial history, category and growth filters', (
    tester,
  ) async {
    final repository = StubTrends();
    await mount(tester, repository);
    expect(find.text('최근 3일 한국의 화제'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trends-growth')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('보도 증가를 비교할 이력을 쌓고 있어요.'),
      150,
    );
    expect(find.textContaining('보도 증가를 비교할 이력을 쌓고 있어요.'), findsOneWidget);
    await tester.tap(find.text('보관함'));
    await tester.pumpAndSettle();
    expect(find.text('나중에 꺼내 쓸 이야기'), findsOneWidget);
    await tester.tap(find.text('오늘의 말문'));
    await tester.pumpAndSettle();
    expect(find.text('오늘은 3개만,\n대화할 만큼 이해하기'), findsOneWidget);
    expect(repository.calls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'growing trend chart, source detail, bookmark and return are safe',
    (tester) async {
      await mount(tester, StubTrends(ready: true));
      await tester.tap(find.byKey(const ValueKey('trends-growth')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('보도 출처 증가 +50%'), 160);
      expect(find.text('보도 출처 증가 +50%'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('대화 준비'), 160);
      await tester.drag(find.byType(ListView).first, const Offset(0, -140));
      await tester.pumpAndSettle();
      await tester.tap(find.text('대화 준비'));
      await tester.pumpAndSettle();
      expect(find.text('전체 1위 · 관측 출처 5그룹'), findsOneWidget);
      await tester.tap(find.text('보관하기').first);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('보관함'));
      await tester.pumpAndSettle();
      expect(find.text('전체 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed trend fetch has retry and no invented rankings', (
    tester,
  ) async {
    final repository = StubTrends()..fail = true;
    await mount(tester, repository);
    expect(find.textContaining('화제를 불러오지 못했어요.'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('최근 3일 한국의 화제'), findsOneWidget);
    expect(find.textContaining('화제를 불러오지 못했어요.'), findsNothing);
    expect(repository.calls, 2);
  });
  testWidgets('trend category filter and large text chart have no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await mount(tester, StubTrends(ready: true));
    await tester.scrollUntilVisible(find.text('24시간 구간별 보도 출처 수'), 200);
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trends-filter-스포츠')),
      -200,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('trends-filter-스포츠')));
    await tester.drag(find.byType(ListView).first, const Offset(0, 220));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trends-filter-스포츠')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('여러 출처에서 다룬 화제를 수집 중이에요.'),
      100,
    );
    expect(find.textContaining('여러 출처에서 다룬 화제를 수집 중이에요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
