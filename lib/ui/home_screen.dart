import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/trends.dart';
import '../state/trend_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  Future<void> _open(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) { /* Report unsupported intents without crashing. */ }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열 수 없습니다. 브라우저나 지도 앱을 확인해 주세요.')));
    }
  }

  Future<void> _map(HotPlace place, String service) async {
    final query = place.mapQuery;
    final native = service == 'naver'
      ? Uri(scheme: 'nmap', host: 'search', queryParameters: {
          'query': query, 'appname': 'com.followmz.app'})
      : Uri(scheme: 'kakaomap', host: 'search', queryParameters: {'q': query});
    try {
      if (await canLaunchUrl(native) &&
          await launchUrl(native, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) { /* Fall back to the HTTPS map when an app is unavailable. */ }
    if (!mounted) return;
    await _open(service == 'naver'
      ? Uri.https('map.naver.com', '/p/search/$query')
      : Uri.https('map.kakao.com', '/link/search/$query'));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trendProvider);
    final feed = state.valueOrNull;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Follow MZ', style: TextStyle(fontWeight: FontWeight.w800)),
          Text(_updated(feed), style: Theme.of(context).textTheme.labelSmall),
        ]),
        actions: [IconButton(tooltip: '새로고침',
          onPressed: state.isLoading ? null : () => ref.read(trendProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh_rounded)), const SizedBox(width: 8)],
      ),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [
          if (feed?.isDemo == true) _notice('예시 데이터 · 실시간 정보가 아닙니다.', Icons.info_outline),
          if (state.hasError && feed != null)
            _notice('업데이트 실패 · 마지막으로 불러온 정보를 표시합니다.', Icons.wifi_off),
          if (state.isLoading && feed != null) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: RefreshIndicator(
            onRefresh: () => ref.read(trendProvider.notifier).refresh(),
            child: state.isLoading && feed == null ? const _Skeleton()
              : feed == null ? _empty(error: true)
              : _content(feed, colors),
          )),
        ]))),
      bottomNavigationBar: NavigationBar(selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_fire_department_outlined),
            selectedIcon: Icon(Icons.local_fire_department), label: '실시간 키워드'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble), label: '밈 & 유행어'),
          NavigationDestination(icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place), label: '핫플레이스'),
        ]),
    );
  }

  String _updated(TrendFeed? feed) {
    final date = feed?.updatedAt;
    if (date == null) return '새로운 흐름을 발견하는 곳';
    final korea = date.toUtc().add(const Duration(hours: 9));
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${korea.month}.${pad(korea.day)} ${pad(korea.hour)}:${pad(korea.minute)} KST 업데이트';
  }

  Widget _notice(String message, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Row(children: [Icon(icon, size: 16), const SizedBox(width: 8),
      Expanded(child: Text(message, style: Theme.of(context).textTheme.labelMedium))]));

  Widget _empty({bool error = false}) => LayoutBuilder(builder: (context, constraints) =>
    ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
      SizedBox(height: constraints.maxHeight * .18),
      Icon(error ? Icons.cloud_off_rounded : Icons.explore_outlined, size: 64),
      const SizedBox(height: 20),
      Text(error ? '지금은 소식을 불러올 수 없어요' : '새로운 소식을 준비 중이에요',
        textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
      const Padding(padding: EdgeInsets.all(16), child: Text(
        '잠시 후 다시 확인하거나 아래로 당겨 새로고침해 주세요.', textAlign: TextAlign.center)),
      Center(child: FilledButton.icon(
        onPressed: () => ref.read(trendProvider.notifier).refresh(),
        icon: const Icon(Icons.refresh), label: const Text('다시 시도'))),
    ]));

  Widget _content(TrendFeed feed, ColorScheme colors) {
    final count = switch (_tab) { 0 => feed.keywords.length, 1 => feed.memes.length, _ => feed.places.length };
    if (count == 0) return _empty();
    return ListView.separated(
      key: PageStorageKey('category-$_tab'), physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      itemCount: count + 1, separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(['지금, 모두의 관심사', '대화가 더 즐거워지는 발견', '이번 주말엔 어디로?'][_tab],
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(['오늘의 검색 흐름을 한눈에', '밈의 의미부터 사용 맥락까지', '혼잡도와 지도를 함께 확인해요'][_tab],
              style: TextStyle(color: colors.onSurfaceVariant)),
          ]));
        }
        final i = index - 1;
        if (_tab == 0) {
          final item = feed.keywords[i];
          return Card(elevation: 0.5, child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: CircleAvatar(backgroundColor: colors.primaryContainer,
              child: Text('${item.rank}', style: TextStyle(color: colors.onPrimaryContainer))),
            title: Text(item.keyword, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(item.source)),
            trailing: Chip(label: Text(item.searchVolume)),
            onTap: () => _open(item.searchUri),
          ));
        }
        if (_tab == 1) {
          final item = feed.memes[i];
          return Card(elevation: 0.5, clipBehavior: Clip.antiAlias,
            child: ExpansionTile(title: Text(item.title,
              style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(item.source),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [Text(item.description), const SizedBox(height: 12),
                Wrap(spacing: 6, children: item.tags.map((tag) => Chip(label: Text('#$tag'))).toList()),
                if (item.sourceUrl != null) TextButton.icon(
                  onPressed: () => _open(item.sourceUrl!), icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('출처 읽기')),
              ]));
        }
        final item = feed.places[i];
        return Card(elevation: 0.5, child: Padding(padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4), Text(item.district), const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              Chip(avatar: const Icon(Icons.groups_outlined, size: 18), label: Text(item.crowdLevel)),
              Chip(label: Text('20대 ${item.age20sRatio}')),
            ]),
            Text('출처: ${item.source}', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: item.mapQuery.isEmpty ? null : () => _map(item, 'naver'),
                child: const Text('네이버지도')),
              OutlinedButton(onPressed: item.mapQuery.isEmpty ? null : () => _map(item, 'kakao'),
                child: const Text('카카오맵')),
            ]),
          ])));
      },
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Shimmer.fromColors(baseColor: colors.surfaceContainerHighest,
      highlightColor: colors.surface,
      child: ListView.builder(physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20), itemCount: 6,
        itemBuilder: (_, _) => Container(height: 100,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: colors.surface,
            borderRadius: BorderRadius.circular(20)))));
  }
}
