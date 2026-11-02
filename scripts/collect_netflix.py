"""Build the Korean weekly Netflix chart from the official public TSV.
Ranks are Netflix's country chart; no inferred Korean view counts or buzz scores.
"""
import csv
import ast
from html.parser import HTMLParser
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor
from http.client import IncompleteRead
import io
import re
import json
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'https://www.netflix.com/tudum/top10/data/all-weeks-countries.tsv'
CHART = 'https://www.netflix.com/tudum/top10/south-korea'


def fetch(url, limit=100_000_000):
    with urlopen(Request(url, headers={'User-Agent': 'Mozilla/5.0 (compatible; Malmun/4.0)', 'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.5'}), timeout=60) as response:
        try:
            data = response.read(limit + 1)
        except IncompleteRead as error:
            if url == SOURCE or b'</html>' not in error.partial[-2000:]:
                raise
            data = error.partial
    if len(data) > limit:
        raise ValueError('Source exceeds size limit')
    return data.decode('utf-8-sig')


def build(text, now=None):
    now = now or datetime.now(timezone.utc)
    reader = csv.DictReader(io.StringIO(text), delimiter='\t')
    required = {'country_name', 'week', 'category', 'weekly_rank', 'show_title', 'season_title', 'cumulative_weeks_in_top_10'}
    if not required.issubset(reader.fieldnames or []):
        raise ValueError('Official country TSV columns changed')
    rows = [r for r in reader if r['country_name'] == 'South Korea' and r['category'] in ('TV', 'Films')]
    if not rows:
        raise ValueError('No South Korea charts')
    latest = max(r['week'] for r in rows)
    week = date.fromisoformat(latest)
    if week.weekday() != 6 or week > now.date():
        raise ValueError('Invalid chart week')
    weeks = []
    for offset in range(4):
        end = (week - timedelta(days=7 * offset)).isoformat()
        charts = {}
        for category in ('TV', 'Films'):
            current = sorted((r for r in rows if r['week'] == end and r['category'] == category), key=lambda r: int(r['weekly_rank']))
            if [int(r['weekly_rank']) for r in current] != list(range(1, 11)):
                if offset == 0:
                    raise ValueError(f'Incomplete or duplicate {category} Top 10')
                continue
            old = {(r['show_title'], r['season_title']): int(r['weekly_rank']) for r in rows if r['week'] == (date.fromisoformat(end) - timedelta(days=7)).isoformat() and r['category'] == category}
            items = []
            seen = set()
            for r in current:
                key = (r['show_title'].strip(), r['season_title'].strip())
                if not key[0] or key in seen:
                    raise ValueError('Empty or duplicate title')
                seen.add(key)
                total = int(r['cumulative_weeks_in_top_10'])
                if total < 1:
                    raise ValueError('Invalid weeks in Top 10')
                items.append({'id': category + ':' + '|'.join(key), 'title': key[0], 'season': None if key[1] in ('', 'N/A') else key[1],
                              'rank': int(r['weekly_rank']), 'previous_rank': old.get(key), 'weeks_in_top10': total})
            charts[category] = items
        if len(charts) == 2:
            weeks.append({'week': end, 'previous_available': all(sum(1 for r in rows if r['week'] == (date.fromisoformat(end) - timedelta(days=7)).isoformat() and r['category'] == c) == 10 for c in ('TV', 'Films')), 'charts': charts})
    return {'schema_version': 1, 'country': 'KR', 'source_url': SOURCE, 'chart_url': CHART,
            'fetched_at': now.isoformat(), 'weeks': weeks}



def graph_data(html):
    """Read JSON already embedded in the public page; never evaluate JS."""
    for _, body in re.findall(r'<script([^>]*)>(.*?)</script>', html, re.S):
        match = re.search(r"graphql\s*=\s*JSON.parse\(('(?:\\.|[^'\\])*')\)", body)
        if match:
            value = json.loads(ast.literal_eval(match.group(1)))
            if isinstance(value.get('data'), dict):
                return value['data']
    raise ValueError('Public chart markup changed')


