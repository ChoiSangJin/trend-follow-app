import 'dart:convert';
import 'briefing.dart';

class TrendItem {
  const TrendItem(
    this.topic,
    this.rank,
    this.sourceGroups,
    this.dailySources,
    this.trackingHours,
    this.ready,
    this.growthPercent,
    this.signal,
  );
  factory TrendItem.fromJson(Json json, DateTime updated, DateTime started) {
    if (json['topic'] is! Map) throw const FormatException('Invalid topic');
    final topic = Topic.fromJson(
      Map<String, dynamic>.from(json['topic'] as Map),
    );
    final rank = json['rank'], groups = json['source_groups'];
    final daily = json['daily_sources'];
    final hours = json['tracking_hours'], ready = json['comparison_ready'];
    final percent = json['growth_percent'], signal = json['signal'];
    if (topic.isPractice ||
        topic.coverage == null ||
        topic.coverage!.groups < 2 ||
        !topicCategories.contains(topic.category) ||
        topic.coverage!.first.isBefore(
          updated.subtract(const Duration(hours: 72)),
        ) ||
        topic.coverage!.last.isAfter(updated) ||
        rank is! int ||
        rank < 1 ||
        rank > 30 ||
        groups is! int ||
        topic.coverage!.groups != (groups > 8 ? 8 : groups) ||
        groups > 600 ||
        daily is! List ||
        daily.length != 3 ||
        daily.any((v) => v is! int || v < 0 || v > groups) ||
        daily.cast<int>().reduce((a, b) => a + b) < groups ||
        hours is! num ||
        !hours.isFinite ||
        hours < 0 ||
        hours > 72 ||
        hours > updated.difference(started).inSeconds / 3600 + .11 ||
        ready is! bool ||
        ready != (hours >= 48) ||
        !['collecting', 'growing', 'new', 'steady'].contains(signal)) {
      throw const FormatException('Invalid trend evidence');
    }
    final counts = daily.cast<int>();
    final previous = counts[1], current = counts[2];
    final expected = !ready
        ? 'collecting'
        : previous >= 2 && current >= 3 && current >= previous * 1.5
        ? 'growing'
        : previous == 0 && current >= 2
        ? 'new'
        : 'steady';
    if (signal != expected ||
        (ready && previous >= 2
            ? percent is! num ||
                  !percent.isFinite ||
                  (percent - (current - previous) * 100 / previous).abs() > .11
            : percent != null)) {
      throw const FormatException('Inconsistent comparison');
    }
    return TrendItem(
      topic,
      rank,
      groups,
      List<int>.from(daily),
      hours.toDouble(),
      ready,
      (percent as num?)?.toDouble(),
      signal as String,
    );
  }
  final Topic topic;
  final int rank, sourceGroups;

  /// Oldest 24-hour window first; each publisher/copy group counted once per window.
  final List<int> dailySources;
  final double trackingHours;
  final bool ready;
  final double? growthPercent;
  final String signal;
  bool get isGrowing => signal == 'growing';
  String get label => switch (signal) {
    'growing' => '보도 출처 증가 +${growthPercent!.round()}%',
    'new' => '최근 24시간 새로 포착',
    'steady' => '추가 관측 중',
    _ => '증가 비교 집계 중',
  };
}

class TrendsFeed {
  const TrendsFeed(this.updatedAt, this.startedAt, this.snapshots, this.items);
  factory TrendsFeed.decode(String encoded) {
    final raw = jsonDecode(encoded);
    if (raw is! Map ||
        raw['schema_version'] != 1 ||
        raw['region'] != 'KR' ||
        raw['cards'] is! List) {
      throw const FormatException('Unsupported trends');
    }
    final updated = DateTime.tryParse(stringValue(raw['updated_at']));
    final started = DateTime.tryParse(stringValue(raw['tracking_started_at']));
    final count = raw['snapshot_count'];
    if (updated == null ||
        started == null ||
        started.isAfter(updated) ||
        updated.difference(started) > const Duration(hours: 72) ||
        count is! int ||
        count < 1 ||
        count > 1000 ||
        (raw['cards'] as List).length > 30) {
      throw const FormatException('Invalid observation history');
    }
    final items = (raw['cards'] as List).map((item) {
      if (item is! Map) throw const FormatException('Invalid trend');
      return TrendItem.fromJson(
        Map<String, dynamic>.from(item),
        updated,
        started,
      );
    }).toList();
    if (items.map((i) => i.topic.id).toSet().length != items.length ||
        items.asMap().entries.any((e) => e.value.rank != e.key + 1)) {
      throw const FormatException('Invalid trend ranks');
    }
    return TrendsFeed(updated, started, count, items);
  }
  final DateTime updatedAt, startedAt;
  final int snapshots;
  final List<TrendItem> items;
}
