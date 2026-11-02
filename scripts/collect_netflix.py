"""Build the Korean weekly Netflix chart from the official public TSV.
Ranks are Netflix's country chart; no inferred Korean view counts or buzz scores.
"""
import csv
import io
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
        data = response.read(limit + 1)
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
                items.append({'id': category + ':' + '|'.join(key), 'title': key[0], 'season': key[1] or None,
                              'rank': int(r['weekly_rank']), 'previous_rank': old.get(key), 'weeks_in_top10': total})
            charts[category] = items
        if len(charts) == 2:
            weeks.append({'week': end, 'charts': charts})
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
        for slug in ('tv', 'films'):
            Path(f'/tmp/netflix-{slug}.html').write_text(fetch(CHART + '/' + slug, 10_000_000))


if __name__ == '__main__':
    main()
