"""Bounded AniList discovery snapshot with public news and airing updates."""
import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from html import unescape
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
API = 'https://graphql.anilist.co'
NEWS = 'https://www.animenewsnetwork.com/news/rss.xml'
SEASONS = ['winter','spring','summer','fall']
QUERY = 'query($year:Int,$season:MediaSeason){trending:Page(perPage:10){media(type:ANIME,isAdult:false,status:RELEASING,sort:TRENDING_DESC){id isAdult title{romaji english native}siteUrl description(asHtml:false)averageScore popularity trending format episodes status season seasonYear genres coverImage{large}nextAiringEpisode{episode airingAt}trailer{id site}}}seasonal:Page(perPage:10){media(type:ANIME,isAdult:false,seasonYear:$year,season:$season,sort:POPULARITY_DESC){id isAdult title{romaji english native}siteUrl description(asHtml:false)averageScore popularity trending format episodes status season seasonYear genres coverImage{large}nextAiringEpisode{episode airingAt}trailer{id site}}}}'


def clean(value, limit=1000):
    return unescape(re.sub(r'<[^>]+>', '', str(value or ''))).strip()[:limit]


def request_api(year, season):
    payload = json.dumps({'query': QUERY, 'variables': {'year': year, 'season': season.upper()}}).encode()
    for attempt in range(3):
        try:
            with urlopen(Request(API, data=payload, headers={'Content-Type':'application/json','Accept':'application/json','User-Agent':'Malmun/4.1 anime discovery'}), timeout=30) as response:
                data = json.loads(response.read(3_000_000))
            if data.get('errors') or not isinstance(data.get('data'), dict):
                raise ValueError('AniList returned errors')
            return data['data']
        except HTTPError as error:
            if attempt == 2 or (error.code != 429 and error.code < 500): raise
        except (URLError, TimeoutError):
            if attempt == 2: raise
        time.sleep(2 * (attempt + 1))
    raise ValueError('AniList unavailable')


def parse_title(raw, position=None):
    identifier = raw.get('id')
    name = raw.get('title') or {}
    url = urlparse(str(raw.get('siteUrl','')))
    if not isinstance(identifier,int) or identifier < 1 or raw.get('isAdult') is True or not (name.get('romaji') or name.get('english')) or url.scheme != 'https' or url.hostname != 'anilist.co' or url.path != '/anime/' + str(identifier):
        return None
    score = raw.get('averageScore')
    if score is not None and (not isinstance(score,int) or not 0 <= score <= 100): return None
    image = (raw.get('coverImage') or {}).get('large')
    if urlparse(str(image)).hostname not in ('s4.anilist.co','s3.anilist.co') or urlparse(str(image)).scheme != 'https': image = None
    return {'id':identifier, 'title':clean(name.get('english') or name.get('romaji'),240),
            'original_title':clean(name.get('romaji'),240), 'japanese_title':clean(name.get('native'),240),
            'url':raw['siteUrl'], 'image_url':image, 'score':score, 'scored_by':None,
            'members':raw.get('popularity'), 'activity':raw.get('trending'), 'position':position,
            'synopsis':clean(raw.get('description')), 'format':clean(raw.get('format'),30),
            'episodes':raw.get('episodes'), 'status':clean(raw.get('status'),80),
            'season':str(raw.get('season') or '').lower(), 'year':raw.get('seasonYear'),
            'genres':[clean(g,60) for g in (raw.get('genres') or [])], 'airing':raw.get('status') == 'RELEASING'}


def build(payload, now):
    local = now.astimezone(timezone(timedelta(hours=9)))
    season = SEASONS[(local.month-1)//3]
    lists, updates, seen_updates = {}, [], set()
    for section in ('trending','seasonal'):
        raw_items = payload.get(section, {}).get('media')
        if not isinstance(raw_items,list): raise ValueError('Missing anime list')
        result, seen = [], set()
        for index, raw in enumerate(raw_items,1):
            item = parse_title(raw,index if section == 'trending' else None)
            if item is None or item['id'] in seen: continue
            if section == 'trending' and not item['airing']: continue
            if section == 'seasonal' and (item['year'] != local.year or item['season'] != season): continue
            result.append(item); seen.add(item['id'])
            if item['id'] in seen_updates: continue
            seen_updates.add(item['id'])
            episode = raw.get('nextAiringEpisode') or {}
            if isinstance(episode.get('episode'),int) and episode['episode'] > 0 and isinstance(episode.get('airingAt'),int):
                when = datetime.fromtimestamp(episode['airingAt'],timezone.utc)
                if now <= when <= now + timedelta(days=14):
                    updates.append({'anime_id':item['id'],'anime_title':item['title'],'kind':'airing',
                                    'title':str(episode['episode'])+'화 방영 예정', 'airing_at':when.isoformat(),'url':item['url']})
            trailer = raw.get('trailer') or {}
            if trailer.get('site') == 'youtube' and re.fullmatch(r'[A-Za-z0-9_-]{11}',str(trailer.get('id',''))):
                updates.append({'anime_id':item['id'],'anime_title':item['title'],'kind':'trailer','title':'작품 예고편',
                                'airing_at':None,'url':'https://www.youtube.com/watch?v='+trailer['id']})
        if not result: raise ValueError('No verified anime entries')
        lists[section] = result[:10]
    return {'schema_version':1,'source':'AniList','source_url':'https://anilist.co','api_url':API,
            'rank_basis':'trending','fetched_at':now.isoformat(),'season_year':local.year,'season':season,
            **lists,'updates':updates[:40],'news':[],'news_available':False}


def parse_news(xml, now):
    root = ET.fromstring(xml)
    articles = {}
    for row in root.findall('./channel/item'):
        url = (row.findtext('link') or '').strip()
        parsed = urlparse(url)
        if parsed.hostname != 'www.animenewsnetwork.com' or parsed.scheme not in ('https','http'): continue
        url = parsed._replace(scheme='https').geturl()
        title = clean(row.findtext('title'),400)
        try: date = parsedate_to_datetime(row.findtext('pubDate')).astimezone(timezone.utc)
        except (TypeError,ValueError,AttributeError): continue
        if title and now-timedelta(days=90) <= date <= now:
            articles[url] = {'title':title,'url':url,'published_at':date.isoformat(),'excerpt':clean(row.findtext('description'),300),'source':'Anime News Network'}
    return sorted(articles.values(),key=lambda a:a['published_at'],reverse=True)[:15]


def collect():
    now = datetime.now(timezone.utc)
    local = now.astimezone(timezone(timedelta(hours=9)))
    data = build(request_api(local.year,SEASONS[(local.month-1)//3]),now)
    try:
        with urlopen(Request(NEWS,headers={'User-Agent':'Malmun/4.1 RSS reader'}),timeout=12) as response:
            data['news'] = parse_news(response.read(1_000_000),now)
        data['news_available'] = True
    except Exception as error:
        print('Article feed unavailable; keeping verified airing/trailer updates:',type(error).__name__)
    return data


def main():
    data = collect()
    (ROOT/'data/anime-v1.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print('Anime source verified:',len(data['trending']),len(data['seasonal']),len(data['news']),len(data['updates']))
    if '--inspect' in sys.argv: print('ANIME_FEED_JSON='+json.dumps(data,ensure_ascii=False))


if __name__ == '__main__': main()
