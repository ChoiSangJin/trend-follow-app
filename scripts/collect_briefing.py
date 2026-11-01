"""Build a dated small-talk briefing from recent Korean-edition news headlines.
No LLM credentials, invented article summaries, popularity claims or scraping logins.
"""
import hashlib
import json
import os
import re
from datetime import datetime, timedelta, timezone
from difflib import SequenceMatcher
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.parse import urlencode, urlparse, parse_qs
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
TOPICS = [
    ('문화·예술', '(미술 전시 OR 뮤지컬 개막 OR 연극 개막 OR 문학상 OR 신간 출간 OR 클래식 공연)', '요즘 가 보고 싶은 전시나 공연, 읽어 보고 싶은 책이 있어요?', '전시·공연 일정과 예약 여부는 공식 안내를 확인해 주세요.'),
    ('연예', '(드라마 공개 OR 예능 첫방송 OR 신곡 발표 OR 새 앨범 OR 영화 개봉)', '요즘 즐겨 보는 작품이나 자주 듣는 노래가 있어요?', '결말은 말하지 않고, 사생활 추측보다 공개된 작품과 활동으로 이야기해 보세요.'),
    ('스포츠', '(프로야구 OR 프로농구 OR 축구 경기 OR 배구 경기)', '요즘 챙겨 보는 경기나 응원하는 팀 있어요?', '상대가 스포츠에 관심이 있는지 먼저 가볍게 물어보세요.'),
    ('기술·과학', '(인공지능 신기능 OR 스마트폰 신제품 OR 과학 발견 OR 우주 탐사 OR 로봇 기술)', '최근 써 보고 편했던 기술이나 신기했던 과학 소식이 있어요?', '연구 결과와 실제 사용할 수 있는 제품·기능은 다를 수 있어요.'),
    ('사회', '(생활 제도 OR 대중교통 OR 교육 정책 OR 공공 서비스 OR 복지 제도)', '이런 변화가 일상에 도움이 될 것 같아요?', '제도 시행일과 적용 대상은 원문·공식 안내를 확인하고, 정치적 입장이나 개인 사정을 단정하지 마세요.'),
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
NEW_CULTURE = re.compile('개봉|공개|신작|신곡|컴백|예고|첫방|첫 방송|개막|시즌')
EXCLUDE = re.compile('주가|주식|증시|수익률|비트코인|매매|사망|참사|성폭|총격|전쟁|수사|기소|폭행|살해|탄핵|혐오|자살|마약|재판|대통령|정당|국회|논란|폭발|부상')


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
                or date < now - timedelta(hours=72) or date > now + timedelta(minutes=10)):
            continue
        # Keep the exact headline instead of expanding it into unverified facts.
        headline = title.removesuffix(' - ' + publisher)
        if category == '사회' and OVERSEAS_EVENTS.search(headline):
            continue
        if category == '연예' and (not NEW_CULTURE.search(headline) or re.search('열애|이혼|결별|사생활|폭로|불륜|악플', headline)):
            continue
        if category == '문화·예술' and not re.search('미술|박물관|공연|연극|뮤지컬|문학|신간|출간|도서|독서|서점|책방|음악회|오케스트라|예술|발레|작가|화가|조각|사진전', headline):
            continue
        if category == '연예' and not re.search('영화|드라마|예능|신곡|컴백|앨범|콘서트|배우|가수|아이돌|넷플릭스|신작|OTT', headline):
            continue
        if category == '기술·과학' and (re.search('투자|펀드|돈줄|증권|금융|채권|정크|기업실적', headline) or not re.search('기술|과학|연구|발견|탐사|우주|위성|로켓|반도체|스마트폰|카메라|배터리|로봇|인공지능|AI|소프트웨어|기능|업데이트', headline)):
            continue
        if category == '사회' and (re.search('시의회|구의회|도의회|정례회|행정사무감사|국정감사|위원장|의장|의원|정치|선거', headline) or not re.search('지원|신청|시행|변경|교통|버스|지하철|교육|학교|복지|서비스|요금|공공|생활|주민|시민|도서관|제도|가구|가족', headline)):
            continue
        results.append(dict(
            id=hashlib.sha256(url.encode()).hexdigest()[:20], category=category,
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
        selected = 0
        for item in candidates(payload, category, question, context, now):
            if any(item['id'] == old['id'] or SequenceMatcher(None, item['title'], old['title']).ratio() > .65 for old in cards):
                continue
            cards.append(item)
            selected += 1
            if selected == PER_CATEGORY:
                break
    if not cards:
        raise ValueError('No recent, eligible stories; preserving previous briefing')
    return dict(schema_version=3, region='KR', edition='daily',
                updated_at=now.isoformat().replace('+00:00', 'Z'), cards=cards)


def legacy_briefing(feed):
    mapping = {'문화·예술': '문화', '연예': '문화', '스포츠': '스포츠', '기술·과학': '기술', '사회': '생활'}
    seen = set()
    cards = []
    for card in feed['cards']:
        if card['category'] in seen:
            continue
        seen.add(card['category'])
        cards.append({**card, 'category': mapping[card['category']]})
    return {**feed, 'schema_version': 2, 'cards': cards}


def main():
    feeds = []
    for category, query, _, _ in TOPICS:
        url = 'https://news.google.com/rss/search?' + urlencode(dict(q=query + ' when:3d', hl='ko', gl='KR', ceid='KR:ko'))
        try:
            with urlopen(Request(url, headers={'User-Agent': 'Malmun/2.0'}), timeout=25) as response:
                payload = response.read(2_000_001)
            if len(payload) > 2_000_000:
                raise ValueError('Feed exceeded size limit')
            feeds.append(payload)
        except Exception as error:
            # Do not log URLs or remote bodies; keep failures distinct from valid news.
            print(f'{category}: unavailable ({type(error).__name__})')
            feeds.append(None)
    feed = build_briefing(feeds, datetime.now(timezone.utc))
    target = ROOT / 'data/briefing-v3.json'
    temporary = target.with_suffix('.tmp')
    temporary.write_text(json.dumps(feed, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(temporary, target)
    # Older v2 clients reject more than five cards. Keep their endpoint compatible.
    legacy = legacy_briefing(feed)
    legacy_target = ROOT / 'data/briefing.json'
    legacy_temp = legacy_target.with_suffix('.tmp')
    legacy_temp.write_text(json.dumps(legacy, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(legacy_temp, legacy_target)
    print(f"Published {len(feed['cards'])} dated conversation topics (KR)")


if __name__ == '__main__':
    main()
