"""Aggregate the validated Korean edition of Google News RSS plus explicitly curated editorial data.

On failure exit nonzero and leave the previously published feed untouched.
No scraped or fabricated congestion/demographic metrics are generated.
"""
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
RSS_URL = 'https://news.google.com/rss?hl=ko&gl=KR&ceid=KR:ko'


def parse_keywords(payload: bytes) -> list[dict]:
    root = ET.fromstring(payload)
    channel = root.find('channel')
    if channel is None or channel.findtext('language', '').lower() not in ('ko', 'ko-kr'):
        raise ValueError('Expected a Korean-language news feed')
    if 'ceid=KR' not in channel.findtext('link', ''):
        raise ValueError('Expected the Korea edition of Google News')
    keywords = []
    seen = set()
    for item in root.findall('./channel/item'):
        title = (item.findtext('title') or '').strip()
        if not title or title in seen:
            continue
        seen.add(title)
        keywords.append({
            'rank': len(keywords) + 1,
            'keyword': title,
            'search_volume': '뉴스',
            'source_url': item.findtext('link', ''),
            'source': 'Google 뉴스 한국판 · ' + item.findtext('source', '언론사 미제공'),
        })
        if len(keywords) == 20:
            break
    if not keywords:
        raise ValueError('Korean news RSS contains no items; preserving previous feed')
    return keywords


def build_feed(payload: bytes, editorial: dict, timestamp: str) -> dict:
    categories = {'keywords': parse_keywords(payload)}
    for name in ('memes', 'hotplaces'):
        entries = editorial.get(name, [])
        if not isinstance(entries, list) or any(not isinstance(x, dict) for x in entries):
            raise ValueError(f'editorial.{name} must be a list of objects')
        categories[name] = entries
    return {'region': 'KR', 'feed_type': 'korean_news', 'updated_at': timestamp, 'is_demo': False, 'categories': categories}


def main() -> None:
    request = Request(RSS_URL, headers={'User-Agent': 'FollowMZ/1.0 RSS aggregator'})
    with urlopen(request, timeout=30) as response:
        payload = response.read(2_000_001)
    if len(payload) > 2_000_000:
        raise ValueError('RSS payload exceeded size limit')
    editorial = json.loads((ROOT / 'data/editorial.json').read_text(encoding='utf-8'))
    feed = build_feed(payload, editorial,
                      datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'))
    destination = ROOT / 'data/trends.json'
    temporary = destination.with_suffix('.tmp')
    temporary.write_text(json.dumps(feed, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(temporary, destination)
    print(f"Published {len(feed['categories']['keywords'])} Korean keywords")


if __name__ == '__main__':
    main()
