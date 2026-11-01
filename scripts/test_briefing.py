import json
import os
import tempfile
import unittest
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError
import collect_briefing as collector
from collect_briefing import candidates, build_briefing, legacy_briefing, legacy_v3, TOPICS
from rank_topics import rank, clusters, independent_reports, related, corroboration_searches

NOW = datetime(2026, 11, 1, 12, tzinfo=timezone.utc)


def rss(items=None, language='ko', edition='KR:ko'):
    if items is None:
        items = [('국립미술관 모네 전시 개막 안내', 'yna.co.kr', 12, 'a', '')]
    body = []
    for title, domain, age, key, description in items:
        date = (NOW-timedelta(hours=age)).strftime('%a, %d %b %Y %H:%M:%S GMT')
        body.append(f'<item><title>{title} - {domain}</title><link>https://news.google.com/rss/articles/{key}</link><source url="https://{domain}">{domain}</source><pubDate>{date}</pubDate><description>{description}</description></item>')
    return ('<rss><channel><language>'+language+'</language><link>https://news.google.com/search?ceid='+edition+'</link>'+''.join(body)+'</channel></rss>').encode()


# Different wording, same named event; not identical syndicated headlines.
PAIRS = [
 [('국립미술관 모네 특별전 개막 안내', '모네 특별전 국립미술관에서 만나는 빛과 그림'),
  ('김영하 문학상 신간 소설 출간 소식', '문학상 김영하 신간 소설 독자와 만남')],
 [('아이유 별빛 신곡 앨범 공개 소식', '별빛 앨범 아이유 신곡 발매 음악의 변화'),
  ('김혜수 넷플릭스 봄날 드라마 공개', '봄날 드라마 김혜수 넷플릭스에서 만나는 연기')],
 [('수원컵 축구 결승 대회 개막 소식', '축구 수원컵 결승 대회 선수들의 도전'),
  ('이강인 마드리드 아틀레티코 경기 골 기록', '마드리드 이강인 아틀레티코 경기 활약 평가')],
 [('누리호 위성 우주 탐사 발사 결과 공개', '우주 누리호 위성 탐사 발사에서 찾은 성과'),
  ('오픈AI 오로라 로봇 기술 신기능 공개', '오로라 로봇 오픈AI 기술 사용법과 변화')],
 [('서울 지하철 교통 요금 개편 시행', '교통 서울 지하철 요금 개편 시민의 변화'),
  ('부산 청년 주거 복지 지원 신청 변경', '청년 부산 주거 복지 지원 신청 일정 안내')],
 [('연준 기준금리 인하 미국 증시 변화', '미국 연준 기준금리 인하 경제 영향 분석'),
  ('통계청 소비자물가 상승 환율 지표 발표', '소비자물가 통계청 상승 환율 지표 해석')],
 [('유엔 제네바 기후 협상 정상회의 개막', '제네바 유엔 기후 협상 정상회의 합의 전망'),
  ('유럽 브뤼셀 국제 보건 외교 협약 발표', '브뤼셀 유럽 국제 보건 외교 협약의 배경')],
]


def all_feeds():
    result = []
    for i, pairs in enumerate(PAIRS):
        items = []
        for j, pair in enumerate(pairs):
            items += [(pair[0], 'yna.co.kr', 36, f'{i}-{j}-a', ''),
                      (pair[1], 'hankyung.com', 12, f'{i}-{j}-b', '')]
        result.append(rss(items))
    return result


def article(title, domain='one.kr', age=24, key=None):
    key = key or domain+title
    return dict(id=key, title=title, summary=title, source=domain, source_url='https://news.google.com/rss/articles/'+str(abs(hash(key))), origin_group=domain,
                published_at=(NOW-timedelta(hours=age)).isoformat().replace('+00:00','Z'))


