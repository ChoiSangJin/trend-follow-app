import 'dart:convert';

import 'briefing.dart';

const audiences = {'work': '회사 동료', 'friends': '친구', 'new': '처음 만난 사람'};

class ConversationGuide {
  ConversationGuide(this.json);
  final Json json;
  factory ConversationGuide.fromJson(Json raw) {
    for (final key in [
      'id',
      'category',
      'title',
      'takeaway',
      'connection',
      'caution',
      'subject',
    ]) {
      if (stringValue(raw[key]).isEmpty) {
        throw FormatException('Missing guide $key');
      }
    }
    if (!topicCategories.contains(raw['category']) ||
        raw['match'] is! List ||
        (raw['match'] as List).isEmpty ||
        (raw['match'] as List).any(
          (g) =>
              g is! List || g.isEmpty || g.any((w) => stringValue(w).isEmpty),
        ) ||
        raw['background'] is! List ||
        (raw['background'] as List).length < 2 ||
        (raw['background'] as List).any((s) => stringValue(s).isEmpty) ||
        raw['dialogs'] is! Map ||
        raw['priority'] is! Map ||
        raw['subjects'] is! List ||
        (raw['subjects'] as List).any((s) => stringValue(s).isEmpty) ||
        raw['reference'] is! Map) {
      throw const FormatException('Incomplete conversation guide');
    }
    if (raw.containsKey('preview_markers') &&
        (raw['preview_markers'] is! List ||
            (raw['preview_markers'] as List).isEmpty ||
            (raw['preview_markers'] as List).any(
              (s) => stringValue(s).isEmpty,
            ) ||
            raw['preview_dialogs'] is! Map)) {
      throw const FormatException('Invalid upcoming game dialog');
    }
    for (final dialogs in [
      raw['dialogs'],
      if (raw.containsKey('preview_markers')) raw['preview_dialogs'],
    ]) {
      for (final audience in audiences.keys) {
        final dialog = dialogs[audience];
        final priority = raw['priority'][audience];
        if (dialog is! Map ||
            stringValue(dialog['opening']).isEmpty ||
            dialog['followups'] is! List ||
            (dialog['followups'] as List).length != 2 ||
            (dialog['followups'] as List).any((q) => stringValue(q).isEmpty) ||
            priority is! int ||
            priority < 0 ||
            priority > 10) {
          throw const FormatException('Invalid audience dialog');
        }
      }
    }
    if (stringValue(raw['reference']['label']).isEmpty ||
        safeLink(raw['reference']['url']) == null) {
      throw const FormatException('Invalid guide reference');
    }
    return ConversationGuide(raw);
  }
  String get id => json['id'];
  String get category => json['category'];
  String get title => json['title'];
  String get takeaway => json['takeaway'];
  List<String> get background => List<String>.from(json['background']);
  String get connection => json['connection'];
  String get caution => json['caution'];
  String opening(String audience) => json['dialogs'][audience]['opening'];
  List<String> followups(String audience) =>
      List<String>.from(json['dialogs'][audience]['followups']);
  int priority(String audience) => json['priority'][audience];
  bool matches(Topic topic) =>
      topic.category == category &&
      !(json['exclude'] is List &&
          (json['exclude'] as List).any(
            (word) => topic.title.toLowerCase().contains(
              (word as String).toLowerCase(),
            ),
          )) &&
      (json['match'] as List).every(
        (group) => (group as List).any(
          (word) => topic.title.toLowerCase().contains(
            (word as String).toLowerCase(),
          ),
        ),
      );
}

class GuideCatalog {
  const GuideCatalog(this.guides);
  factory GuideCatalog.decode(String encoded) {
    final raw = jsonDecode(encoded);
    if (raw is! Map || raw['schema_version'] != 1 || raw['guides'] is! List) {
      throw const FormatException('Invalid guide catalog');
    }
    final guides = (raw['guides'] as List).map((g) {
      if (g is! Map) throw const FormatException('Invalid guide');
      return ConversationGuide.fromJson(Map<String, dynamic>.from(g));
    }).toList();
    if (guides.isEmpty ||
        guides.map((g) => g.id).toSet().length != guides.length) {
      throw const FormatException('Empty or duplicate guides');
    }
    return GuideCatalog(guides);
  }
  final List<ConversationGuide> guides;
  ConversationGuide? match(Topic topic) {
    for (final guide in guides) {
      if (guide.matches(topic)) return guide;
    }
    return null;
  }
}

