"""Build a dated small-talk briefing from recent Korean-edition news headlines.
No LLM credentials, invented article summaries, popularity claims or scraping logins.
"""
import hashlib
import json
import os
import re
import time
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.parse import urlencode, urlparse, parse_qs
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET
from urllib.error import HTTPError
from rank_topics import rank, corroboration_terms, related

ROOT = Path(__file__).resolve().parents[1]
TOPICS = [
    ('문화·예술', '(미술 OR 전시 OR 공연 OR 연극 OR 뮤지컬 OR 문학 OR 신간 OR 클래식)', '요즘 가 보고 싶은 전시나 공연, 읽어 보고 싶은 책이 있어요?', '전시·공연 일정과 예약 여부는 공식 안내를 확인해 주세요.'),
    ('연예', '(드라마 OR 예능 OR 신곡 OR 앨범 OR 영화 OR 아이돌 OR 콘서트)', '요즘 즐겨 보는 작품이나 자주 듣는 노래가 있어요?', '결말은 말하지 않고, 사생활 추측보다 공개된 작품과 활동으로 이야기해 보세요.'),
    ('스포츠', '(프로야구 OR 프로농구 OR 축구 경기 OR 배구 경기)', '요즘 챙겨 보는 경기나 응원하는 팀 있어요?', '상대가 스포츠에 관심이 있는지 먼저 가볍게 물어보세요.'),
    ('기술·과학', '(인공지능 OR 스마트폰 OR 과학 OR 우주 OR 로봇)', '최근 써 보고 편했던 기술이나 신기했던 과학 소식이 있어요?', '연구 결과와 실제 사용할 수 있는 제품·기능은 다를 수 있어요.'),
    ('사회', '(생활 제도 OR 대중교통 OR 교육 정책 OR 공공 서비스 OR 복지 제도)', '이런 변화가 일상에 도움이 될 것 같아요?', '제도 시행일과 적용 대상은 원문·공식 안내를 확인하고, 정치적 입장이나 개인 사정을 단정하지 마세요.'),
    ('경제·주식', '(금리 OR 물가 OR 환율 OR 코스피 OR 주식 OR 증시 OR 기업 실적)', '이 소식이 생활이나 기업에 어떤 영향을 줄 것 같아요?', '기사 시점의 정보이며 실시간 시세나 매매 추천이 아닙니다. 수치의 기준일과 원문을 확인해 주세요.'),
    ('세계뉴스', '(국제 외교 OR 정상회담 OR 무역 협상 OR 국제 기후 OR 세계 보건)', '최근 글로벌 소식 중 관심이 갔던 변화가 있어요?', '국가·사람 전체를 단정하지 말고 사실과 해석을 구분해 이야기해 보세요.'),
]
PER_CATEGORY = 2
PUBLISHERS = {'nocutnews.co.kr', 'kmib.co.kr', 'segye.com', 'asiae.co.kr', 'fnnews.com',
              'sportsseoul.com', 'sportschosun.com', 'osen.co.kr', 'starnewskorea.com',
              'xportsnews.com', 'isplus.com', 'mydaily.co.kr', 'spotvnews.co.kr', 'yna.co.kr', 'newsis.com', 'news1.kr', 'kbs.co.kr', 'imbc.com', 'sbs.co.kr',
              'hani.co.kr', 'khan.co.kr', 'donga.com', 'chosun.com', 'joongang.co.kr',
              'hankyung.com', 'mk.co.kr', 'etnews.com', 'zdnet.co.kr', 'ytn.co.kr',
              'seoul.co.kr', 'ohmynews.com', 'edaily.co.kr', 'mt.co.kr', 'bloter.net',
              'jtbc.co.kr', 'munhwa.com', 'sisain.co.kr', 'hankookilbo.com'}
LOCAL_PLACES = re.compile('서울|부산|인천|대구|광주|대전|울산|세종|제주|수원|고양|성남|용인|춘천|강릉|속초|양양|원주|청주|천안|공주|부여|보령|홍성|전주|군산|익산|여수|순천|목포|담양|경주|안동|포항|울진|창원|진주|통영|거제|남해|한강|성수|연남|여의도|국내|한국|국립')
OVERSEAS_EVENTS = re.compile('중국|일본|장쑤|상하이|도쿄|오사카|대만|홍콩|방콕|싱가포르|타이베이|유럽|파리|런던|뉴욕|미국|양쯔강')
NEW_CULTURE = re.compile('개봉|공개|신작|신곡|컴백|예고|첫방|첫 방송|개막|시즌|발매|개최|신보|수상|시상식|출연|방영|인터뷰')
EXCLUDE = re.compile('성폭|총격|살해|혐오|자살|마약|참수|잔혹|리딩방|수익보장|급등주추천|종목추천|매수추천|지금사야')
HEAVY = re.compile('사망|참사|전쟁|수사|기소|폭행|탄핵|재판|대통령|정당|국회|논란|폭발|부상')
FINANCE = re.compile('주가|주식|증시|수익률|비트코인|매매')


