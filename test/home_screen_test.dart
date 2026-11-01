import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/data/briefing.dart';
import 'package:malmun/data/briefing_repository.dart';
import 'package:malmun/data/briefing_store.dart';
import 'package:malmun/main.dart';
import 'package:malmun/state/briefing_provider.dart';
import 'fixtures.dart';

class StubRepository extends BriefingRepository {
  StubRepository()
    : super(Dio(), MemoryStore(), endpoint: 'https://example.com');
  FeedResult result = FeedResult(Briefing.fromJson(feedJson()), FeedMode.live);
  int calls = 0;
  @override
  Future<FeedResult> load({bool force = false}) async {
    calls++;
    return result;
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    StubRepository repository, {
    BriefingStore? store,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          storeProvider.overrideWithValue(store ?? MemoryStore()),
        ],
        child: const MalmunApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'daily cards lead to dated source, context and conversation question',
    (tester) async {
      await mount(tester, StubRepository());
      expect(find.text(' 말문'), findsNothing);
      expect(find.text('말문'), findsOneWidget);
      await tester.ensureVisible(find.text('대화 준비').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('대화 준비').first);
      await tester.pumpAndSettle();
      expect(find.text('왜 지금 이야기해?'), findsOneWidget);
      expect(find.text('이렇게 말 걸어봐'), findsOneWidget);
      expect(find.textContaining('본문을 읽은 요약이 아니며'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('출처 기사 읽기'), 250);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'detail, back, category and saved transitions never mix bool and scroll offsets',
    (tester) async {
      await mount(tester, StubRepository());
      await tester.ensureVisible(find.text('보관하기').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('보관하기').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('대화 준비').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('대화 준비').first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('filter-연예')),
        -250,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-연예')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('filter-연예')))
            .selected,
        isTrue,
      );
      expect(find.text('오늘의 대화 소재 1'), findsNothing);
      expect(find.text('오늘의 대화 소재 2'), findsOneWidget);
      await tester.tap(find.text('보관함'));
      await tester.pumpAndSettle();
      expect(find.text('오늘의 대화 소재 1'), findsOneWidget);
      await tester.tap(find.text('오늘의 말문'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'all ten cards are available with two per field and matching filter count',
    (tester) async {
      final repository = StubRepository()
        ..result = FeedResult(
          Briefing.fromJson({
            ...feedJson(),
            'cards': [
              for (var i = 0; i < 10; i++)
                {...topicJson(i + 1), 'category': topicCategories[i ~/ 2]},
            ],
          }),
          FeedMode.live,
        );
      await mount(tester, repository);
      expect(find.text('전체 10'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-사회')));
      await tester.pumpAndSettle();
      expect(find.text('사회 2'), findsOneWidget);
      expect(find.text('오늘의 대화 소재 1'), findsNothing);
      await tester.scrollUntilVisible(find.text('오늘의 대화 소재 10'), 250);
      expect(find.text('오늘의 대화 소재 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('legacy bookmark categories remain accessible after the update', (
    tester,
  ) async {
    final store = MemoryStore();
    await store.write(
      'saved-topics-v2',
      jsonEncode([
        {...topicJson(), 'category': '음식'},
      ]),
    );
    await mount(tester, StubRepository(), store: store);
    await tester.tap(find.text('보관함'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('filter-음식')),
      -250,
    );
    await tester.tap(find.byKey(const ValueKey('filter-음식')));
    await tester.pumpAndSettle();
    expect(find.text('음식 1'), findsOneWidget);
    expect(find.text('오늘의 대화 소재 1'), findsOneWidget);
  });
  testWidgets('offline practice is clearly labelled and refresh can recover', (
    tester,
  ) async {
    final repository = StubRepository()
      ..result = FeedResult(
        Briefing.decode(encodedPractice),
        FeedMode.practice,
      );
    await mount(tester, repository);
    expect(find.textContaining('대화 연습 모드'), findsOneWidget);
    repository.result = FeedResult(
      Briefing.fromJson(feedJson()),
      FeedMode.live,
    );
    await tester.tap(find.byTooltip('새로고침'));
    await tester.pumpAndSettle();
    expect(find.textContaining('대화 연습 모드'), findsNothing);
    expect(repository.calls, 2);
  });
  testWidgets('narrow screen and dark mode render without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
      tester,
      StubRepository(),
      brightness: Brightness.dark,
      scale: 2,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
