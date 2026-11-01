import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:follow_mz/data/trend_repository.dart';
import 'package:follow_mz/data/trends.dart';
import 'package:follow_mz/main.dart';
import 'package:follow_mz/state/trend_provider.dart';

class StubRepository extends TrendRepository {
  StubRepository() : super(Dio(), endpoint: 'https://example.com/trends.json');
  int calls = 0;
  bool fail = false;
  TrendFeed feed = TrendFeed.fromJson({
    'is_demo': true, 'updated_at': '2026-10-30T09:00:00Z',
    'categories': {
      'keywords': [{'rank': 1, 'keyword': '테스트 키워드', 'search_volume': '100K+'}],
      'memes': [{'title': '테스트 밈', 'description': '사용 예시 설명'}],
      'hotplaces': [{'name': '테스트 장소', 'district': '성동구', 'crowd_level': '약간 붐빔'}],
    },
  });
  @override
  Future<TrendFeed> fetch({bool force = false}) async {
    calls++;
    if (fail) throw Exception('offline');
    return feed;
  }
}

void main() {
  Future<void> mount(WidgetTester tester, StubRepository repository) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      repositoryProvider.overrideWithValue(repository),
    ], child: const FollowMzApp()));
    await tester.pumpAndSettle();
  }

  testWidgets('renders categories, expands memes, and labels sample data', (tester) async {
    await mount(tester, StubRepository());
    expect(find.text('테스트 키워드'), findsOneWidget);
    expect(find.textContaining('예시 데이터'), findsOneWidget);
    expect(find.textContaining('18:00 KST'), findsOneWidget);
    await tester.tap(find.text('밈 & 유행어'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('테스트 밈'));
    await tester.pumpAndSettle();
    expect(find.text('사용 예시 설명'), findsOneWidget);
    await tester.tap(find.text('핫플레이스'));
    await tester.pumpAndSettle();
    expect(find.text('테스트 장소'), findsOneWidget);
    expect(find.text('네이버지도'), findsOneWidget);
    expect(find.text('카카오맵'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial failure offers retry and can recover', (tester) async {
    final repository = StubRepository()..fail = true;
    await mount(tester, repository);
    expect(find.text('지금은 소식을 불러올 수 없어요'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('테스트 키워드'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('refresh failure retains last successful feed with warning', (tester) async {
    final repository = StubRepository();
    await mount(tester, repository);
    repository.fail = true;
    await tester.tap(find.byTooltip('새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('테스트 키워드'), findsOneWidget);
    expect(find.textContaining('업데이트 실패'), findsOneWidget);
  });

  testWidgets('empty category has retry action and supports pull refresh', (tester) async {
    final repository = StubRepository()..feed = const TrendFeed();
    await mount(tester, repository);
    expect(find.text('새로운 소식을 준비 중이에요'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
  });
}
