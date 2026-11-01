import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:malmun/data/briefing.dart';
import 'package:malmun/data/briefing_store.dart';
import 'package:malmun/state/briefing_provider.dart';
import 'fixtures.dart';

void main() {
  test('dated source and question survive serialization', () {
    final topic = Topic.fromJson(topicJson());
    expect(Topic.fromJson(topic.toJson()).opener, topic.opener);
    expect(topic.url!.scheme, 'https');
    expect(koreaDate(topic.publishedAt!), '11.01 12:00');
  });
  test('requires safe source and publication date for real news', () {
    for (final change in [
      {'source_url': 'javascript:alert(1)'},
      {'published_at': null},
      {'title': false},
    ]) {
      expect(
        () => Topic.fromJson({...topicJson(), ...change}),
        throwsFormatException,
      );
    }
  });
  test('rejects wrong region, duplicate IDs, and empty daily editions', () {
    for (final change in [
      {'region': 'US'},
      {'cards': []},
      {
        'cards': [topicJson(), topicJson()],
      },
    ]) {
      expect(
        () => Briefing.fromJson({...feedJson(), ...change}),
        throwsFormatException,
      );
    }
  });
  test('practice mode cannot be mislabelled as daily news', () {
    final json = jsonDecode(encodedPractice) as Map<String, dynamic>;
    expect(Briefing.fromJson(json).practice, isTrue);
    expect(
      () => Briefing.fromJson({...json, 'edition': 'daily'}),
      throwsFormatException,
    );
  });
  test(
    'accepts ten cards with two per category and rejects an overflowing category',
    () {
      final cards = [
        for (var i = 0; i < 10; i++)
          {...topicJson(i + 1), 'category': topicCategories[i ~/ 2]},
      ];
      expect(
        Briefing.fromJson({...feedJson(), 'cards': cards}).topics.length,
        10,
      );
      expect(
        () => Briefing.fromJson({
          ...feedJson(),
          'cards': [
            ...cards,
            {...topicJson(11), 'category': '사회'},
          ],
        }),
        throwsFormatException,
      );
      cards[2]['category'] = topicCategories[0];
      expect(
        () => Briefing.fromJson({...feedJson(), 'cards': cards}),
        throwsFormatException,
      );
    },
  );
  test(
    'legacy saved topic labels remain readable without losing bookmarks',
    () async {
      final store = MemoryStore();
      await store.write(
        'saved-topics-v2',
        jsonEncode([
          {...topicJson(), 'category': '문화'},
        ]),
      );
      final controller = SavedTopics(store);
      expect(controller.state.single.category, '문화');
      controller.dispose();
    },
  );
  test('saved topics survive controller restart and can be removed', () async {
    final store = MemoryStore();
    final controller = SavedTopics(store);
    final topic = Topic.fromJson(topicJson());
    await controller.toggle(topic);
    final restored = SavedTopics(store);
    expect(restored.state.single.id, topic.id);
    await restored.toggle(topic);
    expect(SavedTopics(store).state, isEmpty);
    controller.dispose();
    restored.dispose();
  });
  test('corrupt saved data does not crash startup', () async {
    final store = MemoryStore();
    await store.write('saved-topics-v2', '{bad');
    final controller = SavedTopics(store);
    expect(controller.state, isEmpty);
    controller.dispose();
  });
}
