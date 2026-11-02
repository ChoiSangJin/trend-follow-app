import 'dart:convert';
import 'dart:io';
import 'package:malmun/data/anime.dart';

Map<String, dynamic> animeJson() {
  final raw =
      jsonDecode(File('assets/anime.json').readAsStringSync())
          as Map<String, dynamic>;
  for (final section in ['trending', 'seasonal']) {
    var n = 0;
    for (final item in raw[section]) {
      n++;
      item['image_url'] = null;
      item['title'] = section == 'trending'
          ? 'Test Anime $n'
          : 'Season Anime $n';
    }
  }
  return raw;
}

AnimeFeed animeFeed() => AnimeFeed.decode(jsonEncode(animeJson()));
