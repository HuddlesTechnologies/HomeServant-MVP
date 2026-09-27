import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/support_tools.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import 'widgets/admin_filter_chip.dart';

/// The one data colour on this page (every chart here is a single series).
/// Validated with the dataviz palette checker against the white cards:
/// lightness band, chroma floor and >= 3:1 contrast all pass. Text never
/// wears it — values and labels stay navy/grey.
const _barColor = Color(0xFF2A78D6);

/// Super admins: how support is performing — how fast customers get a
/// human, how quickly things get resolved, what they're about, who's
/// handling them, when it's busiest, and how customers rate it. Figures
/// come from backend SupportMetricsService.
class AdminSupportInsightsTab extends StatefulWidget {
  const AdminSupportInsightsTab({super.key});

  @override
  State<AdminSupportInsightsTab> createState() => _AdminSupportInsightsTabState();
}

class _AdminSupportInsightsTabState extends State<AdminSupportInsightsTab> {
  static const _ranges = [7, 30, 90];
  int _days = 30;
  SupportMetrics? _metrics;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final metrics = await context.read<AppState>().supportTools.metrics(_days);
      if (mounted) setState(() => _metrics = metrics);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _metrics;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Filters: one row, above everything they affect.
          Row(
            children: [
              for (final days in _ranges) ...[
                AdminFilterChip(
                  label: 'Last $days days',
                  selected: _days == days,
                  onTap: () {
                    setState(() => _days = days);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: AppTextStyles.body(color: AppColors.navy, size: 14))
          else if (m == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
          else ...[
            const _SectionTitle('Right now'),
            _TileGrid(tiles: [
              _Tile('Waiting for an admin', '${m.waiting}', warn: m.waiting > 0),
              _Tile('Longest wait', _duration(m.oldestWaitMinutes)),
              _Tile('Admins on duty & online', '${m.adminsAvailable}', warn: m.adminsAvailable == 0),
              _Tile('Open chats being handled', '${m.openAssigned}'),
            ]),
            const SizedBox(height: 18),
            _SectionTitle('Last ${m.days} days'),
            _TileGrid(tiles: [
              _Tile('Conversations', '${m.totals.conversations}'),
              _Tile(
                'Resolved',
                m.totals.conversations == 0 ? '—' : '${(m.totals.resolved * 100 / m.totals.conversations).round()}%',
                caption: '${m.totals.resolved} of ${m.totals.conversations}',
              ),
              _Tile('Time to first reply', _duration(m.totals.medianFirstResponseMinutes),
                  caption: 'median · 9 in 10 within ${_duration(m.totals.p90FirstResponseMinutes)}'),
              _Tile('Time to resolve', _duration(m.totals.medianResolutionMinutes), caption: 'median'),
              _Tile(
                'Customer rating',
                m.totals.averageRating == null ? '—' : '${m.totals.averageRating!.toStringAsFixed(1)} / 5',
                caption: '${m.totals.ratings} ${m.totals.ratings == 1 ? 'rating' : 'ratings'}',
              ),
              _Tile('Transferred', '${m.totals.transferred}'),
              _Tile('Never answered', '${m.totals.neverAnswered}', warn: m.totals.neverAnswered > 0),
            ]),
            const SizedBox(height: 18),
            const _SectionTitle('Conversations per day'),
            _Card(
              child: _ColumnChart(
                values: [for (final d in m.byDay) d.conversations],
                labelFor: (i) => formatShortDate(m.byDay[i].date),
                tooltipFor: (i) =>
                    '${formatShortDate(m.byDay[i].date)}: ${m.byDay[i].conversations} new, ${m.byDay[i].resolved} resolved',
                axisLabels: m.byDay.isEmpty
                    ? const []
                    : [formatShortDate(m.byDay.first.date), formatShortDate(m.byDay.last.date)],
              ),
            ),
            const SizedBox(height: 18),
            const _SectionTitle('Busiest hours (Lagos time)'),
            _Card(
              child: _ColumnChart(
                values: m.byHour,
                labelFor: (i) => '${i.toString().padLeft(2, '0')}:00',
                tooltipFor: (i) =>
                    '${i.toString().padLeft(2, '0')}:00–${(i + 1).toString().padLeft(2, '0')}:00: ${m.byHour[i]} conversations',
                axisLabels: const ['00:00', '06:00', '12:00', '18:00', '23:00'],
              ),
            ),
            const SizedBox(height: 18),
            const _SectionTitle('By topic'),
            _Card(child: _TopicTable(rows: m.byTopic)),
            const SizedBox(height: 18),
            const _SectionTitle('By admin'),
            Text(
              'For planning cover and spotting who needs help — not a ranking.',
              style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5),
            ),
            const SizedBox(height: 8),
            _Card(child: _AdminTable(rows: m.byAdmin)),
            const SizedBox(height: 18),
            const _SectionTitle('Latest ratings'),
            _Card(
              child: m.recentRatings.isEmpty
                  ? Text('No ratings yet.', style: AppTextStyles.body(color: AppColors.hintGrey, size: 13.5))
                  : Column(
                      children: [
                        for (final r in m.recentRatings)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 44,
                                  child: Text('${r.rating}/5',
                                      style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w700)),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (r.comment != null && r.comment!.isNotEmpty)
                                        Text('"${r.comment}"', style: AppTextStyles.body(color: AppColors.navy, size: 13.5)),
                                      Text(
                                        [
                                          r.topic?.label ?? 'Support',
                                          if (r.adminName != null) 'resolved by ${r.adminName}',
                                          if (r.ratedAt != null) formatShortDate(r.ratedAt!.toLocal()),
                                        ].join(' · '),
                                        style: AppTextStyles.body(color: AppColors.hintGrey, size: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

String _duration(double? minutes) {
  if (minutes == null) return '—';
  if (minutes < 1) return '< 1 min';
  if (minutes < 60) return '${minutes.round()} min';
  final hours = minutes / 60;
  if (hours < 24) {
    final h = hours.floor();
    final rest = (minutes - h * 60).round();
    return rest == 0 ? '$h h' : '$h h $rest min';
  }
  return '${(hours / 24).toStringAsFixed(1)} days';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: AppTextStyles.heading(color: AppColors.navy, size: 16)),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    child: child,
  );
}

class _Tile {
  const _Tile(this.label, this.value, {this.caption, this.warn = false});
  final String label;
  final String value;
  final String? caption;

  /// Needs attention: shown with a warning icon + the value (never colour alone).
  final bool warn;
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : (constraints.maxWidth >= 560 ? 3 : 2);
        final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tile in tiles)
              Container(
                width: width,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tile.label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12, weight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (tile.warn) ...[
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB54708), size: 18),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(tile.value, style: AppTextStyles.heading(color: AppColors.navy, size: 22)),
                        ),
                      ],
                    ),
                    if (tile.caption != null) ...[
                      const SizedBox(height: 2),
                      Text(tile.caption!, style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5)),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A single-series column chart: thin columns (<= 24px) with a 4px rounded
/// top, square at the baseline, a 2px gap between neighbours, a recessive
/// baseline, a max-value reference label, and a hover/long-press tooltip
/// per column (hit area = the whole slot, not just the bar).
class _ColumnChart extends StatelessWidget {
  const _ColumnChart({required this.values, required this.labelFor, required this.tooltipFor, required this.axisLabels});

  final List<int> values;
  final String Function(int index) labelFor;
  final String Function(int index) tooltipFor;
  final List<String> axisLabels;

  static const _height = 120.0;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(0, (a, b) => b > a ? b : a);
    if (max == 0) {
      return SizedBox(
        height: 60,
        child: Center(child: Text('No conversations in this period.', style: AppTextStyles.body(color: AppColors.hintGrey, size: 13))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('max $max', style: AppTextStyles.body(color: AppColors.hintGrey, size: 11)),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / values.length;
            final barWidth = (slot - 2).clamp(1.0, 24.0).toDouble();
            return SizedBox(
              height: _height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Tooltip(
                      message: tooltipFor(i),
                      waitDuration: Duration.zero,
                      child: SizedBox(
                        width: slot,
                        height: _height,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: barWidth,
                            height: values[i] == 0 ? 0 : (values[i] / max * _height).clamp(2.0, _height).toDouble(),
                            decoration: const BoxDecoration(
                              color: _barColor,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        Container(height: 1, color: AppColors.navy.withValues(alpha: 0.15)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (final label in axisLabels) Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 11))],
        ),
      ],
    );
  }
}

TextStyle _th() => AppTextStyles.body(color: AppColors.hintGrey, size: 11.5, weight: FontWeight.w700);
TextStyle _td({bool strong = false}) =>
    AppTextStyles.body(color: AppColors.navy, size: 13, weight: strong ? FontWeight.w700 : FontWeight.w400);

class _TopicTable extends StatelessWidget {
  const _TopicTable({required this.rows});
  final List<({String label, SupportTotals totals})> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Text('No conversations in this period.', style: AppTextStyles.body(color: AppColors.hintGrey, size: 13));
    final max = rows.fold<int>(0, (a, r) => r.totals.conversations > a ? r.totals.conversations : a);
    return LayoutBuilder(
      builder: (context, outer) {
        // Narrow screens: the reply-time/rating text goes under the bar so
        // the bar keeps a readable length.
        final narrow = outer.maxWidth < 560;
        String meta(SupportTotals t) =>
            'first reply ${_duration(t.medianFirstResponseMinutes)}'
            '${t.averageRating != null ? ' · ${t.averageRating!.toStringAsFixed(1)}/5' : ''}';
        final metaStyle = AppTextStyles.body(color: AppColors.hintGrey, size: 12);
        return Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: narrow ? 96 : 110, child: Text(row.label, style: _td(strong: true))),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Horizontal bar (magnitude), count direct-labelled beside it.
                          LayoutBuilder(
                            builder: (context, c) => Row(
                              children: [
                                Container(
                                  width: (row.totals.conversations / max * (c.maxWidth - 40)).clamp(2.0, c.maxWidth).toDouble(),
                                  height: 14,
                                  decoration: const BoxDecoration(
                                    color: _barColor,
                                    borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text('${row.totals.conversations}', style: _td(strong: true)),
                              ],
                            ),
                          ),
                          if (narrow) ...[
                            const SizedBox(height: 2),
                            Text(meta(row.totals), style: metaStyle),
                          ],
                        ],
                      ),
                    ),
                    if (!narrow)
                      SizedBox(width: 150, child: Text(meta(row.totals), textAlign: TextAlign.right, style: metaStyle)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AdminTable extends StatelessWidget {
  const _AdminTable({required this.rows});
  final List<SupportAdminStat> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Text('No admins yet.', style: AppTextStyles.body(color: AppColors.hintGrey, size: 13));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 52,
        columnSpacing: 22,
        horizontalMargin: 0,
        headingTextStyle: _th(),
        columns: const [
          DataColumn(label: Text('Admin')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Open now'), numeric: true),
          DataColumn(label: Text('First replies'), numeric: true),
          DataColumn(label: Text('Resolved'), numeric: true),
          DataColumn(label: Text('First reply (median)')),
          DataColumn(label: Text('Rating')),
        ],
        rows: [
          for (final a in rows)
            DataRow(cells: [
              DataCell(Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name, style: _td(strong: true)),
                  Text(a.level.label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 11)),
                ],
              )),
              DataCell(Text(!a.onDuty ? 'Away' : (a.online ? 'On duty · online' : 'On duty · offline'), style: _td())),
              DataCell(Text('${a.openNow}', style: _td())),
              DataCell(Text('${a.firstReplies}', style: _td())),
              DataCell(Text('${a.resolved}', style: _td())),
              DataCell(Text(_duration(a.medianFirstResponseMinutes), style: _td())),
              DataCell(Text(a.averageRating == null ? '—' : '${a.averageRating!.toStringAsFixed(1)} (${a.ratings})', style: _td())),
            ]),
        ],
      ),
    );
  }
}