def page_chart(html, category):
    if 'South Korea' not in html:
        raise ValueError('Country not confirmed')
    candidates = {}
    for key, entity in graph_data(html).items():
        if not key.startswith('PulseTop10ItemEntity:') or not isinstance(entity, dict):
            continue
        chart, video = entity.get('top10', {}), entity.get('top10Video', {})
        wanted = ('SERIES', 'TV') if category == 'TV' else ('FILM', 'FILMS', 'MOVIE', 'MOVIES')
        if chart.get('category') not in wanted:
            continue
        rank = chart.get('weeklyRank')
        if not any(r.get('countryId') == 'KR' and r.get('rank') == rank for r in entity.get('countryRanks', [])):
            continue
        title = (video.get('parentShow') or {}).get('title') or video.get('title')
        season = video.get('title') if category == 'TV' else None
        season_key = season or 'N/A'
        item = {'id': category + ':' + title + '|' + season_key, 'title': title, 'season': season,
                'rank': rank, 'previous_rank': None, 'weeks_in_top10': chart['cumulativeWeeksInTop10']}
        display = entity.get('displayVideo', {}).get('video', {}) or {}
        netflix_id = (display.get('parentShow') or {}).get('videoId') or display.get('videoId') or video.get('videoId')
        if netflix_id:
            item['metadata'] = {'source_url': CHART + ('/tv' if category == 'TV' else ''),
                                'title_url': f'https://www.netflix.com/kr/title/{netflix_id}?locale=ko-KR',
                                'watch_url': CHART + ('/tv' if category == 'TV' else ''),
                                'synopsis': video.get('shortSynopsis') or '', 'synopsis_language': 'en'}
        key = (chart['weekEndDate'], rank)
        if key in candidates and candidates[key]['id'] != item['id']:
            raise ValueError('Conflicting country ranks')
        candidates[key] = item
    dates = {k[0] for k in candidates}
    if len(dates) != 1 or sorted(k[1] for k in candidates) != list(range(1, 11)):
        raise ValueError('Incomplete country chart page: ' + str(sorted(dates)))
    end = dates.pop()
    return end, [candidates[(end, n)] for n in range(1, 11)]


class PublicTitleParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.meta = {}
        self.scripts = []
        self._script = None
        self.h1 = []
        self._h1 = False
        self.synopsis = []
        self._synopsis = False
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'h1': self._h1 = True
        if attrs.get('data-uia') == 'title-info-synopsis': self._synopsis = True
        if tag == 'meta' and attrs.get('content'):
            self.meta[attrs.get('property') or attrs.get('name')] = attrs['content']
        if tag == 'script' and attrs.get('type') == 'application/ld+json':
            self._script = ''
    def handle_data(self, data):
        if self._h1: self.h1.append(data)
        if self._synopsis: self.synopsis.append(data)
        if self._script is not None:
            self._script += data
    def handle_endtag(self, tag):
        if tag == 'h1': self._h1 = False
        if tag in ('div', 'span'): self._synopsis = False
        if tag == 'script' and self._script is not None:
            try: self.scripts.append(json.loads(self._script))
            except ValueError: pass
            self._script = None


def title_metadata(html, url):
    parser = PublicTitleParser()
    parser.feed(html)
    nodes = []
    def walk(value):
        if isinstance(value, dict):
            types = value.get('@type', [])
            if isinstance(types, str): types = [types]
            if set(types) & {'TVSeries', 'Movie'}: nodes.append(value)
            for child in value.values(): walk(child)
        elif isinstance(value, list):
            for child in value: walk(child)
    for script in parser.scripts: walk(script)
    if not nodes:
        raise ValueError('No public title metadata')
    node = nodes[0]
    if urlparse(node.get('url', url)).path.rstrip('/').split('/')[-1] != urlparse(url).path.split('/')[-1]:
        raise ValueError('Title identity mismatch')
    name = ''.join(parser.h1).strip() or node.get('name', '')
    description = ''.join(parser.synopsis).strip() or node.get('description', '')
    genres = node.get('genre', [])
    if isinstance(genres, str): genres = [genres]
    genre_text = ' '.join(genres)
    # Only use Korean metadata when the page actually supplies it.
    result = {'source_url': url, 'watch_url': url}
    if re.search('[가-힣]', name): result['local_title'] = name
    if re.search('[가-힣]', description):
        result['synopsis'] = description
        result['synopsis_language'] = 'ko'
    if re.search('애니|Anime|Animation', genre_text, re.I): result['kind'] = '애니'
    elif re.search('리얼리티|예능|버라이어티|토크쇼|Reality|Variety', genre_text, re.I): result['kind'] = '예능'
    elif re.search('드라마|Drama', genre_text, re.I): result['kind'] = '드라마'
    actors = node.get('actor', [])
    if isinstance(actors, dict): actors = [actors]
    names = [a['name'] for a in actors if isinstance(a, dict) and a.get('name')]
    if names: result['cast'] = ', '.join(names[:6])
    duration = node.get('duration')
    if isinstance(duration, str) and re.fullmatch(r'PT(?:(\d+)H)?(?:(\d+)M)?', duration):
        match = re.fullmatch(r'PT(?:(\d+)H)?(?:(\d+)M)?', duration)
        minutes = int(match.group(1) or 0) * 60 + int(match.group(2) or 0)
        if minutes: result['runtime'] = str(minutes) + '분'
    image = node.get('image') or parser.meta.get('og:image')
    if isinstance(image, list): image = image[0] if image else None
    if isinstance(image, dict): image = image.get('url')
    if isinstance(image, str) and urlparse(image).scheme == 'https' and urlparse(image).hostname.endswith(('.nflximg.net', '.nflxso.net')):
        result['image_url'] = image
    return result


