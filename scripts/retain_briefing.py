"""Retain still-eligible evidence when a bounded RSS sample temporarily misses a field."""
from copy import deepcopy
from math import isfinite
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse
from rank_topics import related


def timestamp(value):
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('Missing timezone')
    return parsed.astimezone(timezone.utc)


def news_url(value):
    parsed = urlparse(value)
    return parsed.scheme == 'https' and parsed.hostname == 'news.google.com' and parsed.username is None and parsed.password is None


def eligible(card, now):
    try:
        coverage = card['coverage']
        groups, reports = coverage['source_groups'], coverage['report_count']
        if type(groups) is not int or not 1 <= groups <= 8 or type(reports) is not int or reports < groups:
            return False
        if groups == 1 and card['category'] not in ('문화·예술', '스포츠'):
            return False
        first, last, primary = [timestamp(value) for value in
                                (coverage['first_report_at'], coverage['last_report_at'], card['published_at'])]
        if not now-timedelta(hours=72) <= first <= primary <= last <= now-timedelta(hours=6):
            return False
        hours = coverage['span_hours']
        if type(hours) not in (int, float) or not isfinite(hours) or abs((last-first).total_seconds()/3600-hours) > .11:
            return False
        sources = coverage['sources']
        if len(sources) != groups or len({s['group'] for s in sources}) != groups:
            return False
        if any(not s['name'] or not s['group'] or not news_url(s['url']) or not first <= timestamp(s['published_at']) <= last for s in sources):
            return False
        if not any(s['name'] == card['source'] and s['url'] == card['source_url'] and timestamp(s['published_at']) == primary for s in sources):
            return False
        return (card['evidence'] == 'headline' and news_url(card['source_url']) and
                news_url(coverage['first_report_url']) and news_url(coverage['last_report_url']) and
                all(isinstance(card[key], str) and card[key].strip() for key in
                    ('id', 'title', 'summary', 'why_now', 'opener', 'context', 'source')))
    except (KeyError, ValueError, TypeError, AttributeError, OverflowError):
        return False


def carry_recent(feed, previous, now, categories):
    if not isinstance(previous, dict) or previous.get('region') != 'KR' or previous.get('edition') != 'daily' or previous.get('schema_version') not in (4, 5):
        return feed
    try:
        if timestamp(previous['updated_at']) > now:
            return feed
        cached = previous['cards']
        if not isinstance(cached, list):
            return feed
    except (KeyError, TypeError, ValueError, AttributeError):
        return feed
    result = deepcopy(feed)
    for card in cached:
        if not isinstance(card, dict) or card.get('category') not in categories or not eligible(card, now):
            continue
        category = card['category']
        if sum(c['category'] == category for c in result['cards']) >= 2 or any(related(card, c) for c in result['cards']):
            continue
        item = deepcopy(card)
        observed = item.get('last_collected_at', previous['updated_at'])
        try:
            label = timestamp(observed).astimezone(timezone(timedelta(hours=9))).strftime('%m.%d %H:%M')
        except (ValueError, TypeError, AttributeError):
            continue
        item['last_collected_at'] = observed
        qualifier = '단일 출처 · 인기 확인 전. ' if item['coverage']['source_groups'] == 1 else ''
        item['why_now'] = f'{qualifier}이전 수집({label} KST)에서 확인한 기사입니다. 이번 수집의 부족한 분야를 보완하며 모든 근거 기사는 현재 기준 최근 3일 이내입니다. 새로 확인한 인기나 조회수 순위가 아닙니다.'
        item['selection_rank'] = 1 + sum(c['category'] == category for c in result['cards'])
        result['cards'].append(item)
    result['cards'].sort(key=lambda c: (categories.index(c['category']), c['selection_rank']))
    return result
