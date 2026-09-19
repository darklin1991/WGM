import 'package:flutter/material.dart';

import '../../core/engine/knight_duel.dart';
import '../../core/engine/speech_timer.dart';
import '../../core/models/game_state.dart';
import '../../shared/theme.dart';
import '../review/review_log_button.dart';
import 'knight_duel_page.dart';
import 'speech_timer_view.dart';

/// 獨立的發言計時頁：白天發言與遺言用這個。
///
/// 警上發言與平票 PK 發言不走這裡 —— 那兩個是嵌在競選頁與放逐頁的一個階段，
/// 直接用 [SpeechTimerView]。
class SpeechTimerPage extends StatefulWidget {
  const SpeechTimerPage({
    super.key,
    required this.state,
    required this.order,
    required this.phase,
    required this.onFinished,
    this.finishLabel,
    this.onDayEndsEarly,
  });

  final GameState state;

  /// 發言順序。白天發言是 `SpeechOrderPlan.order`，遺言通常只有一兩位。
  final List<int> order;

  final SpeechPhase phase;

  final VoidCallback onFinished;

  final String? finishLabel;

  /// 騎士決鬥出狼時要做什麼（跳過投票直接進黑夜）。
  ///
  /// 給了才會出現決鬥入口 —— 也就是只有白天發言那一輪有，遺言那一輪沒有。
  /// 決鬥視窗到投票開始就關閉了，所以入口只長在這一頁上。
  final VoidCallback? onDayEndsEarly;

  static Route<void> route(
    GameState state, {
    required List<int> order,
    required SpeechPhase phase,
    required Route<void> Function() next,
    String? finishLabel,
    Route<void> Function()? dayEndsEarly,
  }) =>
      MaterialPageRoute<void>(
        builder: (context) => SpeechTimerPage(
          state: state,
          order: order,
          phase: phase,
          finishLabel: finishLabel,
          onFinished: () => Navigator.of(context).pushReplacement(next()),
          onDayEndsEarly: dayEndsEarly == null
              ? null
              : () => Navigator.of(context).pushReplacement(dayEndsEarly()),
        ),
      );

  @override
  State<SpeechTimerPage> createState() => _SpeechTimerPageState();
}

class _SpeechTimerPageState extends State<SpeechTimerPage> {
  late final SpeechTimer _timer;

  @override
  void initState() {
    super.initState();
    _timer = SpeechTimer(
      order: widget.order,
      seconds: widget.state.preset.rules.speechSeconds,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${widget.state.dayNumber} 天　${widget.phase.labelZh}'),
        automaticallyImplyLeading: false,
        actions: [ReviewLogButton(state: widget.state)],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SpeechTimerView(
                timer: _timer,
                phase: widget.phase,
                finishLabel: widget.finishLabel,
                onFinished: widget.onFinished,
              ),
              if (_duelAvailable) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                _duelButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 決鬥視窗：整個白天發言階段都開著，投票一開始就關閉。
  ///
  /// 沒有騎士、騎士已出局、技能用過了，這顆就不會出現。
  bool get _duelAvailable =>
      widget.onDayEndsEarly != null && KnightDuel.isAvailable(widget.state);

  Widget _duelButton() {
    final knight = KnightDuel.aliveKnightSeat(widget.state);

    return OutlinedButton.icon(
      onPressed: _toDuel,
      style: OutlinedButton.styleFrom(foregroundColor: WgmTheme.godColor),
      icon: const Icon(Icons.shield_moon_rounded, size: 18),
      label: Text('騎士翻牌決鬥（$knight 號）'),
    );
  }

  void _toDuel() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (inner) => KnightDuelPage(
          state: widget.state,
          // 決鬥到好人：騎士自刎，白天照常走完發言再投票。
          onDayContinues: () {
            Navigator.of(inner).pop();
            setState(() {});
          },
          // 決鬥到狼：跳過剩下的發言與投票，直接進黑夜。
          onDayEnds: widget.onDayEndsEarly!,
        ),
      ),
    );
  }
}
