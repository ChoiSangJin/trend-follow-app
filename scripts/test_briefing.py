import json
import unittest
import tempfile
from unittest.mock import patch, MagicMock
import collect_briefing as collector
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from collect_briefing import candidates, build_briefing, legacy_briefing, TOPICS

NOW = datetime(2026, 11, 1, 6, tzinfo=timezone.utc)

def rss(title='새로운 미술관 전시가 오늘 개막합니다', date='Sun, 01 Nov 2026 03:00:00 GMT', language='ko', edition='KR:ko', url='https://news.google.com/rss/articles/example'):
    return f'''<rss><channel><language>{language}</language>
<link>https://news.google.com/search?ceid={edition}</link>
<item><title>{title} - 문화신문</title><link>{url}</link>
<source url="https://www.yna.co.kr">문화신문</source><pubDate>{date}</pubDate></item></channel></rss>'''.encode()

def multiple(titles, prefix):
    items=[]
    for i,title in enumerate(titles):
        payload=rss(title=title,url=f'https://news.google.com/rss/articles/{prefix}-{i}').decode()
        items.append(payload[payload.index('<item>'):payload.index('</item>')+7])
    return ('<rss><channel><language>ko</language><link>https://news.google.com/search?ceid=KR:ko</link>'+''.join(items)+'</channel></rss>').encode()

TITLES = [
 ['국립 미술관 전시 개막 안내', '문학상 수상 작가의 신간 출간', '오케스트라 공연 새로운 무대'],
 ['배우들의 새 드라마 시즌 공개', '아이돌 신곡 컴백 무대 첫 방송', '영화관에서 만나는 신작 개봉'],
 ['프로야구 한국시리즈 결승 경기', '여자 배구 대표팀 새로운 시즌', '축구 선수들의 주말 대회 개막'],
 ['우주 탐사선 화성 관측 결과', '새 스마트폰 카메라 기능 발표', '인공지능 서비스 음성 기술 소식'],
 ['대중교통 버스 요금 제도 변경', '공공 도서관 교육 지원 신청', '지역 주민 복지 서비스 안내'],
]
def all_feeds(): return [multiple(titles,i) for i,titles in enumerate(TITLES)]

