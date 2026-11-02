import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/data/briefing.dart';
import 'package:malmun/data/briefing_store.dart';
import 'package:malmun/data/conversation.dart';
import 'package:malmun/state/conversation_provider.dart';

import 'conversation_fixtures.dart';
import 'fixtures.dart';

class FailingLearningStore extends MemoryStore {
  bool fail = false;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('disk full');
    await super.write(key, value);
  }
}

void main() {
  test(
    'editorial catalog provides ten topic guides and three audience flows',
    () {
      final catalog = realCatalog();
      expect(catalog.guides.length, 10);
      expect(
        catalog.guides.map((g) => g.category).toSet(),
        topicCategories.toSet(),
      );
      for (final g in catalog.guides) {
        expect(g.background.length, greaterThanOrEqualTo(2));
        expect(audiences.keys.map(g.opening).toSet().length, 3);
        expect(g.followups('friends').length, 2);
        expect(safeLink(g.json['reference']['url']), isNotNull);
      }
    },
  );
  test(
    'actual source quotations survive saves and older unquoted feeds remain readable',
    () {
      final topic = Briefing.fromJson(coachedFeed()).topics.first;
      expect(
        topic.coverage!.sources.where((s) => s.headline != null).length,
        2,
      );
      expect(
        Topic.fromJson(topic.toJson()).coverage!.sources.last.headline,
        topic.title,
      );
      expect(
        Topic.fromJson(topicJson()).coverage!.sources.last.headline,
        isNull,
      );
      final bad = topic.toJson();
      (bad['coverage']['sources'] as List).last['headline'] = false;
      expect(() => Topic.fromJson(bad), throwsFormatException);
    },
  );
  test(
    'three lessons prioritize unread topics, distinct fields and the selected audience',
    () {
      final options = eligibleBriefings(
        Briefing.fromJson(coachedFeed()).topics,
        realCatalog(),
        coachNow(),
      );
      final friends = chooseBriefings(options, 'friends', {});
      final work = chooseBriefings(options, 'work', {});
      expect(friends.length, 3);
      expect(friends.map((b) => b.topic.category).toSet().length, 3);
      expect(work.first.guide.id, 'ai-work');
      expect(friends.first.guide.id, isNot(work.first.guide.id));
      expect(
        chooseBriefings(
          options,
          'friends',
          {},
          understoodGuides: {'exhibition'},
        ).any((b) => b.guide.id == 'exhibition'),
        isFalse,
      );
      final read = {friends.first.topic.id};
      expect(
        chooseBriefings(
          options,
          'friends',
          read,
        ).any((b) => read.contains(b.topic.id)),
        isFalse,
      );
      expect(
        chooseBriefings(options.take(1).toList(), 'friends', {}).length,
        1,
      );
    },
  );
  test(
    'unprepared, future, too-fresh and expired stories never pad the daily cards',
    () {
      final topic = Briefing.fromJson(coachedFeed()).topics.first;
      final unquoted = Topic.fromJson({
        ...topic.toJson(),
        'coverage': coverageJson(),
      });
      expect(eligibleBriefings([unquoted], realCatalog(), coachNow()), isEmpty);
      expect(
        eligibleBriefings([topic], realCatalog(), DateTime.utc(2026, 11, 1, 4)),
        isEmpty,
      );
      expect(
        eligibleBriefings([topic], realCatalog(), DateTime.utc(2026, 10, 31)),
        isEmpty,
      );
      expect(
        eligibleBriefings(
          [topic],
          realCatalog(),
          coachNow().add(const Duration(days: 4)),
        ),
        isEmpty,
      );
    },
  );
  test(
    'local feedback, notes and audience persist without touching bookmarks',
    () async {
      final store = MemoryStore();
      final controller = LearningController(store, coachNow);
      final brief = eligibleBriefings(
        Briefing.fromJson(coachedFeed()).topics,
        realCatalog(),
        coachNow(),
      ).first;
      await controller.setAudience('work');
      await controller.update(brief, note: '관찰과 해석을 나눠서 말하기');
      expect(controller.state.record(brief.topic.id)!.understood, isFalse);
      await Future.wait([
        controller.update(brief, feedback: 'learned'),
        controller.update(brief, feedback: 'used'),
      ]);
      expect(controller.state.records.length, 1);
      final restored = LearningController(store, coachNow);
      final record = restored.state.records.single;
      expect(restored.state.audience, 'work');
      expect(record.understood, isTrue);
      expect(record.used, isTrue);
      expect(record.note, '관찰과 해석을 나눠서 말하기');
      expect(store.read('saved-topics-v2'), isNull);
      controller.dispose();
      restored.dispose();
    },
  );
  test(
    'write failures preserve state and do not poison subsequent learning writes',
    () async {
      final store = FailingLearningStore()..fail = true;
      final controller = LearningController(store, coachNow);
      final brief = eligibleBriefings(
        Briefing.fromJson(coachedFeed()).topics,
        realCatalog(),
        coachNow(),
      ).first;
      await expectLater(
        controller.update(brief, understood: true),
        throwsStateError,
      );
      expect(controller.state.records, isEmpty);
      store.fail = false;
      await controller.update(brief, feedback: 'known');
      expect(controller.state.records.single.understood, isTrue);
      controller.dispose();
    },
  );
  test('one damaged record cannot erase valid learning history', () async {
    final store = MemoryStore();
    final controller = LearningController(store, coachNow);
    final brief = eligibleBriefings(
      Briefing.fromJson(coachedFeed()).topics,
      realCatalog(),
      coachNow(),
    ).first;
    await controller.update(brief, understood: true);
    final raw = jsonDecode(store.read('conversation-learning-v1')!);
    raw['records'] = [
      null,
      {'bad': true},
      ...raw['records'],
    ];
    await store.write('conversation-learning-v1', jsonEncode(raw));
    final restored = LearningController(store, coachNow);
    expect(restored.state.records.single.topic.id, brief.topic.id);
    controller.dispose();
    restored.dispose();
  });
  test('AI personnel appointments do not become tool-use lessons', () {
    final topic = Topic.fromJson(
      coachedTopic(6, '기술·과학', '국민AI서비스혁신추진단장에 김세웅 전 카카오 부사장'),
    );
    expect(realCatalog().match(topic), isNull);
    final award = Topic.fromJson(
      coachedTopic(7, '문화·예술', '제1회 문학상 시상식 개최…대상 작가 선정'),
    );
    expect(realCatalog().match(award), isNull);
    final resale = Topic.fromJson(
      coachedTopic(8, '스포츠', '프로야구 경기 티켓 되팔아 돈 챙긴 일당'),
    );
    expect(realCatalog().match(resale), isNull);
    final ticketCrime = Topic.fromJson(
      coachedTopic(9, '문화·예술', '공연 티켓 웃돈 판매로 돈 챙긴 일당'),
    );
    expect(realCatalog().match(ticketCrime), isNull);
    final market = Topic.fromJson(
      coachedTopic(10, '문화·예술', '공연시장 티켓판매 증가 통계 발표'),
    );
    expect(realCatalog().match(market)?.id, 'ticket-sales');
  });
  test(
    'matching quoted evidence can come from the wider pool without duplicating lessons',
    () {
      final quoted = Briefing.fromJson(coachedFeed()).topics.first;
      final old = Topic.fromJson({
        ...quoted.toJson(),
        'coverage': coverageJson(),
      });
      final items = eligibleBriefings(
        [old, quoted, quoted],
        realCatalog(),
        coachNow(),
      );
      expect(items.length, 1);
      expect(items.single.topic.coverage!.sources.last.headline, quoted.title);
    },
  );
  test('spoken opening uses only subjects present in the actual article', () {
    final catalog = realCatalog();
    final lee = Topic.fromJson(
      coachedTopic(9, '스포츠', '이강인 축구 경기 골대 불운에도 팀 7연승'),
    );
    final son = Topic.fromJson(coachedTopic(10, '스포츠', '손흥민 축구 경기 출전'));
    final leeBrief = ConversationBrief(lee, catalog.match(lee)!);
    final sonBrief = ConversationBrief(son, catalog.match(son)!);
    expect(leeBrief.opening('friends'), '이강인 경기 소식 봤어요? 이번 경기 봤어요?');
    expect(sonBrief.opening('friends'), contains('손흥민 경기'));
    expect(sonBrief.opening('friends'), isNot(contains('이강인')));
    final unnamed = Topic.fromJson(coachedTopic(11, '스포츠', '축구 경기 골 장면 화제'));
    expect(
      ConversationBrief(unnamed, catalog.match(unnamed)!).opening('friends'),
      '이 경기 소식 봤어요? 이번 경기 봤어요?',
    );
  });
  test('private finance and diplomacy are excluded for people just met', () {
    final options = eligibleBriefings(
      Briefing.fromJson(coachedFeed()).topics,
      realCatalog(),
      coachNow(),
    );
    expect(
      chooseBriefings(
        options,
        'new',
        {},
      ).any((b) => b.guide.id == 'stock-index'),
      isFalse,
    );
    expect(
      chooseBriefings(
        options.where((b) => b.guide.id == 'stock-index').toList(),
        'new',
        {},
      ),
      isEmpty,
    );
  });
  test(
    'upcoming games use watching plans instead of asking about a finished game',
    () {
      final catalog = realCatalog();
      final topic = Topic.fromJson(
        coachedTopic(12, '스포츠', "손흥민, 미네소타전 선발 출격…축구 경기 도움 기록 도전"),
      );
      final brief = ConversationBrief(topic, catalog.match(topic)!);
      expect(brief.opening('friends'), '손흥민 경기 소식 봤어요? 이번 경기 볼 거예요?');
      expect(brief.followups('friends').first, contains('시간 맞으면 같이 볼래요?'));
      final schedule = Topic.fromJson(
        coachedTopic(13, '스포츠', "2026 KBO 한국시리즈 경기 일정"),
      );
      expect(
        ConversationBrief(schedule, catalog.match(schedule)!).opening('work'),
        contains('볼 예정이세요?'),
      );
      final politics = Topic.fromJson(
        coachedTopic(14, '세계뉴스', '미 국무, 중간선거 패해도 외교 변하지 않아'),
      );
      expect(catalog.match(politics), isNull);
    },
  );
  test('daily progress uses the Korean date boundary', () {
    expect(koreaDay(DateTime.utc(2026, 11, 1, 14, 59)), '2026-11-01');
    expect(koreaDay(DateTime.utc(2026, 11, 1, 15)), '2026-11-02');
  });
}
