import 'package:flutter/material.dart';

import '../../core/engine/speech_order.dart';
import '../../core/engine/speech_timer.dart';
import '../../core/models/game_state.dart';
import '../../shared/theme.dart';
import 'badge_succession_page.dart';
import 'exile_vote_page.dart';
import 'speech_timer_page.dart';

/// 決定白天的發言順序。
///
/// 規則（擔當指定）：
///
/// | 情況 | 起點 | 方向 |
/// |---|---|---|
/// | 單死 | 死者 | 警長選 |
/// | 平安夜、雙死以上 | 警長 | 警長選 |
/// | 沒有警長 | 隨機 | 隨機 |
///
/// **方向用順時鐘／逆時鐘表示，不用「左／右」** —— 桌上說的「警左／警右」
/// 對應哪個方向各家習慣不同，所以畫面直接把號碼順序列出來，
/// 法官照警長講的挑就好。
class SpeechOrderPage extends StatefulWidget {
  const SpeechOrderPage({
    super.key,
    required this.state,
    required this.deceased,
    required this.onFinished,
  });

  final GameState state;

  /// 昨晚公布的死者，**加上天亮後被槍帶走的人**（擔當 2026-09-24 指定）。
  final List<int> deceased;

  /// 順序定好之後要做什麼。參數是確定下來的發言順序（座次，依序）。
  ///
  /// 接著是逐人計時發言，所以順序必須傳出去 —— 計時頁要照這個名單走。
  final ValueChanged<List<int>> onFinished;

  /// 定完順序後開啟放逐投票，投完再進下一夜。
  static Route<void> routeThenExile(
    GameState state,
    List<int> deceased, {
    required Route<void> Function() nextNight,
  }) =>
      MaterialPageRoute<void>(
        builder: (context) => SpeechOrderPage(
          state: state,
          deceased: deceased,
          onFinished: (order) => Navigator.of(context).pushReplacement(
            // 順序決定完就逐人計時發言，講完才進投票。
            SpeechTimerPage.route(
              state,
              order: order,
              phase: SpeechPhase.day,
              next: () => ExileVotePage.route(
                state,
                // 放逐、開槍、殉情都可能把警長帶走 —— 進下一夜之前先走警徽流。
                next: () => BadgeSuccessionPage.routeIfDue(
                  state,
                  next: nextNight,
                ),
              ),
              // 騎士決鬥出狼 → 跳過剩下的發言與投票直接進黑夜。
              // 走的是和狼人自爆相同的路徑，但警徽流照樣要走
              // —— 被決鬥掉的可能就是警長。
              dayEndsEarly: () => BadgeSuccessionPage.routeIfDue(
                state,
                next: nextNight,
              ),
            ),
          ),
        ),
      );

  @override
  State<SpeechOrderPage> createState() => _SpeechOrderPageState();
}

class _SpeechOrderPageState extends State<SpeechOrderPage> {
  late final SpeechOrderBasis _basis;

  /// 沒有警長時抽出來的那一份；抽完就固定，不會每次 build 重抽。
  SpeechOrderPlan? _randomPlan;

  /// 已經確定的順序。null 表示還沒選方向。
  SpeechOrderPlan? _chosen;

  @override
  void initState() {
    super.initState();
    _basis = SpeechOrder.basisFor(widget.state, widget.deceased);
    if (_basis == SpeechOrderBasis.random) {
      _randomPlan = SpeechOrder.randomPlan(widget.state);
      _chosen = _randomPlan;
    }
  }

  /// 起點的參考座次：死者或警長。隨機模式下由抽籤決定。
  int get _referenceSeat => switch (_basis) {
        SpeechOrderBasis.deceased => widget.deceased.single,
        SpeechOrderBasis.sheriff => widget.state.sheriffSeat!,
        SpeechOrderBasis.random => _randomPlan!.referenceSeat,
      };

  String get _title => switch (_basis) {
        SpeechOrderBasis.deceased => '單死 · 由警長決定方向',
        SpeechOrderBasis.sheriff => '由警長決定方向',
        SpeechOrderBasis.random => '無警長 · 上帝抽籤',
      };

  String get _hint => switch (_basis) {
        SpeechOrderBasis.deceased =>
          '昨晚只死 $_referenceSeat 號，從他開始算。問警長要哪一邊，'
              '再對照下面的號碼順序挑',
        SpeechOrderBasis.sheriff => widget.deceased.isEmpty
            ? '昨晚是平安夜，從警長 $_referenceSeat 號開始算'
            : '昨晚到現在死了 ${widget.deceased.length} 位，'
                '從警長 $_referenceSeat 號開始算',
        SpeechOrderBasis.random =>
          '本局沒有警長，起點與方向都由上帝抽。抽到 $_referenceSeat 號，'
              '${_randomPlan!.clockwise ? "順時鐘" : "逆時鐘"}',
      };

  void _choose(bool clockwise) {
    setState(() {
      _chosen = SpeechOrder.plan(
        widget.state,
        basis: _basis,
        referenceSeat: _referenceSeat,
        clockwise: clockwise,
      );
    });
  }

  void _reroll() {
    setState(() {
      _randomPlan = SpeechOrder.randomPlan(widget.state);
      _chosen = _randomPlan;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRandom = _basis == SpeechOrderBasis.random;

    return Scaffold(
      appBar: AppBar(title: Text('第 ${widget.state.dayNumber} 天　發言順序')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _hint,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 兩個方向各自把實際順序列出來，法官一眼對照。
                  if (!isRandom) ...[
                    _directionCard(scheme, clockwise: true),
                    const SizedBox(height: 10),
                    _directionCard(scheme, clockwise: false),
                  ] else
                    _orderCard(
                      scheme,
                      plan: _randomPlan!,
                      selected: true,
                      label: _randomPlan!.clockwise ? '順時鐘' : '逆時鐘',
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isRandom)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: _reroll,
                        icon: const Icon(Icons.casino_rounded, size: 18),
                        label: const Text('重抽'),
                      ),
                    ),
                  FilledButton(
                    onPressed: _chosen == null
                        ? null
                        : () => widget.onFinished(_chosen!.order),
                    child: Text(
                      _chosen == null ? '請先選一個方向' : '順序確定，開始發言',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _directionCard(ColorScheme scheme, {required bool clockwise}) {
    final plan = SpeechOrder.plan(
      widget.state,
      basis: _basis,
      referenceSeat: _referenceSeat,
      clockwise: clockwise,
    );
    final selected = _chosen?.clockwise == clockwise;

    return InkWell(
      onTap: () => _choose(clockwise),
      borderRadius: BorderRadius.circular(12),
      child: _orderCard(
        scheme,
        plan: plan,
        selected: selected,
        label: clockwise ? '順時鐘（號碼遞增）' : '逆時鐘（號碼遞減）',
      ),
    );
  }

  Widget _orderCard(
    ColorScheme scheme, {
    required SpeechOrderPlan plan,
    required bool selected,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
        border: Border.all(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.8),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            plan.order.join(' → '),
            style: const TextStyle(fontSize: 16, height: 1.6),
          ),
          if (plan.referenceSpeaks) ...[
            const SizedBox(height: 6),
            Text(
              '警長（${plan.referenceSeat} 號）最後發言',
              style: TextStyle(fontSize: 12, color: WgmTheme.godColor),
            ),
          ],
        ],
      ),
    );
  }
}
