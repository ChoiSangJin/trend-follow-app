"""Build the Korean weekly Netflix chart from the official public TSV.
Ranks are Netflix's country chart; no inferred Korean view counts or buzz scores.
"""
import csv
import ast
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
    with urlopen(Request(url, headers={'User-Agent': 'Malmun/4.0 (public Netflix Top 10 data)'}), timeout=60) as response:
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
    previous = (week - timedelta(days=7)).isoformat()
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


def main():
    result = build(fetch(SOURCE))
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
        inspection = []
        for slug in ('tv', 'films'):
            html = fetch(CHART + '/' + slug, 10_000_000)
            for attrs, body in re.findall(r'<script([^>]*)>(.*?)</script>', html, re.S):
                try:
                    payload = json.loads(body)
                except ValueError:
                    match = re.search(r"graphql\s*=\s*JSON.parse\(('(?:\\.|[^'\\])*')\)", body)
                    if match:
                        payload = json.loads(ast.literal_eval(match.group(1)))
                    else:
                        inspection.append({'attrs': attrs[:200], 'prefix': body[:100]})
                        continue
                def walk(node, path=''):
                    if isinstance(node, dict):
                        if any(k.lower() in ('title', 'showtitle', 'name', 'videos', 'titles', 'synopsis', 'rank', 'weeklyrank') for k in node):
                            inspection.append({'path': path, 'node': {k:(v if not isinstance(v,(dict,list)) else str(v)[:800]) for k,v in node.items()}})
                        for k,v in node.items(): walk(v, path + '.' + k)
                    elif isinstance(node, list):
                        for i,v in enumerate(node): walk(v, path + '[' + str(i) + ']')
                walk(payload)
        print('NETFLIX_SOURCE_JSON=' + json.dumps(inspection[:500], ensure_ascii=False))


if __name__ == '__main__':
    main()
