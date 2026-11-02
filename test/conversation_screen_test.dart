import 'package:malmun/ui/home_screen.dart';
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
          conversationPoolProvider.overrideWith(
            (ref) => ConversationPool(
              ref.watch(briefingProvider).valueOrNull?.briefing.topics ?? [],
            ),
          ),
          repositoryProvider.overrideWithValue(repository),
          storeProvider.overrideWithValue(store),
          guideCatalogProvider.overrideWith((ref) async => realCatalog()),
          conversationClockProvider.overrideWithValue(coachNow),
        ],
        child: const MalmunApp(home: HomeScreen()),
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
      expect(find.text('오늘 무슨 얘기 하지?'), findsOneWidget);
      expect(find.text('오늘 확인한 0 / 3개'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('audience-work')));
      await tester.scrollUntilVisible(find.text('행안부 업무망 AI 검색 기능 도입'), 160);
      expect(find.text('행안부 업무망 AI 검색 기능 도입'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'waits for the full source pool before pinning three diverse lessons',
    (tester) async {
      final base = Briefing.fromJson(coachedFeed()).topics;
      final book = Topic.fromJson(coachedTopic(6, '문화·예술', '김영하 신간 소설 출간'));
      final partial = StateProvider<ConversationPool>(
        (ref) => ConversationPool([base[0], base[2], book], loading: true),
      );
      final repository = StubRepository()
        ..result = FeedResult(Briefing.fromJson(coachedFeed()), FeedMode.live);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repository),
            guideCatalogProvider.overrideWith((ref) async => realCatalog()),
            conversationClockProvider.overrideWithValue(coachNow),
            conversationPoolProvider.overrideWith((ref) => ref.watch(partial)),
          ],
          child: const MalmunApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('coach-open-t1')), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CoachView)),
      );
      container.read(partial.notifier).state = ConversationPool([
        ...base,
        book,
      ]);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('coach-open-t2')),
        200,
      );
      expect(find.byKey(const ValueKey('coach-open-t2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'source evidence, background, memo, feedback and review work without a quiz',
    (tester) async {
      final store = MemoryStore();
      await mount(tester, store);
      await tap(tester, find.byKey(const ValueKey('coach-open-t1')));
      expect(find.text('어떤 소식인가요?'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('배경 참고 · 앱 편집'),
        200,
        scrollable: mainScroll(),
      );
      expect(find.text('배경 참고 · 앱 편집'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConversationScreen)),
      );
      expect(find.text('생각해 보기'), findsNothing);
      await tap(tester, find.text('이해했어요'));
      expect(container.read(learningProvider).understoodIds.length, 1);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('conversation-note')),
        250,
        scrollable: mainScroll(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('conversation-note')),
        '모네 전시 다녀왔는지 물어보기',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tap(tester, find.text('내 문장 저장'));
      await tap(tester, find.text('대화에 써봤어요'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, find.text('내가 남긴 이야기'), direction: -200);
      expect(find.text('이해 표시 1개 · 대화에 써본 1개'), findsOneWidget);
      expect(find.textContaining('모네 전시 다녀왔는지 물어보기'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(tester, store);
      await tap(tester, find.text('내가 남긴 이야기'));
      expect(find.textContaining('모네 전시 다녀왔는지 물어보기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'audience changes keep the displayed and copied first line identical',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester, MemoryStore());
      await tap(tester, find.byKey(const ValueKey('coach-open-t2')));
      expect(find.text('이강인 경기 소식 봤어요? 이번 경기 봤어요?'), findsWidgets);
      await tap(tester, find.text('회사 동료'));
      await tap(tester, find.text('첫마디 복사'));
      expect(copied, '이강인 경기 기사 봤어요? 경기 챙겨 보셨어요?');
      expect(find.text(copied!), findsWidgets);
      expect(copied, isNot(contains('{subject}')));
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
        find.text('오늘 무슨 얘기 하지?'),
        -250,
        scrollable: mainScroll(),
      );
      expect(find.text('오늘 무슨 얘기 하지?'), findsOneWidget);
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
        find.text('반응에 따라 이어가기'),
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