def candidates(payload, category, question, context, now):
    root = ET.fromstring(payload)
    channel = root.find('channel')
    if channel is None or channel.findtext('language', '').lower() not in ('ko', 'ko-kr'):
        raise ValueError('Expected Korean-language feed')
    link = channel.findtext('link', '')
    if parse_qs(urlparse(link).query).get('ceid') != ['KR:ko']:
        raise ValueError('Expected Korea edition ceid=KR:ko')
    results = []
    for item in channel.findall('item'):
        title = ' '.join((item.findtext('title') or '').split())
        source = item.find('source')
        publisher = (source.text or '').strip() if source is not None else ''
        publisher_url = urlparse(source.get('url', '') if source is not None else '')
        publisher_host = publisher_url.hostname or ''
        if publisher_url.scheme != 'https' or not any(publisher_host == host or publisher_host.endswith('.' + host) for host in PUBLISHERS):
            continue
        url = item.findtext('link', '')
        parsed = urlparse(url)
        try:
            date = parsedate_to_datetime(item.findtext('pubDate', ''))
            if date.tzinfo is None:
                continue
            date = date.astimezone(timezone.utc)
        except (ValueError, TypeError, OverflowError):
            continue
        if (not publisher or not 8 <= len(title) <= 220 or EXCLUDE.search(title)
                or not re.search('[가-힣]', title) or parsed.scheme != 'https'
                or parsed.hostname != 'news.google.com' or parsed.username
                or date < now - timedelta(hours=72) or date > now - timedelta(hours=6)):
            continue
        if category not in ('경제·주식', '세계뉴스') and (HEAVY.search(title) or FINANCE.search(title)):
            continue
        # Keep the exact headline instead of expanding it into unverified facts.
        headline = title.removesuffix(' - ' + publisher)
        if category == '사회' and OVERSEAS_EVENTS.search(headline):
            continue
        if category == '연예' and re.search('열애|이혼|결별|사생활|폭로|불륜|악플', headline):
            continue
        if category == '문화·예술' and not re.search('미술|박물관|공연|연극|뮤지컬|문학|신간|출간|도서|독서|서점|책방|음악회|오케스트라|예술|발레|작가|화가|조각|사진전|오페라|국악|무용|연주|합창|서예|공예', headline):
            continue
        if category == '연예' and not re.search('영화|드라마|예능|신곡|컴백|앨범|콘서트|배우|가수|아이돌|넷플릭스|신작|OTT', headline):
            continue
        if category == '기술·과학' and (re.search('투자|펀드|돈줄|증권|금융|채권|정크|기업실적|공모전|인재양성|우수학교|수상자 명단', headline) or not re.search('기술|과학|연구|발견|탐사|우주|위성|로켓|반도체|스마트폰|카메라|배터리|로봇|인공지능|AI|소프트웨어|기능|업데이트|NASA|화성|달 착륙|유전자|세포|양자|물리|실험', headline)):
            continue
        if category == '사회' and (re.search('시의회|구의회|도의회|정례회|행정사무감사|국정감사|위원장|의장|의원|정치|선거', headline) or not re.search('지원|신청|시행|변경|교통|버스|지하철|교육|학교|복지|서비스|요금|공공|생활|주민|시민|도서관|제도|가구|가족', headline)):
            continue
        if category == '스포츠' and not re.search('축구|야구|농구|배구|올림픽|월드컵|K리그|KBO|NBA|MLB|손흥민|이강인', headline):
            continue
        if category == '경제·주식' and not re.search('금리|물가|환율|코스피|코스닥|주식|증시|경제|기업|실적|고용|GDP|소비|실업|수출|무역|연준|매출|영업이익|관세', headline, re.I):
            continue
        if category == '세계뉴스' and not re.search('미국|중국|일본|유럽|유엔|국제|세계|정상|외교|협상|무역|관세|기후|G7|G20|한미|한중|한일|UN|EU', headline):
            continue
        description = item.findtext('description', '')
        wire = re.search(r'\([^)]{0,40}=\s*(연합뉴스|뉴스1|뉴시스)\)|(연합뉴스|뉴스1|뉴시스)\s*기사\s*전재', description)
        origin = next((host for host in sorted(PUBLISHERS, key=len, reverse=True) if publisher_host == host or publisher_host.endswith('.'+host)), publisher_host)
        if origin == 'sportschosun.com': origin = 'chosun.com'
        if origin == 'isplus.com': origin = 'edaily.co.kr'
        if origin in {'yna.co.kr', 'news1.kr', 'newsis.com'}:
            origin = 'wire:' + {'yna.co.kr': '연합뉴스', 'news1.kr': '뉴스1', 'newsis.com': '뉴시스'}[origin]
        if wire:
            origin = 'wire:' + (wire.group(1) or wire.group(2))
        results.append(dict(
            id=hashlib.sha256(url.encode()).hexdigest()[:20], category=category, origin_group=origin,
            title=headline, summary=headline,
            why_now=f'{publisher}에서 {date.astimezone(timezone(timedelta(hours=9))).strftime("%m.%d %H:%M")} KST에 보도했습니다. 수집 당시 최근 72시간 내 기사이며, 인기 순위가 아닌 대화 소재입니다.',
            opener=f'‘{headline}’라는 소식을 봤어요. {question}', context=context,
            source=publisher, source_url=url,
            published_at=date.isoformat().replace('+00:00', 'Z'),
            evidence='headline',
        ))
    return sorted(results, key=lambda x: x['published_at'], reverse=True)


