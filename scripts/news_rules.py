"""Shared headline rules, also applied when reading persisted news observations."""
import re

SPORT_MARKERS = re.compile(r'축구|야구|농구|배구|올림픽|월드컵|K리그|KBO|NBA|MLB|골프|테니스|탁구|배드민턴|수영|손흥민|이강인|김민재|오타니|류현진', re.I)
SPORT_EXCLUDE = re.compile(r'조카|예능|드라마|배우|가수|출연|화보|차림|팬미팅|수면제|내기골프|가로챈|가로채|사기범|사기죄|사기\s*혐의|사기행각|도박|불법\s*베팅|입건|검거|구속(?:\s*(?:영장|기소|송치)|됐|된)|체포|범죄|징역')


def sports_story(title):
    return bool(SPORT_MARKERS.search(title)) and not SPORT_EXCLUDE.search(title)
