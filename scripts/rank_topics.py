"""Conservative headline-based topic clustering and observable coverage ranking.
This measures a bounded RSS sample, never audience size or factual consensus.
"""
import hashlib
import re
from functools import lru_cache
from datetime import datetime
from difflib import SequenceMatcher

MAX_SOURCES = 8
STOP = set('오늘 이번 지난 최근 관련 통해 대한 위해 공개 발표 출시 개막 시작 새로운 신작 소식 기사 뉴스 사진 영상 단독 종합 속보 기자 가수 배우 신곡 앨범 드라마 영화 방송 예능 콘서트 공연 전시 기술 과학 로봇 인공지능 AI ai 지원 신청 제도 교통 교육 주민 시민 요금 버스'.split())
ALIASES = [('연방준비제도', '연준'), ('베를린필하모닉', '베를린필'), ('코스피지수', '코스피'), ('국내총생산', 'gdp')]
PARTICLES = ('에서는', '에도', '으로', '에서', '에게', '까지', '부터', '보다', '에는', '하며', '했다', '한다', '하는', '위한', '은', '는', '을', '를', '과', '와', '의', '이', '가')


@lru_cache(maxsize=8192)
def normalized(title):
    value = re.sub(r'\[[^\]]*\]', ' ', title).lower()
    for source, target in ALIASES:
        value = value.replace(source.lower(), target.lower())
    return ' '.join(re.findall(r'[가-힣a-z0-9]+', value))


@lru_cache(maxsize=8192)
def tokens(title):
    result = []
    for word in normalized(title).split():
        if len(word) >= 4 and word.endswith('서'):
            word = word[:-1]
        if len(word) >= 3 and word.endswith(('도', '에')):
            word = word[:-1]
        for ending in PARTICLES:
            if word.endswith(ending) and len(word) - len(ending) >= 2:
                word = word[:-len(ending)]
                break
        if len(word) >= 2 and word not in STOP and not word.isdigit():
            result.append(word)
    return frozenset(result)


def related(a, b):
    if a['id'] == b['id'] or a['source_url'] == b['source_url']:
        return True
    shared = tokens(a['title']) & tokens(b['title'])
    if not shared:
        return False
    left, right = normalized(a['title']), normalized(b['title'])
    ratio = SequenceMatcher(None, left, right).ratio()
    union = tokens(a['title']) | tokens(b['title'])
    overlap = len(shared) / max(1, len(union))
    # Matching a named player and the same winning streak handles long match reports.
    if a.get('category') == b.get('category') == '스포츠':
        streaks = set(re.findall(r'\d+연승', left)) & set(re.findall(r'\d+연승', right))
        players = {name for name in ('이강인', '손흥민', '김민재', '오타니', '류현진') if name in left and name in right}
        if players and streaks:
            return True
    named_overlap = len([word for word in shared if len(word) >= 3]) >= 2 and ratio >= .32
    return named_overlap or (ratio >= .78 and bool(shared)) or (len(shared) >= 2 and (ratio >= .48 or overlap >= .36)) or (len(shared) == 1 and max(map(len, shared)) >= 3 and ratio >= .68)


def clusters(articles):
    """Seed matching avoids a chain of generic AI/market headlines merging topics."""
    result = []
    seen = set()
    for item in sorted(articles, key=lambda x: (x['published_at'], x['id'])):
        if item['id'] in seen:
            continue
        seen.add(item['id'])
        matches = [group for group in result if related(item, group[0])]
        if matches:
            group = max(matches, key=lambda g: SequenceMatcher(None, normalized(item['title']), normalized(g[0]['title'])).ratio())
            group.append(item)
        else:
            result.append([item])
    return result


def grouped_reports(group):
    """Collapse publisher-domain groups, explicit wire attribution and near-copy titles.

    This cannot detect every rewritten syndicated article. UI/docs describe an estimate.
    """
    headline_buckets = []
    for item in sorted(group, key=lambda x: (x['published_at'], x['id'])):
        origin = item['origin_group']
        bucket = next((old for old in headline_buckets if
                       SequenceMatcher(None, normalized(item['title']), normalized(old['title'])).ratio() >= .92), None)
        if bucket:
            origin = bucket['effective_group']
        headline_buckets.append({**item, 'effective_group': origin})
    # A same-origin story can occur in several headline buckets: it remains one group.
    parent = {}
    def root(key):
        parent.setdefault(key, key)
        while parent[key] != key:
            key = parent[key]
        return key
    for item in headline_buckets:
        a, b = root(item['origin_group']), root(item['effective_group'])
        parent[max(a, b)] = min(a, b)
    return [{**item, 'effective_group': root(item['origin_group'])} for item in headline_buckets]


