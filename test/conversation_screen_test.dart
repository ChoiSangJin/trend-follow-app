import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/data/briefing.dart';
import 'package:malmun/data/briefing_repository.dart';
import 'package:malmun/data/briefing_store.dart';
import 'package:malmun/data/conversation.dart';
import 'package:malmun/main.dart';
import 'package:malmun/state/briefing_provider.dart';
import 'package:malmun/state/conversation_provider.dart';
import 'package:malmun/ui/conversation_views.dart';
import 'conversation_fixtures.dart';
import 'home_screen_test.dart' show StubRepository;

void main() {
  Finder mainScroll() => find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  Future<void> mount(
    WidgetTester tester,
    MemoryStore store, {
    FeedMode mode = FeedMode.live,
  }) async {
    final repository = StubRepository()
      ..result = FeedResult(Briefing.fromJson(coachedFeed()), mode);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          storeProvider.overrideWithValue(store),
          guideCatalogProvider.overrideWith((ref) async => realCatalog()),
          conversationClockProvider.overrideWithValue(coachNow),
        ],
        child: const MalmunApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(
    WidgetTester tester,
    Finder finder, {
    double direction = 200,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      direction,
      scrollable: mainScroll(),
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final y = tester.getCenter(finder).dy;
    if (y < 110 || y > height - 130) {
      await tester.drag(find.byType(ListView).first, Offset(0, height / 2 - y));
      await tester.pumpAndSettle();
    }
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  test('the actual bundled editorial asset is readable', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final text = await rootBundle.loadString('assets/conversation_guides.json');
    expect(GuideCatalog.decode(text).guides.length, 10);
  });
  testWidgets(
    'home caps daily lessons at three and changes its selection for the audience',
    (tester) async {
      await mount(tester, MemoryStore());
      expect(find.text('오늘은 3개만,\n대화할 만큼 이해하기'), findsOneWidget);
      expect(find.text('오늘 확인한 0 / 3개'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('audience-work')));
      await tester.scrollUntilVisible(
        find.text('AI가 답을 빨리 찾으면 확인도 끝난 걸까?'),
        160,
      );
      expect(find.text('AI가 답을 빨리 찾으면 확인도 끝난 걸까?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'source evidence, background, understanding check, memo, feedback and review form one flow',
    (tester) async {
      final store = MemoryStore();
      await mount(tester, store);
      await tap(tester, find.byKey(const ValueKey('coach-open-t1')));
      expect(find.text('1. 어떤 소식과 연결되나요?'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('개념 설명 · 앱 편집'),
        200,
        scrollable: mainScroll(),
      );
      expect(find.text('개념 설명 · 앱 편집'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConversationScreen)),
      );
      await tap(tester, find.byKey(const ValueKey('understanding-1')));
      expect(container.read(learningProvider).understoodIds, isEmpty);
      await tap(
        tester,
        find.byKey(const ValueKey('understanding-0')),
        direction: -100,
      );
      expect(container.read(learningProvider).understoodIds.length, 1);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('conversation-note')),
        250,
        scrollable: mainScroll(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('conversation-note')),
        '관찰한 것과 내 해석을 구분해서 말하기',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tap(tester, find.text('내 문장 저장'));
      await tap(tester, find.text('대화에 써봤어요'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, find.text('내가 이해한 이야기'), direction: -200);
      expect(find.text('이해 표시 1개 · 대화에 써본 1개'), findsOneWidget);
      expect(find.textContaining('관찰한 것과 내 해석을 구분해서 말하기'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(tester, store);
      await tap(tester, find.text('내가 이해한 이야기'));
      expect(find.textContaining('관찰한 것과 내 해석을 구분해서 말하기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'offline prepared lessons stay available and the source browser returns to coaching',
    (tester) async {
      await mount(tester, MemoryStore(), mode: FeedMode.cached);
      expect(find.textContaining('최근 소식을 받지 못했어요.'), findsOneWidget);
      await tap(tester, find.text('분야별 소식 둘러보기'));
      expect(find.text('분야별 소식'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('오늘은 3개만,\n대화할 만큼 이해하기'),
        -250,
        scrollable: mainScroll(),
      );
      expect(find.text('오늘은 3개만,\n대화할 만큼 이해하기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'large text and narrow screens keep the coach and conversation controls usable',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mount(tester, MemoryStore());
      await tap(tester, find.byKey(const ValueKey('coach-open-t1')));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('understanding-0')),
        250,
        scrollable: mainScroll(),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('내 문장 저장'),
        250,
        scrollable: mainScroll(),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