class BriefingTests(unittest.TestCase):
    def parse(self,payload,category='문화·예술'):
        return candidates(payload,category,'질문','맥락',NOW)

    def test_publisher_writes_readable_new_and_compatible_legacy_json(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'data').mkdir()
            responses=[]
            for payload in all_feeds():
                response=MagicMock();response.__enter__.return_value.read.return_value=payload
                responses.append(response)
            with patch.object(collector,'ROOT',root), patch.object(collector,'urlopen',side_effect=responses), patch.object(collector,'datetime') as clock:
                clock.now.return_value=NOW
                collector.main()
            new=json.loads((root/'data/briefing-v3.json').read_text())
            old=json.loads((root/'data/briefing.json').read_text())
            self.assertEqual(new['schema_version'],3)
            self.assertEqual(len(new['cards']),10)
            self.assertEqual(old['schema_version'],2)
            self.assertEqual(len(old['cards']),5)

    def test_entertainment_includes_public_concerts_and_album_releases(self):
        for title in ('가수 단독 콘서트 개최 소식','아이돌 새 앨범 발매 안내'):
            self.assertEqual(len(self.parse(rss(title=title),'연예')),1)

    def test_science_coverage_does_not_use_education_award_announcements(self):
        self.assertEqual(self.parse(rss(title='정보과학 인재양성 우수학교 공모전 수상자'),'기술·과학'),[])
        self.assertEqual(len(self.parse(rss(title='화성 탐사선 과학 실험 결과 공개'),'기술·과학')),1)

    def test_arts_excludes_trade_exhibitions(self):
        self.assertEqual(self.parse(rss(title='서울클래식카쇼 개막 클래식카 전시와 정책 논의')),[])
        self.assertEqual(len(self.parse(rss(title='국립 미술관 작가 사진전 개막 소식'))),1)

    def test_entertainment_excludes_unrelated_ai_video_criticism(self):
        self.assertEqual(self.parse(rss(title='오디세이 비난한 머스크 AI 오디세이 공개'),'연예'),[])
        self.assertEqual(len(self.parse(rss(title='가수 새 앨범과 신곡 공개 소식'),'연예')),1)

    def test_technology_excludes_fundraising_and_financial_headlines(self):
        for title in ('한국투자 10조 펀드 조성 AI데이터센터 짓는다','앤트로픽 정크 경고 AI 돈줄이 마른다'):
            self.assertEqual(self.parse(rss(title=title),'기술·과학'),[])
        self.assertEqual(len(self.parse(rss(title='새 스마트폰 카메라 신기능 공개'),'기술·과학')),1)

    def test_society_prefers_practical_changes_not_council_agendas(self):
        self.assertEqual(self.parse(rss(title='시의회 정례회 개회 첫 행정사무감사'),'사회'),[])
        self.assertEqual(len(self.parse(rss(title='지역 주민 공공서비스 지원 신청 변경 안내'),'사회')),1)

    def test_two_per_category_ten_total_and_legacy_limit(self):
        feed=build_briefing(all_feeds(),NOW)
        self.assertEqual(feed['schema_version'],3)
        self.assertEqual(len(feed['cards']),10)
        self.assertEqual(Counter(x['category'] for x in feed['cards']), {topic[0]:2 for topic in TOPICS})
        legacy=legacy_briefing(feed)
        self.assertEqual(legacy['schema_version'],2)
        self.assertEqual(len(legacy['cards']),5)
        self.assertEqual(len({x['id'] for x in legacy['cards']}),5)

    def test_partial_feed_does_not_pad_or_steal_other_category_quota(self):
        feeds=all_feeds();feeds[0]=None;feeds[1]=multiple(TITLES[1][:1],1)
        counts=Counter(x['category'] for x in build_briefing(feeds,NOW)['cards'])
        self.assertEqual(counts, {'연예':1,'스포츠':2,'기술·과학':2,'사회':2})

    def test_cross_source_and_category_duplicates_are_removed(self):
        feed=build_briefing([multiple(['새 뮤지컬 영화 신작 공개','새 뮤지컬 영화 신작 공개'],1),multiple(['새 뮤지컬 영화 신작 공개'],2),None,None,None],NOW)
        self.assertEqual(len(feed['cards']),1)

    def test_keeps_facts_and_dated_source_without_invented_summary(self):
        topic=self.parse(rss())[0]
        self.assertEqual(topic['title'],topic['summary'])
        self.assertEqual(topic['evidence'],'headline')
        self.assertIn(topic['title'],topic['opener'])
        self.assertEqual(topic['published_at'],'2026-11-01T03:00:00Z')

    def test_wrong_edition_or_language_rejected(self):
        for payload in (rss(edition='US:en'),rss(language='en'),rss(edition='HK:zh')):
            with self.assertRaises(ValueError): self.parse(payload)

    def test_entertainment_requires_public_releases_not_private_life_rumours(self):
        self.assertEqual(self.parse(rss(title='배우 열애 소식 공개'),'연예'),[])
        self.assertEqual(self.parse(rss(title='헤어질 결심이 소환한 클래식 미장센'),'연예'),[])
        self.assertEqual(len(self.parse(rss(title='새 한국 드라마 시즌 공개 소식'),'연예')),1)

    def test_society_excludes_overseas_event_promotions(self):
        self.assertEqual(self.parse(rss(title='양쯔강 문화 축제 중국 장쑤성에서 개막'),'사회'),[])

    def test_unknown_publishers_are_not_used(self):
        self.assertEqual(self.parse(rss().replace(b'https://www.yna.co.kr',b'https://unverified.example')),[])

    def test_old_future_or_missing_date_rejected(self):
        for date in ('Wed, 01 Oct 2025 00:00:00 GMT','Mon, 02 Nov 2026 00:00:00 GMT',''):
            self.assertEqual(self.parse(rss(date=date)),[])

    def test_sensitive_topics_and_unsafe_sources_rejected(self):
        for title in ('대통령의 새로운 발표와 국회 논란','유명 인사 사망 사건 소식'):
            self.assertEqual(self.parse(rss(title=title)),[])
        for url in ('javascript:alert(1)','https://example.com/story','http://news.google.com/story'):
            self.assertEqual(self.parse(rss(url=url)),[])

    def test_no_valid_news_does_not_produce_fake_daily_edition(self):
        with self.assertRaises(ValueError):build_briefing([None]*len(TOPICS),NOW)

    def test_practice_has_two_per_field_without_fake_news(self):
        feed=json.loads((Path(__file__).parents[1]/'assets/practice.json').read_text())
        self.assertEqual(feed['edition'],'practice')
        self.assertEqual(feed['schema_version'],3)
        self.assertEqual(Counter(c['category'] for c in feed['cards']), {topic[0]:2 for topic in TOPICS})
        for card in feed['cards']:
            self.assertIsNone(card['published_at']);self.assertEqual(card['evidence'],'practice')

if __name__=='__main__':unittest.main()
