import json
import socket
from datetime import datetime, timezone, timedelta
from urllib.request import Request, urlopen
now=datetime.now(timezone(timedelta(hours=9)))
query='''query($year:Int,$season:MediaSeason){trending:Page(perPage:10){media(type:ANIME,isAdult:false,status:RELEASING,sort:TRENDING_DESC){id title{romaji english native}siteUrl description(asHtml:false)averageScore popularity trending format episodes status season seasonYear genres coverImage{large}nextAiringEpisode{episode airingAt}trailer{id site}}}seasonal:Page(perPage:10){media(type:ANIME,isAdult:false,seasonYear:$year,season:$season,sort:POPULARITY_DESC){id title{romaji english native}siteUrl description(asHtml:false)averageScore popularity trending format episodes status season seasonYear genres coverImage{large}nextAiringEpisode{episode airingAt}trailer{id site}}}}'''
try:
 print('JIKAN_DNS_FAMILIES', sorted({r[0] for r in socket.getaddrinfo('api.jikan.moe',443,type=socket.SOCK_STREAM)}))
except Exception as e: print('JIKAN_DNS_ERROR',type(e).__name__)
payload=json.dumps({'query':query,'variables':{'year':now.year,'season':['WINTER','SPRING','SUMMER','FALL'][(now.month-1)//3]}}).encode()
with urlopen(Request('https://graphql.anilist.co',data=payload,headers={'Content-Type':'application/json','Accept':'application/json','User-Agent':'Malmun/4.1'}),timeout=30) as response:
 data=json.load(response)
if data.get('errors') or len(data.get('data',{}).get('trending',{}).get('media',[]))<1: raise ValueError('AniList unavailable')
print('ANILIST_PROBE_JSON='+json.dumps({'fetched_at':datetime.now(timezone.utc).isoformat(),'year':now.year,'season':['winter','spring','summer','fall'][(now.month-1)//3],'response':data},ensure_ascii=False))
