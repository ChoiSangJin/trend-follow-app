import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/briefing.dart';
import '../data/briefing_repository.dart';
import '../state/briefing_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _view = 0;
  String _category = '전체';
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(briefingProvider);
    final result = state.valueOrNull;
    final saved = ref.watch(savedProvider);
    final all = _view == 1 ? saved : result?.briefing.topics ?? <Topic>[];
    final topics = all
        .where((t) => _category == '전체' || t.category == _category)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '말문',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -1),
        ),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: state.isLoading
                ? null
                : () => ref.read(briefingProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: RefreshIndicator(
            onRefresh: () => ref.read(briefingProvider.notifier).refresh(),
            child: ListView(
              key: PageStorageKey<String>('malmun-list-$_view-$_category'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _hero(context, result),
                const SizedBox(height: 20),
                if (result != null && _view == 0) _status(context, result),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: ['전체', '문화', '음식', '생활', '기술', '스포츠']
                      .map(
                        (category) => FilterChip(
                          key: ValueKey<String>('filter-$category'),
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                if (state.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (state.hasError && result == null && _view == 0)
                  _empty(context, '브리핑을 열지 못했어요', '잠시 후 새로고침해 주세요.'),
                if (!state.isLoading && topics.isEmpty && !state.hasError)
                  _empty(
                    context,
                    _view == 1 ? '대화 소재를 보관해 보세요' : '이 주제의 소식은 준비 중이에요',
                    _view == 1
                        ? '카드의 보관 버튼을 누르면 여기에 모입니다.'
                        : '다른 주제를 선택하거나 새로고침해 주세요.',
                  ),
                for (final topic in topics)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TopicCard(
                      topic: topic,
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TopicScreen(topic: topic),
                        ),
                      ),
                    ),
                  ),
                if (topics.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '가볍게 물어보고, 상대의 취향을 들어보세요.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _view,
        onDestinationSelected: (view) => setState(() {
          _view = view;
          _category = '전체';
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny),
            label: '오늘의 말문',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks),
            label: '보관함',
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context, FeedResult? result) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _view == 1 ? '나중에 꺼내 쓸 이야기' : '오늘, 무슨 얘기 할까?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.onPrimaryContainer,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _view == 1 ? '마음에 든 소재와 질문을 모아두세요.' : '소식 하나, 질문 하나. 대화의 시작을 가볍게.',
            style: TextStyle(color: colors.onPrimaryContainer),
          ),
          if (_view == 0 && result != null && !result.briefing.practice) ...[
            const SizedBox(height: 16),
            Text(
              '${result.briefing.topics.length}개 이야기 · ${koreaDate(result.briefing.updatedAt!)} KST 수집',
              style: TextStyle(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _status(BuildContext context, FeedResult result) {
    final old =
        result.briefing.updatedAt != null &&
        DateTime.now().toUtc().difference(result.briefing.updatedAt!) >
            const Duration(hours: 48);
    final message = switch (result.mode) {
      FeedMode.practice => '대화 연습 모드 · 최신 소식을 불러오지 못해 기본 질문을 보여드려요.',
      FeedMode.cached => '오프라인 · 마지막으로 받은 브리핑입니다. 기사 날짜를 확인해 주세요.',
      FeedMode.live =>
        old
            ? '이전 브리핑입니다. 최신 소식으로 단정하지 말고 기사 날짜를 확인해 주세요.'
            : '최근 72시간 기사에서 선별 · 인기 순위 아님 · 제목 기반 정보',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.mode == FeedMode.live
                ? Icons.verified_outlined
                : Icons.offline_bolt_outlined,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, String title, String body) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Column(
      children: [
        const Icon(Icons.forum_outlined, size: 40),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center),
      ],
    ),
  );
}

class TopicCard extends ConsumerWidget {
  const TopicCard({super.key, required this.topic, required this.onOpen});
  final Topic topic;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  label: Text(topic.category),
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  topic.publishedAt == null
                      ? '대화 연습'
                      : '${koreaDate(topic.publishedAt!)} KST 기사',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              topic.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              topic.opener,
              style: TextStyle(color: colors.primary, height: 1.6),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: onOpen,
                  child: const Text('대화 준비'),
                ),
                SaveButton(topic: topic),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SaveButton extends ConsumerWidget {
  const SaveButton({super.key, required this.topic});
  final Topic topic;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedProvider).any((x) => x.id == topic.id);
    return TextButton.icon(
      onPressed: () async {
        try {
          await ref.read(savedProvider.notifier).toggle(topic);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('보관하지 못했어요. 다시 시도해 주세요.')),
            );
          }
        }
      },
      icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
      label: Text(saved ? '보관됨' : '보관하기'),
    );
  }
}

class TopicScreen extends StatelessWidget {
  const TopicScreen({super.key, required this.topic});
  final Topic topic;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(topic.category),
      actions: [SaveButton(topic: topic)],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          children: [
            Text(
              topic.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${topic.source}${topic.publishedAt == null ? '' : ' · ${koreaDate(topic.publishedAt!)} KST'}',
            ),
            const SizedBox(height: 24),
            _section(
              context,
              topic.isPractice ? '대화의 소재' : '무슨 소식이야?',
              topic.summary,
            ),
            if (!topic.isPractice)
              const Text('기사 제목 기반 정보입니다. 본문을 읽은 요약이 아니며 세부 내용은 원문에서 확인해 주세요.'),
            const SizedBox(height: 24),
            _section(context, '왜 지금 이야기해?', topic.whyNow),
            const SizedBox(height: 24),
            _section(context, '이렇게 말 걸어봐', topic.opener),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: topic.opener));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('질문을 복사했어요.')));
                  }
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('질문 복사'),
              ),
            ),
            const SizedBox(height: 24),
            _section(context, '대화 전에 알아두면', topic.context),
            if (topic.url != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _open(context),
                icon: const Icon(Icons.open_in_new),
                label: const Text('출처 기사 읽기'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  Widget _section(BuildContext context, String title, String body) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      Text(body, style: const TextStyle(height: 1.7)),
    ],
  );
  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(topic.url!, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      /* Explain failed intents in the UI. */
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('원문을 열지 못했어요. 인터넷 연결과 브라우저를 확인해 주세요.')),
      );
    }
  }
}
