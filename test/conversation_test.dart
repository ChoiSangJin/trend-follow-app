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
    'editorial catalog provides ten specific lessons, checks and three audience flows',
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
  });
  test('daily progress uses the Korean date boundary', () {
    expect(koreaDay(DateTime.utc(2026, 11, 1, 14, 59)), '2026-11-01');
    expect(koreaDay(DateTime.utc(2026, 11, 1, 15)), '2026-11-02');
  });
}
