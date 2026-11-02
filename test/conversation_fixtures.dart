import 'dart:io';
import 'package:malmun/data/briefing.dart';
import 'package:malmun/data/conversation.dart';
import 'fixtures.dart';

GuideCatalog realCatalog() => GuideCatalog.decode(
  File('assets/conversation_guides.json').readAsStringSync(),
);
Json coachedTopic(int i, String category, String title) {
  final coverage = coverageJson(i);
  final sources = (coverage['sources'] as List)
      .map(
        (s) => {
          ...s as Map,
          'headline': s['name'] == '한국경제' ? title : '$title — 다른 관점의 보도',
        },
      )
      .toList();
  return {
    ...topicJson(i),
    'category': category,
    'title': title,
    'summary': title,
    'coverage': {...coverage, 'sources': sources},
  };
}

Json coachedFeed() => {
  ...feedJson(),
  'cards': [
    coachedTopic(1, '문화·예술', '국립미술관 모네 특별전 개막'),
    coachedTopic(2, '스포츠', '이강인 축구 경기 골대 불운에도 팀 7연승'),
    coachedTopic(3, '경제·주식', '코스피 미국 증시 충격에 3% 급락'),
    coachedTopic(4, '기술·과학', '행안부 업무망 AI 검색 기능 도입'),
    coachedTopic(5, '연예', '엔하이픈 신곡 앨범 발매 컴백'),
  ],
};
DateTime coachNow() => DateTime.utc(2026, 11, 1, 12);
