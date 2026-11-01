import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/briefing.dart';
import '../data/trends.dart';
import '../state/trends_provider.dart';

const trendsExplanation =
    '한국판 한국어 뉴스의 최근 72시간 보도를 같은 주제로 묶습니다. 같은 매체·추정 전재·유사 제목은 한 그룹으로 계산합니다. 주요 화제는 관측된 출처 그룹 수와 보도 지속성 순으로 최대 30개를 보여줍니다.\n\n보도 증가는 6시간마다 저장한 이력이 연속 48시간 이상이고, 이전 24시간 출처 2그룹 이상·최근 24시간 3그룹 이상·50% 이상 증가했을 때 표시합니다. 8시간 넘는 수집 공백이나 분야 누락·표본 상한에 도달하면 비교를 다시 기다립니다. 과거 출처가 0인 주제는 새로 포착으로 구분합니다.\n\n구간별 수치는 관측한 기사 표본의 보도 출처 수입니다. 한국 전체의 검색량·조회수·SNS 인기 순위가 아니며, 자동 기사 묶음과 제한된 수집 표본에는 누락과 오류가 있을 수 있습니다.';

class TrendsView extends ConsumerStatefulWidget {
  const TrendsView({super.key, required this.cardBuilder});
  final Widget Function(TrendItem item, Widget metrics) cardBuilder;
  @override
  ConsumerState<TrendsView> createState() => _TrendsViewState();
}

class _TrendsViewState extends ConsumerState<TrendsView> {
  String _category = '전체';
  bool _growth = false;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trendsProvider);
    final result = state.valueOrNull;
    final feed = result?.feed;
    final categoryItems =
        feed?.items
            .where((i) => _category == '전체' || i.topic.category == _category)
            .toList() ??
        <TrendItem>[];
    final items = _growth
        ? categoryItems.where((i) => i.isGrowing).toList()
        : categoryItems;
    if (_growth) {
      items.sort((a, b) => b.growthPercent!.compareTo(a.growthPercent!));
    }
    final stale =
        feed != null &&
        DateTime.now().toUtc().difference(feed.updatedAt) >
            const Duration(hours: 8);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: () => ref.read(trendsProvider.notifier).refresh(),
          child: ListView(
            key: PageStorageKey('trends-list-$_category-$_growth'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                '최근 3일 한국의 화제',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '한국어 뉴스 보도에서 포착한 화제예요. 여러 출처의 보도 범위와 시간에 따른 변화를 살펴보세요.',
              ),
              const SizedBox(height: 12),
              if (feed != null) ...[
                Text(
                  '${koreaDate(feed.updatedAt)} KST 집계 · ${feed.items.length}개 화제',
                ),
                Text(
                  '기록 시작 ${koreaDate(feed.startedAt)} KST · 관측 ${feed.snapshots}회',
                ),
                if (result!.cached || stale)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('이전 집계입니다. 수집 시각을 확인해 주세요.'),
                  ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    key: const ValueKey('trends-coverage'),
                    label: const Text('주요 화제'),
                    selected: !_growth,
                    onSelected: (_) => setState(() => _growth = false),
                  ),
                  ChoiceChip(
                    key: const ValueKey('trends-growth'),
                    label: const Text('보도 증가'),
                    selected: _growth,
                    onSelected: (_) => setState(() => _growth = true),
                  ),
                ],
              ),
              const Text('증가 비교는 연속 48시간의 수집 이력이 필요해요. 조회수·검색량 순위는 아닙니다.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: ['전체', ...topicCategories]
                    .map(
                      (category) => FilterChip(
                        key: ValueKey('trends-filter-$category'),
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              if (state.isLoading) const LinearProgressIndicator(),
              if (state.hasError && feed == null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('화제를 불러오지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.'),
                ),
                OutlinedButton(
                  onPressed: () => ref.read(trendsProvider.notifier).refresh(),
                  child: const Text('다시 시도'),
                ),
              ] else if (!state.isLoading && items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _growth && categoryItems.any((i) => !i.ready)
                        ? '보도 증가를 비교할 이력을 쌓고 있어요. 주요 화제는 지금 확인할 수 있습니다.'
                        : _growth
                        ? '증가 기준을 충족한 화제가 아직 없어요.'
                        : '여러 출처에서 다룬 화제를 수집 중이에요.',
                  ),
                ),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: widget.cardBuilder(item, TrendMetrics(item: item)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TrendMetrics extends StatelessWidget {
  const TrendMetrics({super.key, required this.item});
  final TrendItem item;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maximum = item.dailySources.fold<int>(1, (a, b) => a > b ? a : b);
    const labels = ['48~72시간 전', '24~48시간 전', '최근 24시간'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '전체 ${item.rank}위 · 관측 출처 ${item.sourceGroups}그룹',
          style: TextStyle(fontWeight: FontWeight.w800, color: colors.primary),
        ),
        const SizedBox(height: 8),
        Text(item.label, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (!item.ready)
          Text('연속 관측 ${item.trackingHours.floor()}시간 / 비교에 필요한 48시간'),
        const SizedBox(height: 12),
        const Text('24시간 구간별 보도 출처 수'),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      Text('${item.dailySources[i]}곳'),
                      SizedBox(
                        height: 48,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Semantics(
                            label:
                                '${labels[i]} 보도 출처 ${item.dailySources[i]}곳',
                            child: Container(
                              height: 2 + 46 * item.dailySources[i] / maximum,
                              decoration: BoxDecoration(
                                color: i == 2
                                    ? colors.primary
                                    : colors.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '아래 원문 근거는 최대 ${item.topic.coverage!.groups}곳입니다.',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const Divider(height: 28),
      ],
    );
  }
}
