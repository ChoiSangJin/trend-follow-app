import 'dart:convert';
import 'briefing.dart';

Uri? animeLink(dynamic value) {
  final uri = safeLink(value);
  return uri != null && uri.host == 'anilist.co' ? uri : null;
}

class AnimeTitle {
  AnimeTitle(this.json);
  final Json json;
  factory AnimeTitle.fromJson(Json raw) {
    if (raw['id'] is! int ||
        raw['id'] < 1 ||
        stringValue(raw['title']).isEmpty ||
        animeLink(raw['url'])?.path != '/anime/${raw['id']}' ||
        raw['airing'] is! bool ||
        raw['genres'] is! List ||
        (raw['score'] != null &&
            (raw['score'] is! num ||
                !(raw['score'] as num).isFinite ||
                raw['score'] < 0 ||
                raw['score'] > 100)) ||
        (raw['position'] != null &&
            (raw['position'] is! int ||
                raw['position'] < 1 ||
                raw['position'] > 10))) {
      throw const FormatException('Invalid anime title');
    }
    for (final key in ['scored_by', 'members', 'episodes']) {
      if (raw[key] != null && (raw[key] is! int || raw[key] < 0)) {
        throw const FormatException('Invalid anime count');
      }
    }
    if (raw['image_url'] != null &&
        ![
          's4.anilist.co',
          's3.anilist.co',
        ].contains(safeLink(raw['image_url'])?.host)) {
      throw const FormatException('Invalid anime artwork');
    }
    return AnimeTitle(raw);
  }
  int get id => json['id'];
  String get title => json['title'];
  String get original => stringValue(json['original_title']);
  String get japanese => stringValue(json['japanese_title']);
  String get synopsis => stringValue(json['synopsis']);
  String get format => stringValue(json['format']);
  num? get score => json['score'];
  int? get position => json['position'];
  int? get scoredBy => json['scored_by'];
  int? get members => json['members'];
  int? get episodes => json['episodes'];
  bool get airing => json['airing'];
  List<String> get genres =>
      (json['genres'] as List).whereType<String>().toList();
  Uri get url => animeLink(json['url'])!;
  Uri? get image => safeLink(json['image_url']);
}

class AnimeNews {
  AnimeNews(this.json, this.publishedAt);
  final Json json;
  final DateTime publishedAt;
  factory AnimeNews.fromJson(Json raw, DateTime fetched) {
    final date = DateTime.parse(raw['published_at'] as String).toUtc();
    if (stringValue(raw['title']).isEmpty ||
        safeLink(raw['url'])?.host != 'www.animenewsnetwork.com' ||
        raw['source'] != 'Anime News Network' ||
        date.isAfter(fetched) ||
        fetched.difference(date) > const Duration(days: 90)) {
      throw const FormatException('Invalid anime news');
    }
    return AnimeNews(raw, date);
  }
  String get title => json['title'];
  String get excerpt => stringValue(json['excerpt']);
  Uri get url => safeLink(json['url'])!;
}

class AnimeUpdate {
  AnimeUpdate(this.json, this.airingAt);
  final Json json;
  final DateTime? airingAt;
  factory AnimeUpdate.fromJson(Json raw, Set<int> ids, DateTime fetched) {
    final url = safeLink(raw['url']);
    final kind = raw['kind'];
    if (!ids.contains(raw['anime_id']) ||
        stringValue(raw['title']).isEmpty ||
        stringValue(raw['anime_title']).isEmpty ||
        url == null ||
        !['airing', 'trailer'].contains(kind)) {
      throw const FormatException('Invalid anime update');
    }
    DateTime? airing;
    if (kind == 'airing') {
      airing = DateTime.parse(raw['airing_at'] as String).toUtc();
      if (animeLink(raw['url'])?.path != '/anime/${raw['anime_id']}' ||
          airing.isBefore(fetched) ||
          airing.difference(fetched) > const Duration(days: 14)) {
        throw const FormatException('Invalid airing schedule');
      }
    } else if (url.host != 'www.youtube.com' ||
        url.path != '/watch' ||
        !RegExp(
          r'^[A-Za-z0-9_-]{11}$',
        ).hasMatch(url.queryParameters['v'] ?? '')) {
      throw const FormatException('Invalid trailer');
    }
    return AnimeUpdate(raw, airing);
  }
  String get title => json['title'];
  String get animeTitle => json['anime_title'];
  Uri get url => safeLink(json['url'])!;
}

