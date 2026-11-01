"""Aggregate validated Korea-only Google Trends RSS plus explicitly curated editorial data.

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
RSS_URL = 'https://trends.google.com/trending/rss?geo=KR&hl=ko'


def traffic_count(value: str) -> int:
    import re
    match = re.fullmatch(r'([0-9]+(?:[.][0-9]+)?)([KM]?)', value.replace(',', '').replace('+', '').strip().upper())
    if not match:
        return 0
    return int(float(match[1]) * {'': 1, 'K': 1000, 'M': 1000000}[match[2]])


def parse_keywords(payload: bytes) -> list[dict]:
    root = ET.fromstring(payload)
    channel = root.find('channel')
    if channel is None:
        raise ValueError('Missing feed channel')
    from urllib.parse import urlparse, parse_qs
    link = channel.findtext('link', '')
    if parse_qs(urlparse(link).query).get('geo') != ['KR']:
        raise ValueError('Expected geo=KR in Google Trends response; refusing other regions')
    keywords = []
    seen = set()
    for item in root.findall('./channel/item'):
        title = (item.findtext('title') or '').strip()
        traffic = item.findtext('{https://trends.google.com/trending/rss}approx_traffic', '')
        if not title or title in seen or not any('가' <= c <= '힣' for c in title) or traffic_count(traffic) < 1000:
            continue
        seen.add(title)
        keywords.append({
            'rank': len(keywords) + 1,
            'keyword': title,
            'search_volume': traffic,
            'source_url': item.findtext('link', ''),
            'source': 'Google Trends 대한민국 · 한글 포함 · 검색량 1천회 이상',
        })
        if len(keywords) == 20:
            break
    if not keywords:
        raise ValueError('Korea Trends has no items meeting the published filters; preserving previous feed')
    return keywords


def build_feed(payload: bytes, editorial: dict, timestamp: str) -> dict:
    categories = {'keywords': parse_keywords(payload)}
    for name in ('memes', 'hotplaces'):
        entries = editorial.get(name, [])
        if not isinstance(entries, list) or any(not isinstance(x, dict) for x in entries):
            raise ValueError(f'editorial.{name} must be a list of objects')
        categories[name] = entries
    return {'region': 'KR', 'feed_type': 'korean_trends', 'updated_at': timestamp, 'is_demo': False, 'categories': categories}


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
