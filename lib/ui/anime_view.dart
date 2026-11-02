import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/anime.dart';
import '../data/anime_repository.dart';
import '../state/anime_provider.dart';
import 'netflix_screen.dart' show openNetflixLink;

Future<void> showAnimeInfo(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('애니 정보의 출처와 기준'),
    content: const SingleChildScrollView(
      child: Text(
        'AniList 공식 API의 방영 중 관심순과 분기 신작입니다. 관심순은 AniList 내 활동 기준이며 한국 시청 순위가 아닙니다. 평점은 별도의 100점 기준 지표입니다.\n\n작품명·소개는 제공된 원문이며 영문·일문이 포함됩니다. 방영 예정은 수집 시점 정보로 국내 OTT 공개 시각과 다를 수 있습니다. 예고편은 API에서 제공하는 링크입니다.\n\n기사 소식은 Anime News Network 공개 RSS에서 확인한 최근 90일 기사입니다. 원본 캐시와 수집 주기에 따라 정보 반영이 늦을 수 있습니다. Netflix 순위와 합산하지 않습니다.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
  ),
);

class AnimeView extends ConsumerStatefulWidget {
  const AnimeView({super.key});
  @override
  ConsumerState<AnimeView> createState() => _AnimeViewState();
}

class _AnimeViewState extends ConsumerState<AnimeView> {
  int _view = 0;
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(animeProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('애니 정보를 불러오지 못했어요. 연결 후 다시 시도해 주세요.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(animeProvider),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ),
      data: (result) {
        final feed = result.feed;
        final items = (_view == 0 ? feed.trending : feed.seasonal)
            .where(
              (i) => '${i.title} ${i.original} ${i.japanese}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
            )
            .toList();
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(animeProvider);
            try {
              await ref.read(animeProvider.future);
            } catch (_) {
              /* Error state offers retry. */
            }
          },
          child: ListView(
            key: PageStorageKey('anime-view-$_view'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                '애니, 지금 뭐 볼까?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'AniList · ${feed.seasonLabel}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text('${animeDate(feed.fetchedAt)} 수집'),
              const SizedBox(height: 6),
              const Text('해외 커뮤니티 관심도·작품 정보 · 한국 시청 순위와 별도'),
              if (result.origin != AnimeOrigin.network)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('새 정보를 받지 못해 저장된 자료를 보여드려요. 수집 시각을 확인해 주세요.'),
                ),
              if (feed.stale(ref.watch(animeClockProvider)()))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('48시간 이상 지난 자료입니다. 방영 상태나 새 소식이 달라졌을 수 있어요.'),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final entry in {
                    0: '방영 중 관심순',
                    1: '분기 신작',
                    2: '소식',
                  }.entries)
                    ChoiceChip(
                      key: ValueKey('anime-section-${entry.key}'),
                      label: Text(entry.value),
                      selected: _view == entry.key,
                      onSelected: (_) => setState(() => _view = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_view != 2) ...[
                TextField(
                  key: const ValueKey('anime-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '작품 원제·영문·일문 검색',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                if (_view == 1) const Text('순위가 아닌 분기별 작품 목록입니다.'),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('검색에 맞는 작품이 없어요.'),
                  ),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Card(
                      child: ListTile(
                        key: ValueKey('anime-title-${item.id}'),
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(
                          '${_view == 0 ? '${item.position}. ' : ''}${item.title}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '${item.score == null ? '평가 집계 중' : 'AniList 평점 ${item.score} / 100'}${item.scoredBy == null ? '' : ' · 평가 ${item.scoredBy}명'}\n${item.format}${item.episodes == null || item.episodes == 0 ? '' : ' · ${item.episodes}화'}',
                            style: const TextStyle(height: 1.7),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                AnimeDetailScreen(title: item, feed: feed),
                          ),
                        ),
                      ),
                    ),
                  ),
              ] else ...[
                const Text('방영 예정·예고편과 최근 기사 · 출처별 표시'),
                if (!feed.newsAvailable)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('기사 소식을 확인하지 못해 방영 예정·예고편 정보를 표시합니다.'),
                  ),
                if (feed.news.isEmpty && feed.updates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text('현재 표시할 수 있는 최근 소식이 없어요.'),
                  ),
                for (final article in feed.news)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Anime News Network',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              article.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(animeDate(article.publishedAt)),
                            if (article.excerpt.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  article.excerpt,
                                  style: const TextStyle(height: 1.7),
                                ),
                              ),
                            TextButton.icon(
                              onPressed: () =>
                                  openNetflixLink(context, article.url),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('기사 원문'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (feed.updates.isNotEmpty)
                  ExpansionTile(
                    title: Text('방영 예정·예고편 ${feed.updates.length}개'),
                    children: [
                      for (final update in feed.updates)
                        Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(update.animeTitle),
                            subtitle: Text(
                              '${update.title}${update.airingAt == null ? '\nAPI 제공 예고편 · 게시일 미제공' : '\n${animeDate(update.airingAt!)} · 수집 시점 예정 정보'}',
                            ),
                            trailing: const Icon(Icons.open_in_new),
                            onTap: () => openNetflixLink(context, update.url),
                          ),
                        ),
                    ],
                  ),
              ],
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => showAnimeInfo(context),
                child: const Text('애니 정보의 출처와 기준'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AnimeDetailScreen extends StatelessWidget {
  const AnimeDetailScreen({super.key, required this.title, required this.feed});
  final AnimeTitle title;
  final AnimeFeed feed;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('애니 작품 정보')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              title.title,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (title.original != title.title)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(title.original),
              ),
            if (title.japanese.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(title.japanese),
              ),
            const SizedBox(height: 16),
            if (title.image != null)
              Image.network(
                title.image.toString(),
                height: 260,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            const SizedBox(height: 16),
            Text(
              title.score == null
                  ? '평가 집계 중'
                  : 'AniList 이용자 평점 ${title.score} / 100',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (title.scoredBy != null) Text('평가 참여 ${title.scoredBy}명'),
            if (title.members != null)
              Text('AniList 목록 등록 ${title.members}명 · 실제 시청자 수가 아닙니다.'),
            const SizedBox(height: 12),
            Text(
              '${title.format} · ${title.airing ? '방영 중' : title.json['status']}',
            ),
            Text(
              title.episodes == null || title.episodes == 0
                  ? '회차 미정'
                  : '${title.episodes}화',
            ),
            if (title.genres.isNotEmpty) Text(title.genres.join(' · ')),
            const SizedBox(height: 24),
            Text(
              '작품 소개 · 제공된 원문',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              title.synopsis.isEmpty
                  ? '제공된 소개가 없어요. 원문에서 확인해 주세요.'
                  : title.synopsis,
              style: const TextStyle(height: 1.8),
            ),
            const SizedBox(height: 20),
            Text('${animeDate(feed.fetchedAt)} 수집 · AniList'),
            const Text('국내 OTT 제공 여부와 한국 공개 일정은 별도 확인이 필요합니다.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => openNetflixLink(context, title.url),
              icon: const Icon(Icons.open_in_new),
              label: const Text('AniList 작품 원문'),
            ),
            const SizedBox(height: 20),
            for (final article in feed.updates.where(
              (n) => n.json['anime_id'] == title.id,
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(article.title),
                subtitle: Text(
                  article.airingAt == null
                      ? 'API 제공 예고편'
                      : animeDate(article.airingAt!),
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => openNetflixLink(context, article.url),
              ),
          ],
        ),
      ),
    ),
  );
}