def enrich(result, fetcher=fetch):
    """Prefer the newer public chart if both Korean categories agree on the week."""
    pages = {}
    for category, suffix in [('TV', '/tv'), ('Films', '')]:
        try:
            pages[category] = page_chart(fetcher(CHART + suffix, 10_000_000), category)
        except Exception as error:
            print('Public chart unavailable:', category, type(error).__name__)
    if len(pages) == 2 and pages['TV'][0] == pages['Films'][0]:
        end = pages['TV'][0]
        date_end = date.fromisoformat(end)
        if date_end.weekday() != 6 or date_end > datetime.now(timezone.utc).date():
            raise ValueError('Invalid public chart date')
        new_week = {'week': end, 'charts': {c: pages[c][1] for c in pages}, 'previous_available': False}
        old_week = next((w for w in result['weeks'] if w['week'] == (date_end - timedelta(days=7)).isoformat()), None)
        if old_week:
            new_week['previous_available'] = True
            for category, items in new_week['charts'].items():
                old = {i['id']: i['rank'] for i in old_week['charts'][category]}
                for item in items: item['previous_rank'] = old.get(item['id'])
        if end >= result['weeks'][0]['week']:
            result['weeks'] = [new_week] + [w for w in result['weeks'] if w['week'] < end][:3]
    elif pages:
        print('Retaining TSV charts: public categories did not agree')
    # Match exact title+season identities, never loose title search.
    refs = {item['id']: item.get('metadata') for _, items in pages.values() for item in items if item.get('metadata')}
    for week in result['weeks']:
        for items in week['charts'].values():
            for item in items:
                if item['id'] in refs:
                    item['metadata'] = refs[item['id']]
    links_path = ROOT / 'data/netflix-title-links.json'
    links = json.loads(links_path.read_text()) if links_path.exists() else {}
    for items in result['weeks'][0]['charts'].values():
        for item in items:
            if item['title'] in links and item.get('metadata'):
                item['metadata']['title_url'] = links[item['title']]
    latest = [i for items in result['weeks'][0]['charts'].values() for i in items if i.get('metadata')]
    def load(item):
        url = item['metadata']['title_url']
        try:
            loaded = title_metadata(fetcher(url, 10_000_000), url)
            merged = {**item['metadata'], **loaded}
            if loaded.get('synopsis_language') != 'ko': merged['source_url'] = item['metadata']['source_url']
            return item['id'], merged
        except Exception as error:
            print('Title metadata unavailable:', item['title'], type(error).__name__)
            return item['id'], item['metadata']
    with ThreadPoolExecutor(max_workers=4) as pool:
        metadata = dict(pool.map(load, latest))
    for week in result['weeks']:
        for items in week['charts'].values():
            for item in items:
                if item['id'] in metadata: item['metadata'] = metadata[item['id']]
    return result


def apply_editorial(result, known, translations):
    for week in result['weeks']:
        for items in week['charts'].values():
            for item in items:
                metadata = item.get('metadata', {})
                previous = known.get(item['id'], {})
                if metadata.get('synopsis_language') != 'ko' and previous.get('synopsis_language') == 'ko':
                    metadata = dict(previous)
                entry = translations.get(item['id'])
                if metadata.get('synopsis_language') != 'ko' and entry and entry['source_synopsis'] == metadata.get('synopsis'):
                    metadata['original_synopsis'] = metadata['synopsis']
                    metadata['synopsis'] = entry['translation']
                    metadata['synopsis_language'] = 'ko'
                    metadata['synopsis_credit'] = 'Netflix 공식 소개 · 말문 번역'
                if metadata: item['metadata'] = metadata
    images = {}
    for items in result['weeks'][0]['charts'].values():
        for item in items:
            image = item.get('metadata', {}).get('image_url')
            if image: images.setdefault(image, set()).add(item['title'])
    # Shared artwork across unrelated titles is usually a generic fallback image.
    for week in result['weeks']:
        for items in week['charts'].values():
            for item in items:
                metadata = item.get('metadata', {})
                if len(images.get(metadata.get('image_url'), set())) > 1:
                    metadata.pop('image_url', None)
    return result

def main():
    result = enrich(build(fetch(SOURCE)))
    known = json.loads((ROOT / 'data/netflix-metadata.json').read_text())['titles']
    editorial = json.loads((ROOT / 'data/netflix-editorial.json').read_text())['translations']
    result = apply_editorial(result, known, editorial)
    path = ROOT / 'data/netflix-kr-v1.json'
    # Never replace a newer chart with a stale response.
    if path.exists():
        old = json.loads(path.read_text())
        if old['weeks'][0]['week'] > result['weeks'][0]['week']:
            raise ValueError('Refusing to roll the published chart back')
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print('Official Korean Netflix chart:', result['weeks'][0]['week'])
    print('TV:', [i['title'] for i in result['weeks'][0]['charts']['TV']])
    if '--inspect' in sys.argv:
        print('NETFLIX_FEED_JSON=' + json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
