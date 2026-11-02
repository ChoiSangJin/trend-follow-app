import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/briefing.dart';
import '../data/briefing_repository.dart';
import '../data/conversation.dart';
import '../state/briefing_provider.dart';
import '../state/conversation_provider.dart';

const conversationExplanation =
    '오늘의 브리핑은 여러 출처가 있는 최근 기사 중 준비된 배경 설명과 대화 질문이 맞는 주제를 최대 3개 고릅니다. 서로 다른 분야와 아직 이해 표시를 하지 않은 주제를 우선합니다.\n\n기사 제목에서 확인한 내용은 언론사·발행 시각·원문 링크와 함께 보여줍니다. 배경·대화 문장은 앱이 편집한 설명입니다. 기사 본문을 읽은 요약이나 새로 취재한 사실로 제시하지 않습니다.\n\n대화 상대 선택과 이해 표시·피드백·메모는 이 기기에만 저장됩니다. 적합한 기사가 부족하면 3개를 억지로 채우지 않습니다.';

Future<void> _openSource(BuildContext context, Uri url) async {
  try {
    if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    /* Explain unavailable browsers. */
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('출처를 열지 못했어요. 인터넷 연결과 브라우저를 확인해 주세요.')),
    );
  }
}

Future<void> _record(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기록을 저장하지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }
}

class CoachView extends ConsumerStatefulWidget {
  const CoachView({
    super.key,
    required this.onBrowse,
    required this.onOpen,
    required this.onHistory,
  });
  final VoidCallback onBrowse, onHistory;
  final void Function(ConversationBrief) onOpen;
  @override
  ConsumerState<CoachView> createState() => _CoachViewState();
}

