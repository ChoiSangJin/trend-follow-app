import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/netflix.dart';
import '../data/netflix_repository.dart';
import '../state/netflix_provider.dart';
import '../state/briefing_provider.dart';
import '../state/conversation_provider.dart';
import 'home_screen.dart' show TopicScreen;
import 'anime_view.dart';
import 'conversation_views.dart' show LearningHistoryScreen;

Future<void> openNetflixLink(BuildContext context, Uri link) async {
  try {
    if (await launchUrl(link, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    /* Show a useful error. */
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('링크를 열지 못했어요. 연결과 브라우저를 확인해 주세요.')),
    );
  }
}

Future<void> saveNetflix(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('저장하지 못했어요. 다시 시도해 주세요.')));
    }
  }
}

class NetflixHomeScreen extends ConsumerStatefulWidget {
  const NetflixHomeScreen({super.key});
  @override
  ConsumerState<NetflixHomeScreen> createState() => _NetflixHomeScreenState();
}

class _NetflixHomeScreenState extends ConsumerState<NetflixHomeScreen> {
  int _tab = 0;
  bool _anime = false, _animeVisited = false;
  String _category = 'TV', _kind = '전체', _query = '';
  String? _week;
  bool _watched = false;
  void _open(NetflixTitle title, String week, bool comparable) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NetflixDetailScreen(
            title: title,
            week: week,
            comparable: comparable,
          ),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final result = ref.watch(netflixProvider);
    final records = ref.watch(netflixLibraryProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          bottom: TabBar(
            onTap: (index) => setState(() {
              _anime = index == 1;
              _animeVisited = _animeVisited || _anime;
            }),
            tabs: const [
              Tab(key: ValueKey("source-netflix"), text: "넷플릭스"),
              Tab(key: ValueKey("source-anime"), text: "애니"),
            ],
          ),
          title: const Text(
            '말문',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            IconButton(
              tooltip: '순위와 출처 안내',
              icon: const Icon(Icons.info_outline),
              onPressed: () => _anime
                  ? showAnimeInfo(context)
                  : showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('이 순위는 어디서 왔나요?'),
                        content: const SingleChildScrollView(
                          child: Text(
                            'Netflix Tudum이 공개한 한국 주간 Top 10입니다. 한국에서 시청한 순위이며 한국 제작 작품만을 뜻하지 않습니다. TV 목록에는 드라마·예능·애니 등이 함께 포함됩니다.\n\n집계 주간을 표시하며 실시간·오늘의 순위나 한국 전체 OTT 순위로 해석하지 않습니다. 이전 주와 비교할 수 있을 때만 상승·하락을 표시합니다. 누적 진입 주수는 연속 주수가 아닙니다. 국가별 시청자 수를 추정하지 않습니다.\n\n작품 소개는 출처에서 확인한 정보만 표시합니다. 확인하지 못한 정보는 비워 둡니다. 말문은 넷플릭스가 운영하거나 인증한 앱이 아닙니다.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('닫기'),
                          ),
                          TextButton(
                            onPressed: () => openNetflixLink(
                              context,
                              Uri.parse(netflixChartUrl),
                            ),
                            child: const Text('공식 순위 보기'),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
        body: IndexedStack(
          index: _anime ? 1 : 0,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _tab == 1
                    ? ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Text(
                            '내가 고른 작품',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('보고 싶어요'),
                                selected: !_watched,
                                onSelected: (_) =>
                                    setState(() => _watched = false),
                              ),
                              ChoiceChip(
                                label: const Text('봤어요'),
                                selected: _watched,
                                onSelected: (_) =>
                                    setState(() => _watched = true),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (!records.any((r) => r.watched == _watched))
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Text('작품에서 저장 버튼을 누르면 여기에 모여요.'),
                            ),
                          for (final record in records.where(
                            (r) => r.watched == _watched,
                          ))
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              title: Text(record.title.title),
                              subtitle: Text(
                                '${record.week} 종료 주간에 저장 · ${record.title.category == 'TV' ? 'TV' : '영화'}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  _open(record.title, record.week, false),
                            ),
                          const Divider(),
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const LegacySavedScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('이전 뉴스 보관함·메모'),
                          ),
                          const Text(
                            '내 목록은 이 기기에만 저장돼요.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : result.when(
                        data: (data) => _chart(data),
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('순위를 불러오지 못했어요. 연결 후 다시 시도해 주세요.'),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: () =>
                                      ref.invalidate(netflixProvider),
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            if (_animeVisited) const AnimeView() else const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: _anime
            ? null
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (value) => setState(() => _tab = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.trending_up),
                    label: '한국 Top 10',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.bookmarks_outlined),
                    label: '내 목록',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _chart(NetflixResult result) {
    final feed = result.feed;
    final week =
        feed.weeks.where((w) => w.key == _week).firstOrNull ?? feed.weeks.first;
    final all = week.charts[_category]!;
    final kinds = [
      '전체',
      ...all.map((t) => t.kind.isEmpty ? '미분류' : t.kind).toSet(),
    ];
    final kind = kinds.contains(_kind) ? _kind : '전체';
    final items = all
        .where(
          (t) =>
              (kind == '전체' || (t.kind.isEmpty ? '미분류' : t.kind) == kind) &&
              ('${t.title} ${t.originalTitle} ${t.season ?? ''}')
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    final stale = feed.stale(ref.watch(netflixClockProvider)());
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(netflixProvider);
        try {
          await ref.read(netflixProvider.future);
        } catch (_) {
          /* The error state offers retry. */
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          Text(
            '넷플릭스에서\n요즘 뭐 볼까?',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 20),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NETFLIX 공식 주간 TOP 10',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    week.label,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text('한국 시청 기준 · 주간 집계'),
                  if (result.origin != NetflixOrigin.network)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        '새 순위를 확인하지 못해 저장된 자료를 보여드려요. 집계 기간을 확인해 주세요.',
                      ),
                    ),
                  if (stale)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('최신 주간 자료가 아닐 수 있어요. 공식 순위에서 새 집계를 확인해 주세요.'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                key: const ValueKey('netflix-TV'),
                label: const Text('TV 프로그램'),
                selected: _category == 'TV',
                onSelected: (_) => setState(() {
                  _category = 'TV';
                  _kind = '전체';
                }),
              ),
              ChoiceChip(
                key: const ValueKey('netflix-Films'),
                label: const Text('영화'),
                selected: _category == 'Films',
                onSelected: (_) => setState(() {
                  _category = 'Films';
                  _kind = '전체';
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('작품 찾기 · 다른 주간'),
            children: [
              SizedBox(
                width: 280,
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: week.key,
                  underline: const SizedBox.shrink(),
                  items: feed.weeks
                      .map(
                        (w) => DropdownMenuItem(
                          value: w.key,
                          child: Text(
                            '${w.end.month}.${w.end.day} 종료 주간',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _week = v;
                    _kind = '전체';
                  }),
                ),
              ),
              TextField(
                key: const ValueKey('netflix-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '작품 이름으로 찾기',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              if (kinds.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: kinds
                        .map(
                          (k) => ChoiceChip(
                            label: Text(k),
                            selected: kind == k,
                            onSelected: (_) => setState(() => _kind = k),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${_category == 'TV' ? 'TV 프로그램' : '영화'} Top 10${kind != '전체' || _query.isNotEmpty ? ' · ${items.length}개 표시' : ''}',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text('필터를 사용해도 공식 순위는 그대로 표시해요.'),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Text('이 주간 Top 10에 맞는 작품이 없어요.'),
            ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: NetflixCard(
                title: item,
                comparable: week.comparable,
                onTap: () => _open(item, week.key, week.comparable),
              ),
            ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () => openNetflixLink(
              context,
              Uri.parse(
                '$netflixChartUrl/${_category == 'TV' ? 'tv' : 'films'}',
              ),
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Netflix Tudum 공식 순위'),
          ),
          const Text(
            '주간 순위는 취향이나 작품의 완성도를 뜻하지 않아요.\n말문은 넷플릭스의 비공식 독립 앱입니다.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.6),
          ),
        ],
      ),
    );
  }
}

class NetflixCard extends StatelessWidget {
  const NetflixCard({
    super.key,
    required this.title,
    required this.comparable,
    required this.onTap,
  });
  final NetflixTitle title;
  final bool comparable;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('netflix-title-${title.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 42 * MediaQuery.textScalerOf(context).scale(1),
              child: Text(
                '${title.rank}'.padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (title.season != null && title.season != title.title)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        title.seasonLabel!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      Text(
                        title.movement(comparable),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text('누적 ${title.weeks}주 진입'),
                      if (title.metadata['synopsis_credit'] is String)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            title.metadata['synopsis_credit'] as String,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (title.kind.isNotEmpty) Text(title.kind),
                    ],
                  ),
                  if (title.synopsis.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        title.synopsis,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.5),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    '작품 살펴보기 →',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class NetflixDetailScreen extends ConsumerWidget {
  const NetflixDetailScreen({
    super.key,
    required this.title,
    required this.week,
    required this.comparable,
  });
  final NetflixTitle title;
  final String week;
  final bool comparable;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref
        .watch(netflixLibraryProvider)
        .where((r) => r.title.id == title.id)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(title.category == 'TV' ? 'TV 프로그램' : '영화')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '한국 Netflix ${title.rank}위 · $week 종료 주간',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title.title,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (title.season != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(title.season!),
                ),
              const SizedBox(height: 16),
              if (title.image != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    title.image.toString(),
                    height: 210,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                title.metadata['synopsis_language'] == 'en'
                    ? '공식 작품 소개 · 영문'
                    : '어떤 작품인가요?',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                title.synopsis.isEmpty
                    ? '작품 소개는 공식 페이지에서 확인해 주세요.'
                    : title.synopsis,
                style: const TextStyle(height: 1.8),
              ),
              if (title.kind.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('분류 · ${title.kind}'),
                ),
              if (title.runtime.isNotEmpty) Text('분량 · ${title.runtime}'),
              if (title.cast.isNotEmpty) Text('출연 · ${title.cast}'),
              const SizedBox(height: 24),
              Text(
                '순위에서 확인한 점',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                '${title.movement(comparable)} · 한국 Top 10 누적 ${title.weeks}주 진입',
                style: const TextStyle(height: 1.7),
              ),
              if (title.previousRank != null && comparable)
                Text('지난주 ${title.previousRank}위 → 이 주간 ${title.rank}위'),
              const Text(
                '누적 진입 주수는 연속 진입 주수가 아닙니다. 순위만으로 화제가 된 이유나 시청자 수를 알 수는 없어요.',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => saveNetflix(
                      context,
                      () => ref
                          .read(netflixLibraryProvider.notifier)
                          .set(
                            title,
                            week,
                            remove: record != null && !record.watched,
                          ),
                    ),
                    icon: Icon(
                      record != null && !record.watched
                          ? Icons.bookmark
                          : Icons.bookmark_outline,
                    ),
                    label: Text(
                      record != null && !record.watched
                          ? '보고 싶은 작품에 저장됨'
                          : '보고 싶어요',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => saveNetflix(
                      context,
                      () => ref
                          .read(netflixLibraryProvider.notifier)
                          .set(
                            title,
                            week,
                            watched: true,
                            remove: record?.watched == true,
                          ),
                    ),
                    icon: Icon(
                      record?.watched == true
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                    ),
                    label: const Text('봤어요'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => openNetflixLink(context, title.watch),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Netflix에서 확인'),
              ),
              TextButton(
                onPressed: () => openNetflixLink(context, title.source),
                child: const Text('작품 정보 출처 보기'),
              ),
              const SizedBox(height: 20),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('이 얘기를 꺼낸다면'),
                children: [
                  Text(
                    '“넷플릭스 Top 10에 ${title.title} 있던데, 봤어요?”',
                    style: const TextStyle(height: 1.7),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: '넷플릭스 Top 10에 ${title.title} 있던데, 봤어요?',
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('문장을 복사했어요.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('첫마디 복사'),
                  ),
                  const Text(
                    '안 봤다면 줄거리나 감상을 아는 척하지 않아도 돼요. 본 상대에게는 스포일러 없이 어땠는지 물어보세요.',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LegacySavedScreen extends ConsumerWidget {
  const LegacySavedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedProvider);
    final learning = ref.watch(learningProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('이전 뉴스 보관함·메모')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('이전에 저장한 뉴스와 메모입니다. 기사 날짜를 확인해 주세요.'),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LearningHistoryScreen(
                  onOpen: (topic) => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TopicScreen(topic: topic),
                    ),
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.edit_note),
            label: Text('내가 남긴 이야기 · ${learning.records.length}개'),
          ),
          if (saved.isEmpty) const Text('저장한 뉴스가 없어요.'),
          for (final topic in saved)
            ListTile(
              title: Text(topic.title),
              subtitle: Text(topic.category),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TopicScreen(topic: topic),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
