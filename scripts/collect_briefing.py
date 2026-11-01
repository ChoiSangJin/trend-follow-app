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
    ('문화', '(영화 개봉 OR 드라마 공개 OR 예능 공개)', '최근에 본 작품 중 추천할 만한 게 있어요?', '취향을 먼저 물어보고, 결말이나 반전은 말하지 않는 편이 좋아요.'),
    ('음식', '(신메뉴 OR 제철 음식 OR 음식 축제)', '요즘 새로 먹어 보고 싶은 음식 있어요?', '직접 먹어 본 경험과 기사에서 본 정보를 구분해 이야기해 보세요.'),
    ('생활', '(전시 개막 OR 가을 산책 OR 지역 축제)', '시간 나면 가 보고 싶은 곳 있어요?', '행사 일정·예약·운영 여부는 원문이나 공식 안내를 확인해 주세요.'),
    ('기술', '(신제품 출시 OR 과학 발견 OR 우주 탐사)', '이런 기능이 있으면 실제로 써 볼 것 같아요?', '출시 계획과 실제 사용할 수 있는 기능은 다를 수 있어요.'),
    ('스포츠', '(프로야구 OR 프로농구 OR 축구 경기)', '요즘 챙겨 보는 경기나 응원하는 팀 있어요?', '상대가 스포츠에 관심이 있는지 먼저 가볍게 물어보세요.'),
]
PUBLISHERS = {'yna.co.kr', 'newsis.com', 'news1.kr', 'kbs.co.kr', 'imbc.com', 'sbs.co.kr',
              'hani.co.kr', 'khan.co.kr', 'donga.com', 'chosun.com', 'joongang.co.kr',
              'hankyung.com', 'mk.co.kr', 'etnews.com', 'zdnet.co.kr', 'ytn.co.kr',
              'seoul.co.kr', 'ohmynews.com', 'edaily.co.kr', 'mt.co.kr', 'bloter.net',
              'jtbc.co.kr', 'munhwa.com', 'sisain.co.kr', 'hankookilbo.com'}
EXCLUDE = re.compile('사망|참사|성폭|총격|전쟁|수사|기소|폭행|살해|탄핵|혐오|자살|마약|재판|대통령|정당|국회|논란|폭발|부상')


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
        for item in candidates(payload, category, question, context, now):
            if any(item['id'] == old['id'] or SequenceMatcher(None, item['title'], old['title']).ratio() > .65 for old in cards):
                continue
            cards.append(item)
            break
    if not cards:
        raise ValueError('No recent, eligible stories; preserving previous briefing')
    return dict(schema_version=2, region='KR', edition='daily',
                updated_at=now.isoformat().replace('+00:00', 'Z'), cards=cards)


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
    target = ROOT / 'data/briefing.json'
    temporary = target.with_suffix('.tmp')
    temporary.write_text(json.dumps(feed, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(temporary, target)
    print(f"Published {len(feed['cards'])} dated conversation topics (KR)")


if __name__ == '__main__':
    main()