class _CoachViewState extends ConsumerState<CoachView> {
  List<String>? _pinned;
  String? _day, _audience;
  @override
  Widget build(BuildContext context) {
    final news = ref.watch(briefingProvider);
    final catalog = ref.watch(guideCatalogProvider);
    final pool = ref.watch(conversationPoolProvider);
    final learning = ref.watch(learningProvider);
    final now = ref.watch(conversationClockProvider)();
    final day = koreaDay(now);
    final feed = news.valueOrNull;
    final eligible = eligibleBriefings(
      pool.topics,
      catalog.valueOrNull ?? const GuideCatalog([]),
      now,
    );
    if (_day != day || _audience != learning.audience) {
      _pinned = null;
      _day = day;
      _audience = learning.audience;
    }
    if (_pinned == null && eligible.isNotEmpty && !pool.loading) {
      _pinned = chooseBriefings(
        eligible,
        learning.audience,
        learning.understoodIds,
        understoodGuides: learning.understoodGuideIds,
      ).map((b) => b.topic.id).toList();
    }
    final selected = <ConversationBrief>[];
    for (final id in _pinned ?? <String>[]) {
      for (final b in eligible) {
        if (b.topic.id == id) selected.add(b);
      }
    }
    if (selected.length < 3 && !pool.loading) {
      for (final b in chooseBriefings(
        eligible,
        learning.audience,
        learning.understoodIds,
        understoodGuides: learning.understoodGuideIds,
      )) {
        if (!selected.any(
          (item) =>
              item.topic.id == b.topic.id ||
              item.topic.category == b.topic.category,
        )) {
          selected.add(b);
        }
        if (selected.length == 3) break;
      }
      if (selected.isNotEmpty) {
        _pinned = selected.map((b) => b.topic.id).toList();
      }
    }
    final completed = selected
        .where((b) => learning.record(b.topic.id)?.understood == true)
        .length;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: () => refreshConversation(ref),
          child: ListView(
            key: const PageStorageKey('coach-today'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                '오늘 무슨 얘기 하지?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              const Text('관심 가는 소식부터 골라 보세요. 첫마디도 같이 준비했어요.'),
              const SizedBox(height: 16),
              if (selected.isNotEmpty)
                Text(
                  '오늘 확인한 $completed / ${selected.length}개',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onHistory,
                icon: const Icon(Icons.history_edu),
                label: const Text('내가 남긴 이야기'),
              ),
              const SizedBox(height: 8),
              const Text('누구와 이야기하나요?'),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: audiences.entries
                    .map(
                      (e) => ChoiceChip(
                        key: ValueKey('audience-${e.key}'),
                        label: Text(e.value),
                        selected: learning.audience == e.key,
                        onSelected: (_) => _record(
                          context,
                          () => ref
                              .read(learningProvider.notifier)
                              .setAudience(e.key),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              if (feed != null && (feed.cachedNews || feed.briefing.practice))
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    '최근 소식을 받지 못했어요. 기사 날짜를 확인하고 이전 브리핑은 복습으로 활용해 주세요.',
                  ),
                ),
              if (pool.cached && !(feed?.cachedNews ?? false))
                const Text('일부 화제는 이전 집계입니다. 기사 날짜를 확인해 주세요.'),
              if (pool.loading || catalog.isLoading)
                const LinearProgressIndicator(),
              if (catalog.hasError)
                const Text('배경 설명을 준비하지 못했어요. 앱을 다시 열어 주세요.'),
              if (!pool.loading && !catalog.isLoading && selected.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    '서로 다른 출처의 기사와 배경 설명을 연결하고 있어요. 준비된 브리핑이 생기면 여기에 표시합니다. 이전 기록은 복습할 수 있어요.',
                  ),
                ),
              for (var i = 0; i < selected.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _BriefCard(
                    brief: selected[i],
                    number: i + 1,
                    audience: learning.audience,
                    understood:
                        learning.record(selected[i].topic.id)?.understood ==
                        true,
                    review: learning.understoodGuideIds.contains(
                      selected[i].guide.id,
                    ),
                    onOpen: () => widget.onOpen(selected[i]),
                  ),
                ),
              if (eligible.any(
                (b) => !selected.any((s) => s.guide.id == b.guide.id),
              ))
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _pinned = chooseBriefings(
                      eligible,
                      learning.audience,
                      {
                        ...learning.understoodIds,
                        ...selected.map((b) => b.topic.id),
                      },
                      understoodGuides: {
                        ...learning.understoodGuideIds,
                        ...selected.map((b) => b.guide.id),
                      },
                    ).map((b) => b.topic.id).toList();
                  }),
                  icon: const Icon(Icons.shuffle),
                  label: const Text('다른 주제로 바꾸기'),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: widget.onBrowse,
                child: const Text('분야별 소식 둘러보기'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  '기사에서 확인한 내용과 편집한 배경 설명을 구분해서 읽어 주세요.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on FeedResult {
  bool get cachedNews => mode != FeedMode.live;
}

class _BriefCard extends StatelessWidget {
  const _BriefCard({
    required this.brief,
    required this.number,
    required this.audience,
    required this.understood,
    required this.onOpen,
    this.review = false,
  });
  final ConversationBrief brief;
  final int number;
  final String audience;
  final bool understood;
  final bool review;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number · ${brief.topic.category}${understood
                ? ' · 이해 표시 완료'
                : review
                ? ' · 전에 본 주제'
                : ''}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            brief.topic.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(brief.opening(audience), style: const TextStyle(height: 1.6)),
          const SizedBox(height: 12),
          Text(
            '${brief.topic.source} · ${koreaDate(brief.topic.publishedAt!)} KST',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: ValueKey('coach-open-${brief.topic.id}'),
            onPressed: onOpen,
            child: Text(understood ? '다시 꺼내 보기' : '대화 준비하기'),
          ),
        ],
      ),
    ),
  );
}

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.brief, this.header});
  final ConversationBrief brief;
  final Widget? header;
  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  late final TextEditingController _note;
  @override
  void initState() {
    super.initState();
    _note = TextEditingController(
      text:
          ref.read(learningProvider).record(widget.brief.topic.id)?.note ?? '',
    );
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brief = widget.brief, guide = brief.guide, topic = brief.topic;
    final learning = ref.watch(learningProvider);
    final record = learning.record(topic.id);
    final audience = learning.audience;
    final saved = ref.watch(savedProvider).any((t) => t.id == topic.id);
    final older =
        topic.publishedAt != null &&
        ref
                .watch(conversationClockProvider)()
                .toUtc()
                .difference(topic.publishedAt!) >
            const Duration(hours: 72);
    final other =
        topic.coverage?.sources
            .where((s) => s.headline != null && s.url != topic.url)
            .take(1)
            .toList() ??
        <CoverageSource>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(topic.category),
        actions: [
          IconButton(
            tooltip: saved ? '보관 해제' : '보관하기',
            onPressed: () => _record(
              context,
              () => ref.read(savedProvider.notifier).toggle(topic),
            ),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            key: PageStorageKey('conversation-${topic.id}'),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            children: [
              Text(
                topic.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                brief.opening(audience),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                  height: 1.6,
                ),
              ),
              if (older)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('이전 기사로 복습하는 기록입니다. 현재 상황으로 단정하지 마세요.'),
                ),
              const SizedBox(height: 24),
              ?widget.header,
              _section(
                context,
                '어떤 소식인가요?',
                const Text('언론사 기사 제목에서 확인한 표현입니다. 세부 내용은 각 원문을 확인해 주세요.'),
              ),
              const SizedBox(height: 8),
              Text(topic.coverage?.label ?? '이전 보관 자료 · 추가 출처 기록 없음'),
              const SizedBox(height: 8),
              Text('“${topic.title}”'),
              TextButton.icon(
                onPressed: () => _openSource(context, topic.url!),
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  '${topic.source} · ${koreaDate(topic.publishedAt!)} KST 원문',
                ),
              ),
              for (final source in other) ...[
                Text('“${source.headline}”'),
                TextButton.icon(
                  onPressed: () => _openSource(context, source.url),
                  icon: const Icon(Icons.link),
                  label: Text(
                    '${source.name} · ${koreaDate(source.publishedAt)} KST 원문',
                  ),
                ),
              ],
              if (topic.coverage != null &&
                  topic.coverage!.sources.length > other.length + 1)
                TextButton.icon(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (sheetContext) => SafeArea(
                      child: SizedBox(
                        height: MediaQuery.sizeOf(sheetContext).height * .6,
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            Text(
                              '원문 근거 모두 보기',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            for (final source in topic.coverage!.sources)
                              ListTile(
                                title: Text(source.headline ?? source.name),
                                subtitle: Text(
                                  '${source.name} · ${koreaDate(source.publishedAt)} KST',
                                ),
                                trailing: const Icon(Icons.open_in_new),
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  _openSource(context, source.url);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.source_outlined),
                  label: Text('원문 근거 ${topic.coverage!.groups}곳 모두 보기'),
                ),
              const SizedBox(height: 20),
              _section(
                context,
                '짧게 알아두면',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '배경 참고 · 앱 편집',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    for (final paragraph in guide.background)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          paragraph,
                          style: const TextStyle(height: 1.7),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => _openSource(
                        context,
                        safeLink(guide.json['reference']['url'])!,
                      ),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text(guide.json['reference']['label']),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _section(
                context,
                '이렇게 꺼내 보세요',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: audiences.entries
                          .map(
                            (e) => ChoiceChip(
                              label: Text(e.value),
                              selected: audience == e.key,
                              onSelected: (_) => _record(
                                context,
                                () => ref
                                    .read(learningProvider.notifier)
                                    .setAudience(e.key),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '첫마디',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      brief.opening(audience),
                      style: const TextStyle(height: 1.7),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: brief.opening(audience)),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('첫마디를 복사했어요.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('첫마디 복사'),
                    ),
                    const Text(
                      '반응에 따라 이어가기',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    for (final question in brief.followups(audience))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          question,
                          style: const TextStyle(height: 1.6),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      '조심할 점 · ${guide.caution}',
                      style: const TextStyle(height: 1.6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _section(
                context,
                '내 말로 한 문장',
                Column(
                  children: [
                    TextField(
                      controller: _note,
                      key: const ValueKey('conversation-note'),
                      maxLength: 240,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '실제로 꺼내고 싶은 말이나 대화 후기를 적어 보세요.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _record(context, () async {
                          await ref
                              .read(learningProvider.notifier)
                              .update(brief, note: _note.text);
                          if (context.mounted) FocusScope.of(context).unfocus();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('이 기기에 메모를 저장했어요.')),
                            );
                          }
                        }),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('내 문장 저장'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _record(
                  context,
                  () => ref
                      .read(learningProvider.notifier)
                      .update(brief, understood: true),
                ),
                icon: Icon(
                  record?.understood == true
                      ? Icons.check_circle
                      : Icons.check_circle_outline,
                ),
                label: Text(
                  record?.understood == true ? '이해했다고 표시했어요' : '이해했어요',
                ),
              ),
              const SizedBox(height: 12),
              const Text('이 이야기는 어땠나요?'),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final entry in {
                    'learned': '새로 알았어요',
                    'known': '이미 알아요',
                    'used': '대화에 써봤어요',
                  }.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: entry.key == 'used'
                          ? record?.used == true
                          : record?.feedback == entry.key,
                      onSelected: (_) => _record(
                        context,
                        () => ref
                            .read(learningProvider.notifier)
                            .update(brief, feedback: entry.key),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '이해 표시·피드백·메모는 이 기기에만 저장됩니다.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      child,
    ],
  );
}

class LearningHistoryScreen extends ConsumerWidget {
  const LearningHistoryScreen({super.key, required this.onOpen});
  final void Function(Topic) onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(learningProvider).records;
    return Scaffold(
      appBar: AppBar(title: const Text('내가 남긴 이야기')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '이해 표시 ${records.where((r) => r.understood).length}개 · 대화에 써본 ${records.where((r) => r.used).length}개',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text('기사 날짜와 내가 남긴 문장을 보며 다시 꺼내 보세요.'),
              if (records.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text('이해 표시나 메모를 남기면 여기에 모입니다.'),
                ),
              for (final record in records)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Card(
                    child: ListTile(
                      title: Text(record.topic.title),
                      subtitle: Text(
                        '${record.used ? '대화에 써봤어요 · ' : ''}${koreaDate(record.updatedAt)} KST 기록${record.note.isEmpty ? '' : '\n${record.note}'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => onOpen(record.topic),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
