import 'package:flutter/material.dart';

import '../../core/engine/night_death_shot.dart';
import '../../core/engine/speech_timer.dart';
import '../../core/engine/win_checker.dart';
import '../../core/models/game_state.dart';
import '../night/seat_picker.dart';
import '../review/game_over_page.dart';
import '../review/review_log_button.dart';
import 'speech_timer_page.dart';

/// 夜死開槍頁：夜裡出局的獵人／狼王，天亮後由法官記下開槍目標。
///
/// 規則（誰能開、能打誰、打完誰死）全在 [NightDeathShot] 裡，
/// 這一頁只負責把選擇畫出來。
class NightDeathShotPage extends StatefulWidget {
  const NightDeathShotPage({
    super.key,
    required this.state,
    required this.shooters,
    required this.onFinished,
  });

  final GameState state;

  /// 依序要開槍的座次（`NightOutcome.shooterSeats`）。
  final List<int> shooters;

  /// 開完槍、勝負未分時要做什麼（接警徽流與發言順序）。
  ///
  /// 帶進被帶走的座次（含殉情）—— 發言順序的「單死／雙死」要把他們算進去
  /// （擔當 2026-09-24 指定）。
  final void Function(List<int> taken) onFinished;

  static Route<void> route(
    GameState state, {
    required List<int> shooters,
    required Route<void> Function(List<int> taken) next,
  }) =>
      MaterialPageRoute<void>(
        builder: (context) => NightDeathShotPage(
          state: state,
          shooters: shooters,
          onFinished: (taken) =>
              Navigator.of(context).pushReplacement(next(taken)),
        ),
      );

  /// 有人能開槍就先開，沒有就直接走 [next]。
  static Route<void> routeIfDue(
    GameState state, {
    required List<int> shooters,
    required Route<void> Function(List<int> taken) next,
  }) =>
      shooters.isEmpty
          ? next(const [])
          : route(state, shooters: shooters, next: next);

  @override
  State<NightDeathShotPage> createState() => _NightDeathShotPageState();
}

class _NightDeathShotPageState extends State<NightDeathShotPage> {
  late final NightDeathShot _s;

  /// 還沒按下去之前先選起來的目標。
  int? _picked;

  @override
  void initState() {
    super.initState();
    _s = NightDeathShot(state: widget.state, shooters: widget.shooters);
  }

  void _shoot(int? seat) {
    setState(() {
      _s.shoot(seat);
      _picked = null;
    });

    // 開槍可能當場分出勝負（例如帶走最後一匹狼）—— 每次死亡後都要重新檢查。
    final win = WinChecker.check(widget.state);
    if (win.isOver) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GameOverPage(state: widget.state, check: win),
        ),
      );
    }
  }

  void _undo() {
    setState(() {
      _s.undo();
      _picked = null;
    });
  }

  void _toLastWords() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (inner) => SpeechTimerPage(
          state: widget.state,
          order: _s.lastWordsSeats,
          phase: SpeechPhase.lastWords,
          finishLabel: '遺言結束',
          onFinished: () => Navigator.of(inner).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shooter = _s.currentShooter;

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${widget.state.dayNumber} 天　開槍'),
        automaticallyImplyLeading: false,
        actions: [ReviewLogButton(state: widget.state)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shooter == null
                      ? '開槍結果'
                      : '$shooter 號'
                          '（${widget.state.playerAt(shooter).role?.nameZh ?? "?"}）'
                          '可以開槍',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (shooter != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '問「要帶走誰？」—— 點選目標，或放棄開槍',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeatPicker(
                    state: widget.state,
                    selected: {?_picked},
                    onTap: _s.finished
                        ? (_) {}
                        : (seat) => setState(
                              () => _picked = _picked == seat ? null : seat,
                            ),
                    selectableSeats: _s.finished ? const {} : _s.targets,
                    disabledReason:
                        _s.finished ? null : seatBlockReasonsZh(_s.blockedSeats),
                    showRoleName: true,
                  ),
                  if (_s.notes.isNotEmpty) _resultCard(scheme),
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
                  if (_s.canUndo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: _undo,
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: Text('撤銷上一步（${_s.undoLabel}）'),
                      ),
                    ),
                  if (_s.finished) ...[
                    // 遺言要不要給由法官決定，App 只提供碼表。
                    if (_s.lastWordsSeats.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: _toLastWords,
                          icon: const Icon(
                            Icons.record_voice_over_outlined,
                            size: 18,
                          ),
                          label: Text(
                            '${_s.lastWordsSeats.join('、')} 號遺言計時',
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: () => widget.onFinished(
                        _s.deaths.map((d) => d.seat).toList(),
                      ),
                      child: const Text('繼續'),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed: _picked == null ? null : () => _shoot(_picked),
                      icon: const Icon(Icons.crisis_alert_rounded),
                      label: Text(
                        _picked == null ? '請先選擇目標' : '開槍帶走 $_picked 號',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => _shoot(null),
                      child: const Text('放棄開槍'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 結果卡。法官照著這張卡宣布。
  Widget _resultCard(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '結果',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              for (final note in _s.notes)
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
