import 'dart:convert';
import 'briefing.dart';

const netflixChartUrl = 'https://www.netflix.com/tudum/top10/south-korea';
const netflixDataUrl =
    'https://www.netflix.com/tudum/top10/data/all-weeks-countries.tsv';

DateTime chartDate(dynamic value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid chart date');
  }
  final result = DateTime.parse('${value}T00:00:00Z');
  if (result.toIso8601String().substring(0, 10) != value ||
      result.weekday != DateTime.sunday) {
    throw const FormatException('Chart must end on Sunday');
  }
  return result;
}

class NetflixTitle {
  NetflixTitle(this.json, this.category);
  final Json json;
  final String category;
  factory NetflixTitle.fromJson(Json json, String category) {
    if (!['TV', 'Films'].contains(category) ||
        stringValue(json['id']).isEmpty ||
        !stringValue(json['id']).startsWith('$category:') ||
        stringValue(json['title']).isEmpty ||
        json['rank'] is! int ||
        json['rank'] < 1 ||
        json['rank'] > 10 ||
        json['weeks_in_top10'] is! int ||
        json['weeks_in_top10'] < 1 ||
        (json['previous_rank'] != null &&
            (json['previous_rank'] is! int ||
                json['previous_rank'] < 1 ||
                json['previous_rank'] > 10))) {
      throw const FormatException('Invalid Netflix title');
    }
    final metadata = json['metadata'];
    if (metadata != null &&
        (metadata is! Map ||
            stringValue(metadata['source_url']).isEmpty ||
            safeLink(metadata['source_url'])?.host != 'www.netflix.com')) {
      throw const FormatException('Invalid metadata source');
    }
    if (metadata is Map) {
      for (final key in ['watch_url', 'title_url']) {
        if (metadata[key] != null &&
            safeLink(metadata[key])?.host != 'www.netflix.com') {
          throw const FormatException('Invalid Netflix link');
        }
      }
      if (metadata['image_url'] != null) {
        final host = safeLink(metadata['image_url'])?.host ?? '';
        if (!host.endsWith('.nflximg.net') && !host.endsWith('.nflxso.net')) {
          throw const FormatException('Invalid artwork source');
        }
      }
    }
    return NetflixTitle(json, category);
  }
  String get id => json['id'];
  String get originalTitle => json['title'];
  String get title => stringValue(metadata['local_title'], originalTitle);
  String? get season => json['season'] is String ? json['season'] : null;
  String? get seasonLabel {
    var value = season;
    if (value == null) return null;
    if (value.startsWith('$originalTitle:')) {
      value = value.substring(originalTitle.length + 1).trim();
    }
    if (value == 'Limited Series') return '리미티드 시리즈';
    final match = RegExp(r'^(Season|Part) (\d+)$').firstMatch(value);
    return match == null
        ? value
        : '${match[1] == 'Season' ? '시즌' : '파트'} ${match[2]}';
  }

  int get rank => json['rank'];
  int? get previousRank => json['previous_rank'];
  int get weeks => json['weeks_in_top10'];
  Json get metadata => json['metadata'] is Map
      ? Map<String, dynamic>.from(json['metadata'])
      : {};
  String get synopsis => stringValue(metadata['synopsis']);
  String get kind => stringValue(metadata['kind']);
  String get runtime => stringValue(metadata['runtime']);
  String get cast => stringValue(metadata['cast']);
  Uri? get image => safeLink(metadata['image_url']);
  Uri get source =>
      safeLink(metadata['source_url']) ??
      Uri.parse('$netflixChartUrl/${category == 'TV' ? 'tv' : 'films'}');
  Uri get watch => safeLink(metadata['watch_url']) ?? source;
  String movement(bool comparable) {
    if (!comparable) return '이전 주 비교 자료 없음';
    if (previousRank != null) {
      final difference = previousRank! - rank;
      return difference > 0
          ? '↑ $difference'
          : difference < 0
          ? '↓ ${-difference}'
          : '순위 유지';
    }
    return weeks == 1 ? '첫 진입' : '재진입';
  }
}

class NetflixWeek {
  NetflixWeek(this.end, this.charts, this.comparable);
  final DateTime end;
  final Map<String, List<NetflixTitle>> charts;
  final bool comparable;
  DateTime get start => end.subtract(const Duration(days: 6));
  String get key => end.toIso8601String().substring(0, 10);
  String get label =>
      '${start.year}.${start.month}.${start.day} – ${end.month}.${end.day}';
  factory NetflixWeek.fromJson(Json raw) {
    final end = chartDate(raw['week']);
    if (raw['charts'] is! Map || raw['previous_available'] is! bool) {
      throw const FormatException('Missing charts');
    }
    final charts = <String, List<NetflixTitle>>{};
    for (final category in ['TV', 'Films']) {
      final items = raw['charts'][category];
      if (items is! List || items.length != 10) {
        throw const FormatException('Incomplete Top 10');
      }
      final titles = items
          .map(
            (i) =>
                NetflixTitle.fromJson(Map<String, dynamic>.from(i), category),
          )
          .toList();
      if (titles.map((t) => t.id).toSet().length != 10 ||
          titles.indexed.any((v) => v.$2.rank != v.$1 + 1)) {
        throw const FormatException('Duplicate or unordered ranks');
      }
      charts[category] = titles;
    }
    return NetflixWeek(end, charts, raw['previous_available']);
  }
}

class NetflixFeed {
  NetflixFeed(this.json, this.weeks, this.fetchedAt);
  final Json json;
  final List<NetflixWeek> weeks;
  final DateTime fetchedAt;
  factory NetflixFeed.decode(String encoded) {
    final raw = jsonDecode(encoded);
    if (raw is! Map ||
        raw['schema_version'] != 1 ||
        raw['country'] != 'KR' ||
        raw['source_url'] != netflixDataUrl ||
        raw['chart_url'] != netflixChartUrl ||
        raw['weeks'] is! List ||
        (raw['weeks'] as List).isEmpty ||
        (raw['weeks'] as List).length > 4) {
      throw const FormatException('Invalid Netflix source');
    }
    final weeks = (raw['weeks'] as List)
        .map((w) => NetflixWeek.fromJson(Map<String, dynamic>.from(w)))
        .toList();
    final fetched = DateTime.parse(raw['fetched_at'] as String).toUtc();
    if (fetched.isBefore(weeks.first.end) ||
        weeks.indexed.any(
          (v) => v.$1 > 0 && !weeks[v.$1 - 1].end.isAfter(v.$2.end),
        )) {
      throw const FormatException('Invalid chart chronology');
    }
    return NetflixFeed(Map<String, dynamic>.from(raw), weeks, fetched);
  }
  bool stale(DateTime now) =>
      now.toUtc().difference(weeks.first.end) > const Duration(days: 14);
}