class SelectionTests(unittest.TestCase):
    def parse(self, payload, category='문화·예술'):
        return candidates(payload,category,'질문','맥락',NOW)

    def test_6_to_72_hour_window_is_enforced_including_boundaries(self):
        for age, expected in [(5.9,0),(6,1),(72,1),(72.1,0),(-1,0)]:
            self.assertEqual(len(self.parse(rss([('국립 미술관 모네 전시 개막','yna.co.kr',age,'a','')]))),expected)

    def test_wrong_edition_or_language_rejected(self):
        for payload in (rss(edition='US:en'),rss(language='en'),rss(edition='HK:zh')):
            with self.assertRaises(ValueError): self.parse(payload)

    def test_unknown_publisher_rejected_and_wire_origin_is_shared(self):
        self.assertEqual(self.parse(rss([('국립 미술관 모네 전시 개막','unverified.example',12,'a','')])),[])
        reports=self.parse(rss([('국립미술관 모네 전시 개막 안내','yna.co.kr',20,'a',''),
                               ('모네 특별전 국립미술관 빛과 그림','hankyung.com',10,'b','(서울=연합뉴스)')]))
        self.assertEqual(len({a['origin_group'] for a in reports}),1)
        self.assertEqual(rank(reports,'문화·예술','질문','맥락'),[])
        for credit in ['뉴스1 기사 전재', '연합뉴스 기사 전재', '뉴시스 기사 전재']:
            item = self.parse(rss([('국립미술관 모네 전시 개막 안내','hankyung.com',10,'c',credit)]))[0]
            self.assertEqual(item['origin_group'], 'wire:'+credit.split()[0])

    def test_new_economy_and_global_fields_allow_relevant_public_policy(self):
        for category,title in [('경제·주식','연준 금리 인하 코스피 증시 변화'),('세계뉴스','미국 대통령 국제 무역 관세 협상')]:
            self.assertEqual(len(self.parse(rss([(title,'yna.co.kr',12,'a','')]),category)),1)
        self.assertEqual(self.parse(rss([('무료 리딩방 수익보장 종목추천','yna.co.kr',12,'a','')]),'경제·주식'),[])

    def test_irrelevant_entertainment_finance_and_council_agenda_rejected(self):
        for category,title in [('연예','머스크 AI 오디세이 공개'),('기술·과학','한국투자 10조 펀드 AI 데이터센터'),('사회','시의회 정례회 행정사무감사'),('문화·예술','자동차 전시 카쇼 개막')]:
            self.assertEqual(self.parse(rss([(title,'yna.co.kr',12,'a','')]),category),[])

    def test_multi_publisher_coverage_is_required_not_raw_article_count(self):
        a,b=PAIRS[0][0]
        single=[article(a,'one.kr',30,'a'),article(b,'one.kr',10,'b')]
        self.assertEqual(rank(single,'문화·예술','질문','맥락'),[])
        copies=[article(a,domain,24,domain) for domain in ('a.kr','b.kr','c.kr','d.kr')]
        self.assertEqual(rank(copies,'문화·예술','질문','맥락'),[])
        independent=[article(a,'one.kr',30,'a'),article(b,'two.kr',10,'b')]
        result=rank(independent,'문화·예술','질문','맥락')
        self.assertEqual(len(result),1)
        self.assertEqual(result[0]['coverage']['source_groups'],2)
        self.assertEqual(result[0]['coverage']['span_hours'],20)
        self.assertEqual(len(result[0]['coverage']['sources']),2)

    def test_same_group_and_duplicate_urls_do_not_add_votes(self):
        a,b=PAIRS[0][0]
        reports=[article(a,'same.kr',20,'a'),article(b,'same.kr',12,'b'),article(a,'other.kr',10,'a')]
        self.assertEqual(rank(reports,'문화·예술','질문','맥락'),[])
        for credit in ['뉴스1 기사 전재', '연합뉴스 기사 전재', '뉴시스 기사 전재']:
            item = self.parse(rss([('국립미술관 모네 전시 개막 안내','hankyung.com',10,'c',credit)]))[0]
            self.assertEqual(item['origin_group'], 'wire:'+credit.split()[0])

    def test_real_world_event_headline_variants_do_not_become_two_cards(self):
        for left,right in [
            ('행안부, 공무원 업무망에 AI 웹검색 도입…12월 한글 보고서 작성 지원', "정부 업무망서 인터넷 검색에 보고서 작성도…'온AI' 기능 확대"),
            ('[속보] 한미일 외교장관 “北 완전한 비핵화 의지 재확인”', '한미일 외교장관, G20 계기 美서 회동…한반도 등 논의하나')]:
            self.assertTrue(related(article(left), article(right,'two.kr')))

    def test_followup_searches_distinct_unconfirmed_events(self):
        confirmed=[article(PAIRS[0][0][0]),article(PAIRS[0][0][1],'two.kr')]
        missing=[article(PAIRS[0][1][0],'three.kr'),article('국립극단 햄릿 연극 공연 개막','four.kr')]
        searches=corroboration_searches(confirmed+missing)
        self.assertEqual(len(searches),2)
        self.assertFalse(any('모네' in search for search in searches))

    def test_unrelated_topics_do_not_merge_on_generic_keywords(self):
        self.assertFalse(related(article('서울 버스 요금 교통 제도 변경'),article('부산 교육 지원 제도 변경')))
        self.assertFalse(related(article('오픈AI 오로라 로봇 기술 발표'),article('삼성 스마트폰 배터리 신기능 공개')))

    def test_breadth_then_duration_outweighs_newness(self):
        a,b=PAIRS[0][0];c,d=PAIRS[0][1]
        reports=[article(a,'a.kr',50,'a'),article(b,'b.kr',12,'b'),
                 article(c,'a.kr',9,'c'),article(d,'b.kr',7,'d')]
        result=rank(reports,'문화·예술','질문','맥락')
        self.assertEqual(len(result),2)
        self.assertEqual(result[0]['coverage']['span_hours'],38)
        self.assertEqual(result[1]['coverage']['span_hours'],2)

    def test_fourteen_topics_and_legacy_compatibility(self):
        feed=build_briefing(all_feeds(),NOW)
        self.assertEqual(feed['schema_version'],4)
        self.assertEqual(len(feed['cards']),14)
        self.assertEqual(Counter(c['category'] for c in feed['cards']),{t[0]:2 for t in TOPICS})
        self.assertEqual(len(legacy_v3(feed)['cards']),10)
        self.assertEqual(legacy_v3(feed)['schema_version'],3)
        self.assertEqual(len(legacy_briefing(feed)['cards']),5)
        for topic in feed['cards']:
            self.assertGreaterEqual(topic['coverage']['source_groups'],2)
            self.assertEqual(topic['title'],topic['summary'])

    def test_insufficient_evidence_is_not_padded(self):
        feeds=all_feeds();feeds[0]=None
        self.assertEqual(len(build_briefing(feeds,NOW)['cards']),12)
        with self.assertRaises(ValueError):build_briefing([None]*7,NOW)

    def test_publisher_writes_three_valid_json_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'data').mkdir()
            responses=[]
            for payload in all_feeds():
                response=MagicMock();response.__enter__.return_value.read.return_value=payload;responses.append(response)
            with patch.object(collector,'ROOT',root),patch.object(collector,'urlopen',side_effect=responses) as fetch,patch.object(collector,'datetime') as clock,patch.object(collector.time,'sleep'),patch.dict(os.environ,{'GITHUB_ACTIONS':'false'}):
                clock.now.return_value=NOW;collector.main()
            self.assertIn('/rss/search?', fetch.call_args_list[0].args[0].full_url)
            self.assertIn('/section/topic/ENTERTAINMENT?', fetch.call_args_list[1].args[0].full_url)
            self.assertIn('ceid=KR%3Ako', fetch.call_args_list[1].args[0].full_url)
            for name,schema,limit in [('briefing-v4.json',4,14),('briefing-v3.json',3,10),('briefing.json',2,5)]:
                data=json.loads((root/'data'/name).read_text());self.assertEqual(data['schema_version'],schema);self.assertEqual(len(data['cards']),limit)

    def test_obituaries_and_celebrity_outfits_are_not_sports_or_technology(self):
        for category,title in [('스포츠','배우, 조카 축구 경기 응원 차림 공개'),('기술·과학','[부고] 우주항공청장 모친상')]:
            self.assertEqual(self.parse(rss([(title,'yna.co.kr',12,'a','')]),category),[])

    def test_section_failure_uses_same_korean_keyword_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'data').mkdir()
            response=MagicMock();response.__enter__.return_value.read.return_value=all_feeds()[1]
            denied=HTTPError('https://news.google.com',403,'denied',{},None)
            with patch.object(collector,'ROOT',root),patch.object(collector,'TOPICS',[TOPICS[1]]),patch.object(collector,'urlopen',side_effect=[denied,response]) as fetch,patch.object(collector,'datetime') as clock,patch.object(collector.time,'sleep'),patch.dict(os.environ,{'GITHUB_ACTIONS':'false'}):
                clock.now.return_value=NOW;collector.main()
            self.assertEqual(fetch.call_count,2)
            self.assertIn('/section/topic/ENTERTAINMENT?',fetch.call_args_list[0].args[0].full_url)
            self.assertIn('/rss/search?',fetch.call_args_list[1].args[0].full_url)
            self.assertEqual(len(json.loads((root/'data/briefing-v4.json').read_text())['cards']),2)

    def test_retry_transient_status_once_but_not_denied_access(self):
        response=MagicMock();response.__enter__.return_value.read.return_value=b'ok'
        for status,calls in [(503,2),(403,1)]:
            error=HTTPError('https://news.google.com',status,'error',{},None)
            with patch.object(collector,'urlopen',side_effect=[error,response]) as fetch,patch.object(collector.time,'sleep'):
                if status==503:self.assertEqual(collector.fetch_rss('https://news.google.com'),b'ok')
                else:
                    with self.assertRaises(HTTPError):collector.fetch_rss('https://news.google.com')
                self.assertEqual(fetch.call_count,calls)

    def test_practice_is_not_evidence_backed_news(self):
        data=json.loads((Path(__file__).parents[1]/'assets/practice.json').read_text())
        self.assertEqual(data['edition'],'practice');self.assertEqual(data['schema_version'],4)
        self.assertEqual(Counter(c['category'] for c in data['cards']),{t[0]:2 for t in TOPICS})
        for card in data['cards']:self.assertIsNone(card['published_at']);self.assertNotIn('coverage',card)

if __name__=='__main__':unittest.main()
