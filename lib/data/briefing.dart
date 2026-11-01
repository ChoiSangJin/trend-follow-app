import 'dart:convert';

typedef Json = Map<String, dynamic>;
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
  };
}

class Briefing {
  const Briefing({required this.topics, this.updatedAt, this.practice = false});
  factory Briefing.fromJson(Json json) {
    if (json['schema_version'] != 2 ||
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
        topics.length > 5 ||
        topics.map((t) => t.id).toSet().length != topics.length ||
        topics.any((t) => t.isPractice != practice) ||
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
