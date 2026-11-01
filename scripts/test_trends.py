import unittest
from datetime import timedelta
from build_trends import build_trends
from collect_briefing import TOPICS, candidates
from test_briefing import NOW, article, rss

CATEGORY = '문화·예술'
ENDINGS = ['빛과 공간으로 만나는 작품 세계', '색채로 펼치는 유럽 회화의 장면',
           '자연과 정원이 품은 인상주의', '붓질 너머 감상하는 시간 여행', '새로운 시선으로 풀어낸 빛의 순간']


def report(age, number, origin=None):
    item = article('국립미술관 모네 특별전 '+ENDINGS[number % len(ENDINGS)], f'publisher{number}.kr', age, f'r{number}')
    return {**item, 'category': CATEGORY, 'evidence': 'headline', 'opener': '전시 보러 가실래요?',
            'context': '원문을 확인하세요.', 'why_now': '관측된 기사', 'origin_group': origin or item['origin_group']}


def previous(snapshots=None):
    return {'schema_version': 1, 'region': 'KR', 'articles': [], 'snapshots': snapshots if snapshots is not None else
            [{'at': (NOW-timedelta(hours=h)).isoformat(), 'categories': [CATEGORY]} for h in range(48, 0, -6)]}


class TrendsTests(unittest.TestCase):
    def build(self, reports, history=None, available=None):
        return build_trends(reports, history, NOW, TOPICS, [CATEGORY] if available is None else available)

    def test_initial_observation_never_claims_growth_from_backfilled_headlines(self):
        feed, history = self.build([report(age,i) for i,age in enumerate([36,30,6,4,2])])
        item=feed['cards'][0]
        self.assertEqual(item['daily_sources'],[0,2,3])
        self.assertEqual(item['signal'],'collecting')
        self.assertIsNone(item['growth_percent'])
        self.assertFalse(item['comparison_ready'])
        self.assertEqual(feed['snapshot_count'],1)
        self.assertEqual(len(history['articles']),5)

    def test_continuous_history_compares_equal_windows_with_a_real_baseline(self):
        feed,_=self.build([report(age,i) for i,age in enumerate([36,30,6,4,2])],previous())
        item=feed['cards'][0]
        self.assertEqual(item['source_groups'],5)
        self.assertEqual(item['tracking_hours'],48)
        self.assertEqual(item['signal'],'growing')
        self.assertEqual(item['growth_percent'],50)
        self.assertTrue(item['comparison_ready'])

    def test_zero_baseline_is_newly_observed_not_infinite_growth(self):
        feed,_=self.build([report(3,0),report(2,1)],previous())
        self.assertEqual(feed['cards'][0]['signal'],'new')
        self.assertIsNone(feed['cards'][0]['growth_percent'])

    def test_fast_reruns_and_collection_gaps_cannot_manufacture_history(self):
        reports=[report(age,i) for i,age in enumerate([36,30,6,4,2])]
        burst=[{'at':(NOW-timedelta(seconds=s)).isoformat(),'categories':[CATEGORY]} for s in range(100,0,-1)]
        for history in [previous(burst),previous([{'at':(NOW-timedelta(hours=48)).isoformat(),'categories':[CATEGORY]}]),previous()]:
            feed,_=self.build(reports,history,available=[] if history==previous() else None)
            self.assertFalse(feed['cards'][0]['comparison_ready'])
            self.assertEqual(feed['cards'][0]['signal'],'collecting')

    def test_duplicate_urls_publishers_and_wire_copies_do_not_add_growth_votes(self):
        reports=[report(30,0),report(29,1),report(3,2,origin='publisher0.kr')]
        reports += [{**reports[-1],'id':f'copy{i}','source_url':f'https://news.google.com/rss/articles/copy{i}', 'origin_group':f'copy{i}.kr'} for i in range(30)]
        feed,history=self.build(reports+reports,previous())
        item=feed['cards'][0]
        self.assertEqual(item['source_groups'],2)
        self.assertEqual(item['daily_sources'],[0,2,1])
        self.assertEqual(item['signal'],'steady')
        self.assertEqual(len(history['articles']),33)

    def test_expiration_future_and_unsafe_urls_are_excluded_and_boundaries_do_not_overlap(self):
        reports=[report(age,i) for i,age in enumerate([72,48,24,0])]
        reports += [report(73,5),report(-1,6),{**report(2,7),'source_url':'http://unsafe.example'}]
        feed,history=self.build(reports)
        self.assertEqual(len(history['articles']),4)
        self.assertEqual(feed['cards'][0]['daily_sources'],[2,1,1])
        stale={**previous(), 'articles':[report(80,0)]}
        feed,history=self.build([],stale)
        self.assertEqual(feed['cards'],[])
        self.assertEqual(history['articles'],[])

    def test_sample_cap_interrupts_comparison_history(self):
        history=previous()
        history['snapshots'][4]['truncated_categories']=[CATEGORY]
        feed,_=self.build([report(age,i) for i,age in enumerate([36,30,6,4,2])],history)
        self.assertFalse(feed['cards'][0]['comparison_ready'])
        self.assertEqual(feed['cards'][0]['signal'],'collecting')

    def test_previous_observations_persist_without_double_counting(self):
        _,history=self.build([report(30,0),report(29,1)])
        feed,again=self.build([report(30,0),report(2,2)],history)
        self.assertEqual(feed['cards'][0]['source_groups'],3)
        self.assertEqual(len(again['articles']),3)
        self.assertEqual(feed['snapshot_count'],1)

    def test_trends_accept_under_six_hour_articles_without_changing_briefing_window(self):
        payload=rss([('국립미술관 모네 특별전 개막 안내','yna.co.kr',1,'fresh','')])
        self.assertEqual(candidates(payload,CATEGORY,'질문','맥락',NOW),[])
        self.assertEqual(len(candidates(payload,CATEGORY,'질문','맥락',NOW,minimum_age_hours=0)),1)

if __name__=='__main__':unittest.main()