class ConversationBrief {
  const ConversationBrief(this.topic, this.guide);
  final Topic topic;
  final ConversationGuide guide;

  bool get isPreview =>
      guide.json['preview_markers'] is List &&
      (guide.json['preview_markers'] as List).any(
        (word) => topic.title.contains(word as String),
      );
  Map get _dialogs =>
      (isPreview ? guide.json['preview_dialogs'] : guide.json['dialogs'])
          as Map;
  List<String> followups(String audience) =>
      List<String>.from(_dialogs[audience]['followups']);

  // Use only names literally present in this headline. Never invent a result,
  // a score, a reason for a market move, or the speaker's viewing experience.
  String opening(String audience) {
    var subject = guide.json['subject'] as String;
    for (final name in List<String>.from(guide.json['subjects'])) {
      if (!topic.title.toLowerCase().contains(name.toLowerCase())) continue;
      subject = switch (guide.id) {
        'football-contribution' || 'team-streak' => '$name 경기',
        'exhibition' => '$name 전시',
        'music' => topic.title.contains('신곡') ? '$name 신곡' : '$name 새 앨범',
        'commute' => '$name 관련 소식',
        _ => name,
      };
      break;
    }
    return (_dialogs[audience]['opening'] as String).replaceAll(
      '{subject}',
      subject,
    );
  }
}

List<ConversationBrief> eligibleBriefings(
  List<Topic> topics,
  GuideCatalog catalog,
  DateTime now,
) {
  final cutoff = now.toUtc().subtract(const Duration(hours: 72));
  final result = <ConversationBrief>[];
  final ids = <String>{};
  for (final topic in topics) {
    final guide = catalog.match(topic);
    if (guide == null ||
        topic.isPractice ||
        topic.publishedAt == null ||
        topic.publishedAt!.isBefore(cutoff) ||
        topic.publishedAt!.isAfter(
          now.toUtc().subtract(const Duration(hours: 6)),
        ) ||
        topic.coverage == null ||
        topic.coverage!.groups < 2) {
      continue;
    }
    final quotes = topic.coverage!.sources
        .where(
          (s) =>
              s.headline != null &&
              !s.publishedAt.isBefore(cutoff) &&
              !s.publishedAt.isAfter(
                now.toUtc().subtract(const Duration(hours: 6)),
              ),
        )
        .toList();
    if (quotes.length >= 2 && ids.add(topic.id)) {
      result.add(ConversationBrief(topic, guide));
    }
  }
  return result;
}

List<ConversationBrief> chooseBriefings(
  List<ConversationBrief> options,
  String audience,
  Set<String> understood, {
  Set<String> understoodGuides = const {},
}) {
  final sorted = options.where((b) => b.guide.priority(audience) > 0).toList()
    ..sort((a, b) {
      final seen =
          (understood.contains(a.topic.id)
                  ? 2
                  : understoodGuides.contains(a.guide.id)
                  ? 1
                  : 0)
              .compareTo(
                understood.contains(b.topic.id)
                    ? 2
                    : understoodGuides.contains(b.guide.id)
                    ? 1
                    : 0,
              );
      if (seen != 0) return seen;
      final priority = b.guide
          .priority(audience)
          .compareTo(a.guide.priority(audience));
      if (priority != 0) return priority;
      return b.topic.publishedAt!.compareTo(a.topic.publishedAt!);
    });
  final chosen = <ConversationBrief>[];
  for (final item in sorted) {
    if (chosen.any((b) => b.topic.category == item.topic.category)) continue;
    chosen.add(item);
    if (chosen.length == 3) return chosen;
  }
  return chosen;
}

String koreaDay(DateTime date) => date
    .toUtc()
    .add(const Duration(hours: 9))
    .toIso8601String()
    .substring(0, 10);