def build_briefing(feeds, now):
    cards = []
    for (category, _, question, context), payload in zip(TOPICS, feeds):
        if payload is None:
            continue
        articles = candidates(payload, category, question, context, now) if isinstance(payload, bytes) else payload
        for item in rank(articles, category, question, context):
            if any(related(item, old) for old in cards):
                continue
            item['selection_rank'] = 1 + sum(old['category'] == category for old in cards)
            cards.append(item)
            if item['selection_rank'] == PER_CATEGORY:
                break
    if not cards:
        raise ValueError('No mature topics supported by two source groups; preserving previous briefing')
    return dict(schema_version=4, region='KR', edition='daily',
                updated_at=now.isoformat().replace('+00:00', 'Z'), cards=cards)


def legacy_v3(feed):
    old_categories = {'문화·예술', '연예', '스포츠', '기술·과학', '사회'}
    return {**feed, 'schema_version': 3, 'cards': [card for card in feed['cards'] if card['category'] in old_categories]}


def legacy_briefing(feed):
    mapping = {'문화·예술': '문화', '연예': '문화', '스포츠': '스포츠', '기술·과학': '기술', '사회': '생활'}
    seen = set()
    cards = []
    for card in feed['cards']:
        if card['category'] not in mapping or card['category'] in seen:
            continue
        seen.add(card['category'])
        cards.append({**card, 'category': mapping[card['category']]})
    return {**feed, 'schema_version': 2, 'cards': cards}


def fetch_rss(url):
    for attempt in range(2):
        try:
            with urlopen(Request(url, headers={'User-Agent': 'Malmun/2.2 RSS reader'}), timeout=15) as response:
                payload = response.read(2_000_001)
            if len(payload) > 2_000_000:
                raise ValueError('Feed exceeded size limit')
            return payload
        except HTTPError as error:
            if attempt or error.code not in (429, 500, 502, 503, 504):
                raise
            wait = error.headers.get('Retry-After') if error.headers else None
            if wait is not None and (not wait.isdigit() or int(wait) > 10):
                raise
            time.sleep(max(2, int(wait or 0)))
    raise RuntimeError('Unreachable')


def main():
    feeds = []
    now = datetime.now(timezone.utc)
    for category, query, question, context in TOPICS:
        def collect(search):
            url = 'https://news.google.com/rss/search?' + urlencode(dict(q=search+' when:3d', hl='ko', gl='KR', ceid='KR:ko'))
            return candidates(fetch_rss(url), category, question, context, now)
        try:
            articles = collect(query)
            # At most one corroboration query per field, within a bounded request budget.
            if len(rank(articles, category, question, context)) < 2:
                search = corroboration_terms(articles)
                if search:
                    time.sleep(.5)
                    try:
                        articles += collect(search)
                    except Exception as error:
                        print(f'{category}: corroboration unavailable ({type(error).__name__})')
            feeds.append(articles)
        except Exception as error:
            detail = f'HTTP {error.code}' if isinstance(error, HTTPError) else type(error).__name__
            print(f'{category}: unavailable ({detail})')
            if os.environ.get('GITHUB_ACTIONS') == 'true':
                print(f'::warning title=Briefing source::{category}: {detail}')
            feeds.append(None)
        time.sleep(.5)
    feed = build_briefing(feeds, now)
    versions = [('briefing-v4.json', feed), ('briefing-v3.json', legacy_v3(feed)), ('briefing.json', legacy_briefing(feed))]
    for filename, data in versions:
        if not data['cards']:
            continue
        target = ROOT / 'data' / filename
        temporary = target.with_suffix('.tmp')
        temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        os.replace(temporary, target)
    counts = {topic[0]: sum(card['category'] == topic[0] for card in feed['cards']) for topic in TOPICS}
    print('Coverage-based topics: ' + json.dumps(counts, ensure_ascii=False))
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        print('::notice title=Briefing counts::' + json.dumps(counts, ensure_ascii=False))
    print(f"Published {len(feed['cards'])} mature topics with multiple source groups")


if __name__ == '__main__':
    main()
