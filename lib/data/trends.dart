typedef Json = Map<String, dynamic>;

String text(dynamic value, [String fallback = '']) =>
    value is String && value.trim().isNotEmpty ? value.trim() : fallback;

List<T> items<T>(dynamic value, T Function(Json) parse) => value is List
    ? value.whereType<Json>().map(parse).toList(growable: false)
    : <T>[];

Uri? webUri(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty && uri.userInfo.isEmpty
      ? uri
      : null;
}

class TrendFeed {
  const TrendFeed({this.updatedAt, this.isDemo = false, this.memes = const [],
    this.places = const [], this.keywords = const []});

  factory TrendFeed.fromJson(Json json) {
    final rawCategories = json['categories'];
    if (rawCategories is! Map ||
        rawCategories.keys.any((key) => key is! String)) {
      throw const FormatException('categories 객체가 없습니다.');
    }
    final categories = Map<String, dynamic>.from(rawCategories);
    for (final name in ['memes', 'hotplaces', 'keywords']) {
      if (categories[name] != null && categories[name] is! List) {
        throw FormatException('$name 목록 형식이 올바르지 않습니다.');
      }
    }
    return TrendFeed(
      updatedAt: DateTime.tryParse(text(json['updated_at'])),
      isDemo: json['is_demo'] == true,
      memes: items(categories['memes'], Meme.fromJson),
      places: items(categories['hotplaces'], HotPlace.fromJson),
      keywords: items(categories['keywords'], Keyword.fromJson)
        ..sort((a, b) => a.rank.compareTo(b.rank)),
    );
  }

  final DateTime? updatedAt;
  final bool isDemo;
  final List<Meme> memes;
  final List<HotPlace> places;
  final List<Keyword> keywords;
}

class Meme {
  const Meme({required this.id, required this.title, required this.description,
    required this.source, required this.sourceUrl, required this.tags});
  factory Meme.fromJson(Json json) => Meme(
    id: text(json['id']), title: text(json['title'], '제목 없는 밈'),
    description: text(json['description'], '아직 설명이 없습니다.'),
    source: text(json['source'], '출처 미제공'),
    sourceUrl: webUri(text(json['source_url'])),
    tags: json['tags'] is List
      ? (json['tags'] as List).whereType<String>().where((s) => s.trim().isNotEmpty).toList()
      : const [],
  );
  final String id, title, description, source;
  final Uri? sourceUrl;
  final List<String> tags;
}

class HotPlace {
  const HotPlace({required this.id, required this.name, required this.district,
    required this.crowdLevel, required this.age20sRatio, required this.mapQuery,
    required this.source});
  factory HotPlace.fromJson(Json json) => HotPlace(
    id: text(json['id']), name: text(json['name'], '이름 없는 장소'),
    district: text(json['district'], '위치 미제공'),
    crowdLevel: text(json['crowd_level'], '혼잡도 정보 없음'),
    age20sRatio: text(json['age_20s_ratio'], '정보 없음'),
    mapQuery: text(json['map_query'], text(json['name'])),
    source: text(json['source'], '출처 미제공'),
  );
  final String id, name, district, crowdLevel, age20sRatio, mapQuery, source;
}

class Keyword {
  const Keyword({required this.rank, required this.keyword,
    required this.searchVolume, required this.source, this.sourceUrl});
  factory Keyword.fromJson(Json json) => Keyword(
    rank: (int.tryParse('${json['rank']}') ?? 999).clamp(1, 999).toInt(),
    keyword: text(json['keyword'], '키워드 미제공'),
    searchVolume: text(json['search_volume'], '집계 중'),
    source: text(json['source'], '출처 미제공'),
    sourceUrl: webUri(text(json['source_url'])),
  );
  final int rank;
  final String keyword, searchVolume, source;
  final Uri? sourceUrl;
  Uri get searchUri => sourceUrl ?? Uri.https('www.google.com', '/search', {'q': keyword});
}