def independent_reports(group):
    by_group = {}
    for item in grouped_reports(group):
        key = item['effective_group']
        if key not in by_group or item['published_at'] > by_group[key]['published_at']:
            by_group[key] = {**item, 'effective_group': key}
    return sorted(by_group.values(), key=lambda x: (x['published_at'], x['id']), reverse=True)


def coverage_topic(group, category, question, context, *, minimum_sources=2):
    reports = independent_reports(group)
    if len(reports) < minimum_sources:
        return None
    reports = reports[:MAX_SOURCES]
    # Each retained source gets equal weight, rather than letting copies choose the headline.
    representative = max(reports, key=lambda a: (
        sum(SequenceMatcher(None, normalized(a['title']), normalized(b['title'])).ratio() for b in reports) / len(reports),
        a['published_at'], a['id']))
    dates = [datetime.fromisoformat(item['published_at'].replace('Z', '+00:00')) for item in group]
    first, last = min(dates), max(dates)
    earliest = min(group, key=lambda x: (x['published_at'], x['id']))
    latest = max(group, key=lambda x: (x['published_at'], x['id']))
    hours = round((last-first).total_seconds()/3600, 1)
    span_label = f'{int(hours)}시간' if hours >= 1 else '1시간 미만'
    coverage = dict(source_groups=len(reports), report_count=len(group), span_hours=hours,
                    first_report_at=first.isoformat().replace('+00:00', 'Z'),
                    last_report_at=last.isoformat().replace('+00:00', 'Z'),
                    first_report_url=earliest['source_url'], last_report_url=latest['source_url'],
                    sources=[dict(name=item['source'], group=item['effective_group'],
                                  url=item['source_url'], published_at=item['published_at']) for item in reports])
    explanation = (f'단일 출처 기사입니다. {representative["source"]}의 보도 1곳을 확인해 문화·스포츠의 추가 읽을거리로 제공합니다. 여러 매체의 관심이나 인기가 확인된 소식은 아닙니다.' if len(reports) == 1 else f'수집 범위에서 관련 보도 {len(group)}개를 확인했습니다. 유사 제목·같은 매체를 묶은 출처그룹 {len(reports)}곳, {span_label}에 걸친 보도를 근거로 선정했습니다. 조회수나 공유수 순위는 아닙니다.')
    return dict(id=hashlib.sha256((category+'|'+earliest['id']).encode()).hexdigest()[:20],
                category=category, title=representative['title'], summary=representative['title'],
                why_now=explanation,
                opener=f'‘{representative["title"]}’라는 소식을 봤어요. {question}', context=context,
                source=representative['source'], source_url=representative['source_url'],
                published_at=representative['published_at'], evidence='headline', coverage=coverage)


def rank(articles, category, question, context):
    result = [topic for group in clusters(articles) if (topic := coverage_topic(group, category, question, context))]
    # Breadth first, then sustained coverage. No unobservable audience/viral score.
    return sorted(result, key=lambda x: (x['coverage']['source_groups'],
                  x['coverage']['span_hours'], x['coverage']['last_report_at'], x['id']), reverse=True)


def corroboration_searches(articles, limit=2):
    """Target distinct unconfirmed events rather than re-searching a confirmed one."""
    groups = [group for group in clusters(articles) if len(independent_reports(group)) < 2]
    groups.sort(key=lambda g: max(a['published_at'] for a in g), reverse=True)
    searches = []
    for group in groups:
        words = [word for word in normalized(group[0]['title']).split() if word in tokens(group[0]['title'])]
        if not words:
            words = sorted(tokens(group[0]['title']), key=lambda x: (-len(x), x))
        search = ' '.join('"'+word+'"' for word in words[:2])
        if search and search not in searches:
            searches.append(search)
        if len(searches) == limit:
            break
    return searches


def additional_reading(articles, category, question, context):
    """Real dated articles for sparse arts/sport fields; never count copies as popularity."""
    if category not in ('문화·예술', '스포츠'):
        return []
    result = [coverage_topic(group, category, question, context, minimum_sources=1)
              for group in clusters(articles) if len(independent_reports(group)) == 1]
    # One original report represents the item, irrespective of copy count or copy span.
    return sorted(result, key=lambda x: (x['published_at'], x['id']), reverse=True)
