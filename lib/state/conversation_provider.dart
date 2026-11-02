import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/briefing.dart';
import '../data/briefing_store.dart';
import '../data/conversation.dart';
import 'briefing_provider.dart';
import 'trends_provider.dart';

final conversationClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final guideCatalogProvider = FutureProvider<GuideCatalog>(
  (ref) async => GuideCatalog.decode(
    await rootBundle.loadString('assets/conversation_guides.json'),
  ),
);
final learningProvider =
    StateNotifierProvider<LearningController, LearningState>(
      (ref) => LearningController(
        ref.watch(storeProvider),
        ref.watch(conversationClockProvider),
      ),
    );

class LearningRecord {
  const LearningRecord({
    required this.topic,
    required this.guideId,
    required this.updatedAt,
    this.understood = false,
    this.feedback = '',
    this.used = false,
    this.note = '',
  });
  final Topic topic;
  final String guideId, feedback, note;
  final DateTime updatedAt;
  final bool understood, used;
  Json toJson() => {
    'topic': topic.toJson(),
    'guide_id': guideId,
    'updated_at': updatedAt.toIso8601String(),
    'understood': understood,
    'feedback': feedback,
    'used': used,
    'note': note,
  };
  factory LearningRecord.fromJson(Json json) {
    final date = DateTime.tryParse(stringValue(json['updated_at']));
    if (json['topic'] is! Map ||
        stringValue(json['guide_id']).isEmpty ||
        date == null ||
        json['understood'] is! bool ||
        json['used'] is! bool ||
        !['', 'learned', 'known', 'used'].contains(json['feedback']) ||
        json['note'] is! String ||
        (json['note'] as String).length > 4000) {
      throw const FormatException('Invalid learning record');
    }
    return LearningRecord(
      topic: Topic.fromJson(Map<String, dynamic>.from(json['topic'])),
      guideId: json['guide_id'],
      updatedAt: date,
      understood: json['understood'],
      feedback: json['feedback'],
      used: json['used'],
      note: json['note'],
    );
  }
}

class LearningState {
  const LearningState({this.audience = 'friends', this.records = const []});
  final String audience;
  final List<LearningRecord> records;
  LearningRecord? record(String id) {
    for (final r in records) {
      if (r.topic.id == id) return r;
    }
    return null;
  }

  Set<String> get understoodGuideIds =>
      records.where((r) => r.understood).map((r) => r.guideId).toSet();
  Set<String> get understoodIds =>
      records.where((r) => r.understood).map((r) => r.topic.id).toSet();
}

class LearningController extends StateNotifier<LearningState> {
  LearningController(this.store, this.now) : super(const LearningState()) {
    try {
      final raw = jsonDecode(store.read('conversation-learning-v1') ?? '{}');
      if (raw is Map && raw['schema_version'] == 1) {
        final records = <LearningRecord>[];
        if (raw['records'] is List) {
          for (final item in (raw['records'] as List).take(150)) {
            try {
              if (item is Map) {
                records.add(
                  LearningRecord.fromJson(Map<String, dynamic>.from(item)),
                );
              }
            } catch (_) {
              /* Preserve other valid records. */
            }
          }
        }
        state = LearningState(
          audience: audiences.containsKey(raw['audience'])
              ? raw['audience']
              : 'friends',
          records: records,
        );
      }
    } catch (_) {
      /* A broken local cache must not block reading. */
    }
  }
  final BriefingStore store;
  final DateTime Function() now;
  Future<void> _pending = Future.value();
  Future<void> _commit(LearningState Function(LearningState) update) {
    final operation = _pending.then((_) async {
      final next = update(state);
      await store.write(
        'conversation-learning-v1',
        jsonEncode({
          'schema_version': 1,
          'audience': next.audience,
          'records': next.records.map((r) => r.toJson()).toList(),
        }),
      );
      if (mounted) state = next;
    });
    _pending = operation.catchError((_) {});
    return operation;
  }

  Future<void> setAudience(String audience) {
    if (!audiences.containsKey(audience)) {
      throw ArgumentError('Invalid audience');
    }
    return _commit(
      (s) => LearningState(audience: audience, records: s.records),
    );
  }

  Future<void> update(
    ConversationBrief brief, {
    bool? understood,
    String? feedback,
    String? note,
  }) {
    if (brief.topic.isPractice) {
      throw ArgumentError('Only sourced news can be recorded');
    }
    if (feedback != null && !['learned', 'known', 'used'].contains(feedback)) {
      throw ArgumentError('Invalid feedback');
    }
    if (note != null && note.length > 4000) {
      throw ArgumentError('Note is too long');
    }
    return _commit((s) {
      final old = s.record(brief.topic.id);
      final record = LearningRecord(
        topic: brief.topic,
        guideId: brief.guide.id,
        updatedAt: now().toUtc(),
        understood:
            understood ?? (feedback != null ? true : old?.understood ?? false),
        feedback: feedback ?? old?.feedback ?? '',
        used: feedback == 'used' || (old?.used ?? false),
        note: note ?? old?.note ?? '',
      );
      return LearningState(
        audience: s.audience,
        records: [
          record,
          ...s.records.where((r) => r.topic.id != brief.topic.id),
        ].take(150).toList(),
      );
    });
  }
}

class ConversationPool {
  const ConversationPool(
    this.topics, {
    this.loading = false,
    this.cached = false,
  });
  final List<Topic> topics;
  final bool loading, cached;
}

final conversationPoolProvider = Provider<ConversationPool>((ref) {
  final news = ref.watch(briefingProvider);
  final trends = ref.watch(trendsProvider);
  return ConversationPool(
    [
      ...news.valueOrNull?.briefing.topics ?? <Topic>[],
      ...trends.valueOrNull?.feed.items.map((i) => i.topic) ?? <Topic>[],
    ],
    loading: news.isLoading || trends.isLoading,
    cached: trends.valueOrNull?.cached ?? false,
  );
});
Future<void> refreshConversation(WidgetRef ref) async {
  await Future.wait([
    ref.read(briefingProvider.notifier).refresh(),
    ref.read(trendsProvider.notifier).refresh(),
  ]);
}
