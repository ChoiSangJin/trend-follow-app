"""Read-only Jikan/MyAnimeList discovery feed. No Korean viewing-rank claims."""
import json
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from html import unescape
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
API = 'https://api.jikan.moe/v4'
SEASONS = ['winter', 'spring', 'summer', 'fall']


def fetch(path):
    for attempt in range(3):
        try:
            with urlopen(Request(API + path, headers={'User-Agent': 'Malmun/4.1 anime discovery'}), timeout=30) as response:
                raw = response.read(3_000_001)
            if len(raw) > 3_000_000:
                raise ValueError('Oversized API response')
            return json.loads(raw)
        except HTTPError as error:
            if error.code != 429 and error.code < 500:
                raise
            if attempt == 2:
                raise
        except (URLError, TimeoutError):
            if attempt == 2:
                raise
        time.sleep(2 * (attempt + 1))
    raise ValueError('API unavailable')


def clean(value, limit=1000):
    return unescape(re.sub(r'<[^>]+>', '', str(value or ''))).strip()[:limit]


def mal_url(value):
    url = urlparse(str(value or ''))
    return value if url.scheme == 'https' and url.hostname in ('myanimelist.net', 'www.myanimelist.net') and not url.username else None


def title(raw, position=None):
    identifier = raw.get('mal_id')
    if not isinstance(identifier, int) or identifier < 1 or not clean(raw.get('title')) or not mal_url(raw.get('url')):
        return None
    if str(raw.get('rating', '')).startswith(('Rx', 'R+')) or any(g.get('mal_id') in (12, 49) for g in raw.get('genres', [])):
        return None
    score = raw.get('score')
    if score is not None and (not isinstance(score, (int, float)) or not 0 <= score <= 10):
        return None
    image = raw.get('images', {}).get('jpg', {}).get('image_url')
    if not isinstance(image, str) or urlparse(image).scheme != 'https' or urlparse(image).hostname != 'cdn.myanimelist.net':
        image = None
    return {'id': identifier, 'title': clean(raw.get('title_english') or raw['title'], 240),
            'original_title': clean(raw['title'], 240), 'japanese_title': clean(raw.get('title_japanese'), 240),
            'url': raw['url'], 'image_url': image, 'score': score, 'scored_by': raw.get('scored_by') or 0,
            'members': raw.get('members') or 0, 'position': position,
            'synopsis': clean(raw.get('synopsis')), 'format': clean(raw.get('type'), 30),
            'episodes': raw.get('episodes'), 'status': clean(raw.get('status'), 80),
            'season': raw.get('season'), 'year': raw.get('year'),
            'genres': [clean(g.get('name'), 60) for g in raw.get('genres', [])],
            'airing': raw.get('airing') is True}


def titles(payload, ranked=False, year=None, season=None):
    if not isinstance(payload, dict) or not isinstance(payload.get('data'), list):
        raise ValueError('Invalid anime response')
    output, seen = [], set()
    for position, raw in enumerate(payload['data'], 1):
        if not isinstance(raw, dict):
            continue
        item = title(raw, position if ranked else None)
        if item is None or item['id'] in seen:
            continue
        if ranked and (not item['airing'] or item['score'] is None):
            continue
        if year is not None and (item['year'] != year or item['season'] != season):
            continue
        seen.add(item['id'])
        output.append(item)
    if not output:
        raise ValueError('No verified anime entries')
    return output[:10]


def news(payload, anime, now):
    if not isinstance(payload, dict) or not isinstance(payload.get('data'), list):
        raise ValueError('Invalid news response')
    output = []
    for row in payload['data']:
        try:
            published = datetime.fromisoformat(row['date'].replace('Z', '+00:00')).astimezone(timezone.utc)
        except (KeyError, ValueError, TypeError):
            continue
        if not now - timedelta(days=90) <= published <= now or not mal_url(row.get('url')) or not clean(row.get('title')):
            continue
        output.append({'anime_id': anime['id'], 'anime_title': anime['title'], 'title': clean(row['title'], 400),
                       'url': row['url'], 'published_at': published.isoformat(), 'excerpt': clean(row.get('excerpt'), 400)})
    return output


def collect(fetcher=fetch, now=None, delay=time.sleep):
    now = now or datetime.now(timezone.utc)
    local = now.astimezone(timezone(timedelta(hours=9)))
    season = SEASONS[(local.month - 1) // 3]
    ranked = titles(fetcher('/top/anime?filter=airing&limit=10&sfw=true'), ranked=True)
    delay(1.1)
    seasonal = titles(fetcher(f'/seasons/{local.year}/{season}?limit=25&sfw=true'), year=local.year, season=season)
    articles, errors, checked = [], [], set()
    for item in (ranked[:3] + seasonal[:3]):
        if item['id'] in checked:
            continue
        checked.add(item['id'])
        delay(1.1)
        try:
            articles.extend(news(fetcher(f"/anime/{item['id']}/news"), item, now))
        except Exception:
            errors.append(item['id'])
    unique = {a['url']: a for a in articles}
    return {'schema_version': 1, 'source': 'Jikan / MyAnimeList', 'source_url': 'https://jikan.moe',
            'fetched_at': now.isoformat(), 'season_year': local.year, 'season': season,
            'airing': ranked, 'seasonal': seasonal,
            'news': sorted(unique.values(), key=lambda a:a['published_at'], reverse=True)[:15],
            'news_checked_ids': sorted(checked), 'news_failed_ids': errors}


def main():
    data = collect()
    (ROOT / 'data/anime-v1.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print('Anime source verified:', len(data['airing']), len(data['seasonal']), len(data['news']))
    if '--inspect' in sys.argv:
        print('ANIME_FEED_JSON=' + json.dumps(data, ensure_ascii=False))


if __name__ == '__main__':
    main()
