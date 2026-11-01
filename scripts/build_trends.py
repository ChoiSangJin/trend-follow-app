"""Three-day Korean news coverage, with persisted observation history (not audience data)."""
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse
from news_rules import sports_story
from rank_topics import clusters, grouped_reports, coverage_topic, related

MAX_PER_CATEGORY = 600


def date(value):
    result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if result.tzinfo is None:
        raise ValueError('Timezone required')
    return result.astimezone(timezone.utc)


def valid_article(item, now, categories):
    try:
        url = urlparse(item['source_url'])
        return (item['category'] in categories and (item['category'] != '스포츠' or sports_story(item['title'])) and item['evidence'] == 'headline' and
                now-timedelta(hours=72) <= date(item['published_at']) <= now and
                url.scheme == 'https' and url.hostname == 'news.google.com' and url.username is None and
                all(isinstance(item[key], str) and item[key].strip() for key in
                    ('id', 'title', 'summary', 'source', 'origin_group', 'opener', 'context', 'why_now')))
    except (KeyError, ValueError, TypeError, AttributeError):
        return False


def continuous_hours(snapshots, category, now):
    times = sorted({date(s['at']) for s in snapshots if category in s['categories'] and category not in s.get('truncated_categories', [])})
    if not times or times[-1] != now:
        return 0.0
    start = times[-1]
    for older in reversed(times[:-1]):
        if start-older > timedelta(hours=8):
            break
        start = older
    return int((now-start).total_seconds()/360)/10


def build_trends(articles, previous, now, topics, available):
    categories = [t[0] for t in topics]
    previous = previous if isinstance(previous, dict) and previous.get('schema_version') == 1 and previous.get('region') == 'KR' else {}
    retained = previous.get('articles', [])
    retained = retained if isinstance(retained, list) else []
    unique = {}
    for item in retained + articles:
        if isinstance(item, dict) and valid_article(item, now, categories):
            unique[(item['category'], item['id'])] = item
    pool = []
    truncated = []
    for category in categories:
        candidates = sorted((a for a in unique.values() if a['category'] == category),
                            key=lambda a: (a['published_at'], a['id']), reverse=True)
        if len(candidates) > MAX_PER_CATEGORY:
            truncated.append(category)
        pool.extend(candidates[:MAX_PER_CATEGORY])
    snapshots = []
    for item in previous.get('snapshots', []) if isinstance(previous.get('snapshots'), list) else []:
        try:
            if isinstance(item['categories'], list) and now-timedelta(hours=72) <= date(item['at']) < now:
                snapshots.append({'at': item['at'], 'categories': [c for c in item['categories'] if c in categories],
                                  'truncated_categories': [c for c in item.get('truncated_categories', []) if c in categories]})
        except (KeyError, ValueError, TypeError, AttributeError):
            continue
    snapshots.append({'at': now.isoformat().replace('+00:00', 'Z'), 'categories': [c for c in available if c in categories], 'truncated_categories': truncated})
    snapshots = sorted({s['at']: s for s in snapshots}.values(), key=lambda s: s['at'])[-1000:]
    cards = []
    for category, _, question, context in topics:
        hours = continuous_hours(snapshots, category, now)
        ready = hours >= 48
        for group in clusters([a for a in pool if a['category'] == category]):
            topic = coverage_topic(group, category, question, context)
            if topic is None:
                continue
            labelled = grouped_reports(group)
            total = len({a['effective_group'] for a in labelled})
            daily = [set(), set(), set()]
            for item in labelled:
                age = (now-date(item['published_at'])).total_seconds()/3600
                index = 2 if age < 24 else 1 if age < 48 else 0
                daily[index].add(item['effective_group'])
            counts = [len(s) for s in daily]
            older, current = counts[1:]
            percent = round((current-older)*100/older, 1) if ready and older >= 2 else None
            signal = 'collecting' if not ready else 'growing' if older >= 2 and current >= 3 and current >= older*1.5 else 'new' if older == 0 and current >= 2 else 'steady'
            cards.append(dict(topic=topic, source_groups=total, daily_sources=counts,
                              tracking_hours=hours, comparison_ready=ready, growth_percent=percent, signal=signal))
    cards.sort(key=lambda c: (c['source_groups'], c['topic']['coverage']['span_hours'],
                              c['topic']['coverage']['last_report_at'], c['topic']['id']), reverse=True)
    selected = []
    for item in cards:
        if any(related(item['topic'], old['topic']) for old in selected):
            continue
        selected.append({**item, 'rank': len(selected)+1})
        if len(selected) == 30:
            break
    history = dict(schema_version=1, region='KR', snapshots=snapshots, articles=pool)
    feed = dict(schema_version=1, region='KR', updated_at=now.isoformat().replace('+00:00', 'Z'),
                tracking_started_at=snapshots[0]['at'], snapshot_count=len(snapshots), cards=selected)
    return feed, history
