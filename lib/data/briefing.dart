import 'dart:convert';

typedef Json = Map<String, dynamic>;
const topicCategories = ['문화·예술', '연예', '스포츠', '기술·과학', '사회', '경제·주식', '세계뉴스'];
String stringValue(dynamic value, [String fallback = '']) =>
    value is String && value.trim().isNotEmpty ? value.trim() : fallback;

Uri? safeLink(dynamic value) {
  final uri = Uri.tryParse(stringValue(value));
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

class CoverageSource {
  const CoverageSource(
    this.name,
    this.group,
    this.url,
    this.publishedAt, [
    this.headline,
  ]);
  factory CoverageSource.fromJson(Json json) {
    final url = safeLink(json['url']);
    final date = DateTime.tryParse(stringValue(json['published_at']));
    if (stringValue(json['name']).isEmpty ||
        stringValue(json['group']).isEmpty ||
        url == null ||
        date == null) {
      throw const FormatException('Invalid coverage source');
    }
    final headline = json['headline'];
    if (headline != null && (headline is! String || headline.trim().isEmpty)) {
      throw const FormatException('Invalid source headline');
    }
    return CoverageSource(
      json['name'],
      json['group'],
      url,
      date,
      headline as String?,
    );
  }
  final String name, group;
  final Uri url;
  final DateTime publishedAt;
  final String? headline;
  Json toJson() => {
    'name': name,
    'group': group,
    'url': url.toString(),
    'published_at': publishedAt.toIso8601String(),
    if (headline != null) 'headline': headline,
  };
}

class Coverage {
  const Coverage({
    required this.groups,
    required this.reports,
    required this.hours,
    required this.first,
    required this.last,
    required this.firstUrl,
    required this.lastUrl,
    required this.sources,
  });
  factory Coverage.fromJson(Json json) {
    final groups = json['source_groups'];
    final reports = json['report_count'];
    final hours = json['span_hours'];
    final first = DateTime.tryParse(stringValue(json['first_report_at']));
    final last = DateTime.tryParse(stringValue(json['last_report_at']));
    final firstUrl = safeLink(json['first_report_url']);
    final lastUrl = safeLink(json['last_report_url']);
    if (groups is! int ||
        groups < 1 ||
        groups > 8 ||
        reports is! int ||
        reports < groups ||
        hours is! num ||
        !hours.isFinite ||
        hours < 0 ||
        hours > 72 ||
        first == null ||
        last == null ||
        first.isAfter(last) ||
        firstUrl == null ||
        lastUrl == null ||
        json['sources'] is! List) {
      throw const FormatException('Invalid coverage measurements');
    }
    final sources = (json['sources'] as List).map((item) {
      if (item is! Map) throw const FormatException('Invalid source');
      return CoverageSource.fromJson(Map<String, dynamic>.from(item));
    }).toList();
    if (sources.length != groups ||
        sources.map((s) => s.group).toSet().length != groups ||
        sources.any(
          (s) => s.publishedAt.isBefore(first) || s.publishedAt.isAfter(last),
        ) ||
        (last.difference(first).inSeconds / 3600 - hours).abs() > .11) {
      throw const FormatException(
        'Coverage evidence does not match measurements',
      );
    }
    return Coverage(
      groups: groups,
      reports: reports,
      hours: hours.toDouble(),
      first: first,
      last: last,
      firstUrl: firstUrl,
      lastUrl: lastUrl,
      sources: sources,
    );
  }
  final int groups, reports;
  final double hours;
  final DateTime first, last;
  final Uri firstUrl, lastUrl;
  final List<CoverageSource> sources;
  bool get singleSource => groups == 1;
  String get label =>
      singleSource ? '단일 출처 · 인기 확인 전' : '출처 $groups그룹 · $spanLabel에 걸친 보도';
  String get spanLabel => hours < 1 ? '1시간 미만' : '${hours.floor()}시간';
  Json toJson() => {
    'source_groups': groups,
    'report_count': reports,
    'span_hours': hours,
    'first_report_at': first.toIso8601String(),
    'last_report_at': last.toIso8601String(),
    'first_report_url': firstUrl.toString(),
    'last_report_url': lastUrl.toString(),
    'sources': sources.map((s) => s.toJson()).toList(),
  };
}

class Topic {
  const Topic({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    required this.whyNow,
    required this.opener,
    required this.context,
    required this.source,
    required this.evidence,
    this.url,
    this.publishedAt,
    this.coverage,
  });

  factory Topic.fromJson(Json json) {
    for (final key in [
      'id',
      'category',
      'title',
      'summary',
      'why_now',
      'opener',
      'context',
      'source',
      'evidence',
    ]) {
      if (stringValue(json[key]).isEmpty) {
        throw FormatException('Missing topic field: $key');
      }
    }
    final evidence = stringValue(json['evidence']);
    final url = safeLink(json['source_url']);
    final published = DateTime.tryParse(stringValue(json['published_at']));
    if (evidence != 'practice' &&
        (evidence != 'headline' || url == null || published == null)) {
      throw const FormatException('A news topic requires a dated HTTPS source');
    }
    final coverage = json['coverage'] is Map
        ? Coverage.fromJson(Map<String, dynamic>.from(json['coverage']))
        : null;
    if (coverage != null &&
        (published == null ||
            published.isBefore(coverage.first) ||
            published.isAfter(coverage.last) ||
            !coverage.sources.any(
              (item) =>
                  item.url == url &&
                  item.name == json['source'] &&
                  item.publishedAt.isAtSameMomentAs(published),
            ))) {
      throw const FormatException(
        'Primary headline does not match coverage sources',
      );
    }
    return Topic(
      id: json['id'],
      category: json['category'],
      title: json['title'],
      summary: json['summary'],
      whyNow: json['why_now'],
      opener: json['opener'],
      context: json['context'],
      source: json['source'],
      evidence: evidence,
      url: url,
      publishedAt: published,
      coverage: coverage,
    );
  }

  final String id,
      category,
      title,
      summary,
      whyNow,
      opener,
      context,
      source,
      evidence;
  final Uri? url;
  final DateTime? publishedAt;
  final Coverage? coverage;
  bool get isPractice => evidence == 'practice';
  Json toJson() => {
    'id': id,
    'category': category,
    'title': title,
    'summary': summary,
    'why_now': whyNow,
    'opener': opener,
    'context': context,
    'source': source,
    'evidence': evidence,
    'source_url': url?.toString(),
    'published_at': publishedAt?.toIso8601String(),
    if (coverage != null) 'coverage': coverage!.toJson(),
  };
}

class Briefing {
  const Briefing({required this.topics, this.updatedAt, this.practice = false});
  factory Briefing.fromJson(Json json) {
    if (json['schema_version'] != 5 ||
        json['region'] != 'KR' ||
        json['cards'] is! List) {
      throw const FormatException('Unsupported briefing');
    }
    final practice = json['edition'] == 'practice';
    if (!practice && json['edition'] != 'daily') {
      throw const FormatException('Invalid edition');
    }
    final topics = (json['cards'] as List).map((item) {
      if (item is! Map) throw const FormatException('Invalid topic');
      return Topic.fromJson(Map<String, dynamic>.from(item));
    }).toList();
    final date = DateTime.tryParse(stringValue(json['updated_at']));
    if (topics.isEmpty ||
        topics.length > 14 ||
        topics.map((t) => t.id).toSet().length != topics.length ||
        topics.any(
          (t) =>
              t.isPractice != practice ||
              !topicCategories.contains(t.category) ||
              (!practice && t.coverage == null) ||
              (!practice &&
                  t.coverage?.singleSource == true &&
                  !['문화·예술', '스포츠'].contains(t.category)) ||
              (practice && t.coverage != null),
        ) ||
        topicCategories.any(
          (category) => topics.where((t) => t.category == category).length > 2,
        ) ||
        (!practice && date == null)) {
      throw const FormatException('Invalid briefing content');
    }
    return Briefing(topics: topics, updatedAt: date, practice: practice);
  }
  factory Briefing.decode(String value) {
    final json = jsonDecode(value);
    if (json is! Map) throw const FormatException('Invalid JSON envelope');
    return Briefing.fromJson(Map<String, dynamic>.from(json));
  }
  final List<Topic> topics;
  final DateTime? updatedAt;
  final bool practice;
}

String koreaDate(DateTime date) {
  final kst = date.toUtc().add(const Duration(hours: 9));
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${kst.month}.${pad(kst.day)} ${pad(kst.hour)}:${pad(kst.minute)}';
}
