import 'package:malmun/ui/home_screen.dart';
import 'package:malmun/state/conversation_provider.dart';
import 'conversation_fixtures.dart';
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
          conversationPoolProvider.overrideWith(
            (ref) => ConversationPool(
              ref.watch(briefingProvider).valueOrNull?.briefing.topics ?? [],
            ),
          ),
          guideCatalogProvider.overrideWith((ref) async => realCatalog()),
          repositoryProvider.overrideWithValue(repository),
          storeProvider.overrideWithValue(store ?? MemoryStore()),
        ],
        child: const MalmunApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('분야별 소식 둘러보기'), 250);
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('분야별 소식 둘러보기'));
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
      expect(find.text('이렇게 말 걸어봐'), findsNothing);
      expect(find.text('질문 복사'), findsNothing);
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
    'all fourteen cards are available with two per field and matching filter count',
    (tester) async {
      final repository = StubRepository()
        ..result = FeedResult(
          Briefing.fromJson({
            ...feedJson(),
            'cards': [
              for (var i = 0; i < 14; i++)
                {...topicJson(i + 1), 'category': topicCategories[i ~/ 2]},
            ],
          }),
          FeedMode.live,
        );
      await mount(tester, repository);
      expect(find.text('전체 14'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-세계뉴스')));
      await tester.pumpAndSettle();
      expect(find.text('세계뉴스 2'), findsOneWidget);
      expect(find.text('오늘의 대화 소재 1'), findsNothing);
      await tester.scrollUntilVisible(find.text('오늘의 대화 소재 14'), 250);
      expect(find.text('오늘의 대화 소재 14'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('selection criteria and source evidence are inspectable', (
    tester,
  ) async {
    await mount(tester, StubRepository());
    await tester.tap(find.byTooltip('선정 기준'));
    await tester.pumpAndSettle();
    expect(find.text('대화 추천 선정 기준'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('대화 준비').first, 250);
    await tester.drag(find.byType(ListView).first, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('대화 준비').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('선정 근거 · 확인한 출처'), 250);
    expect(find.textContaining('수집한 관련 보도 3개'), findsOneWidget);
    expect(find.textContaining('사실 확정이나 조회수 지표는 아닙니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('single-source arts cards and details explain the limitation', (
    tester,
  ) async {
    final source = (coverageJson()['sources'] as List).last;
    final repository = StubRepository()
      ..result = FeedResult(
        Briefing.fromJson({
          ...feedJson(),
          'cards': [
            {
              ...topicJson(),
              'coverage': {
                ...coverageJson(),
                'source_groups': 1,
                'report_count': 1,
                'span_hours': 0,
                'first_report_at': source['published_at'],
                'first_report_url': source['url'],
                'sources': [source],
              },
            },
          ],
        }),
        FeedMode.live,
      );
    await mount(tester, repository);
    await tester.scrollUntilVisible(find.text('단일 출처 · 인기 확인 전'), 160);
    expect(find.text('단일 출처 · 인기 확인 전'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('대화 준비'), 160);
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('대화 준비'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('단일 출처 · 인기 확인 전. 추가 읽을거리'),
      200,
    );
    expect(find.textContaining('여러 매체의 관심이 확인된 소식은 아닙니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