class AnimeFeed {
  AnimeFeed(
    this.fetchedAt,
    this.year,
    this.season,
    this.trending,
    this.seasonal,
    this.news,
    this.updates,
    this.newsAvailable,
  );
  final DateTime fetchedAt;
  final int year;
  final String season;
  final List<AnimeTitle> trending, seasonal;
  final List<AnimeNews> news;
  final List<AnimeUpdate> updates;
  final bool newsAvailable;
  factory AnimeFeed.decode(String encoded) {
    final raw = jsonDecode(encoded);
    if (raw is! Map ||
        raw['schema_version'] != 1 ||
        raw['source_url'] != 'https://anilist.co' ||
        raw['source'] != 'AniList' ||
        raw['api_url'] != 'https://graphql.anilist.co' ||
        raw['rank_basis'] != 'trending' ||
        raw['season_year'] is! int ||
        raw['season_year'] < 2000 ||
        !['winter', 'spring', 'summer', 'fall'].contains(raw['season']) ||
        raw['trending'] is! List ||
        raw['seasonal'] is! List ||
        raw['news'] is! List ||
        raw['updates'] is! List ||
        raw['news_available'] is! bool) {
      throw const FormatException('Invalid anime feed');
    }
    final fetched = DateTime.parse(raw['fetched_at'] as String).toUtc();
    final local = fetched.add(const Duration(hours: 9));
    if (raw['season_year'] != local.year ||
        raw['season'] !=
            ['winter', 'spring', 'summer', 'fall'][(local.month - 1) ~/ 3]) {
      throw const FormatException('Incorrect anime season');
    }
    List<AnimeTitle> parse(dynamic list, bool ranked) {
      if ((list as List).isEmpty || list.length > 10) {
        throw const FormatException('Invalid anime list size');
      }
      final items = list
          .map((v) => AnimeTitle.fromJson(Map<String, dynamic>.from(v)))
          .toList();
      if (items.map((i) => i.id).toSet().length != items.length ||
          (ranked && items.any((i) => !i.airing || i.position == null)) ||
          (!ranked &&
              items.any(
                (i) =>
                    i.json['year'] != raw['season_year'] ||
                    i.json['season'] != raw['season'],
              ))) {
        throw const FormatException('Inconsistent anime list');
      }
      if (ranked) {
        for (var i = 1; i < items.length; i++) {
          if (items[i].position! <= items[i - 1].position!) {
            throw const FormatException('Unordered anime ranking');
          }
        }
      }
      return items;
    }

    final trending = parse(raw['trending'], true),
        seasonal = parse(raw['seasonal'], false);
    final ids = {...trending.map((i) => i.id), ...seasonal.map((i) => i.id)};
    final articles = (raw['news'] as List)
        .map((n) => AnimeNews.fromJson(Map<String, dynamic>.from(n), fetched))
        .toList();
    final updates = (raw['updates'] as List)
        .map(
          (n) =>
              AnimeUpdate.fromJson(Map<String, dynamic>.from(n), ids, fetched),
        )
        .toList();
    if (articles.length > 15 ||
        updates.length > 40 ||
        (!raw['news_available'] && articles.isNotEmpty) ||
        articles.map((n) => n.url.toString()).toSet().length !=
            articles.length) {
      throw const FormatException('Invalid anime update list');
    }
    return AnimeFeed(
      fetched,
      raw['season_year'],
      raw['season'],
      trending,
      seasonal,
      articles,
      updates,
      raw['news_available'],
    );
  }
  String get seasonLabel =>
      '$year년 ${{'winter': '겨울', 'spring': '봄', 'summer': '여름', 'fall': '가을'}[season]} 분기';
  bool stale(DateTime now) =>
      now.toUtc().difference(fetchedAt) > const Duration(hours: 48);
}

String animeDate(DateTime value) {
  final d = value.toUtc().add(const Duration(hours: 9));
  return '${d.year}.${d.month}.${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} KST';
}
