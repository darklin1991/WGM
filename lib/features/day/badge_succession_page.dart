import 'package:flutter/material.dart';

import '../../core/engine/badge_succession.dart';
import '../../core/models/game_state.dart';
import '../../shared/theme.dart';
import '../night/seat_picker.dart';

/// 警徽流頁：警長出局後，由警長指定接任者或撕毀警徽。
///
/// 規則（什麼時候要走、可以交給誰、交完誰是警長）全在 [BadgeSuccession] 裡。
/// 這一頁只負責把選擇畫出來。
///
/// 進這一頁之前請先用 [BadgeSuccession.isDue] 判斷該不該走。
class BadgeSuccessionPage extends StatefulWidget {
  const BadgeSuccessionPage({
    super.key,
    required this.state,
    required this.onFinished,
  });

  final GameState state;

  /// 警徽處理完之後要做什麼（夜死接發言順序，日死接下一夜）。
  final VoidCallback onFinished;

  static Route<void> route(
    GameState state, {
    required Route<void> Function() next,
  }) =>
      MaterialPageRoute<void>(
        builder: (context) => BadgeSuccessionPage(
          state: state,
          onFinished: () => Navigator.of(context).pushReplacement(next()),
        ),
      );

  /// 該走警徽流就先走，不用走就直接走 [next]。
  ///
  /// 呼叫端不必自己判斷 —— 把這個夾在「死亡結算完」與「下一個環節」中間即可。
  /// [next] 是延遲求值的，所以 `isDue` 是在真正要離開前一頁的那一刻才判斷。
  static Route<void> routeIfDue(
    GameState state, {
    required Route<void> Function() next,
  }) =>
      BadgeSuccession.isDue(state) ? route(state, next: next) : next();

  @override
  State<BadgeSuccessionPage> createState() => _BadgeSuccessionPageState();
}

class _BadgeSuccessionPageState extends State<BadgeSuccessionPage> {
  late final BadgeSuccession _b;

  /// 還沒按下去之前先選起來的接任者。
  int? _picked;

  @override
  void initState() {
    super.initState();
    _b = BadgeSuccession(state: widget.state);
  }

  void _pass() {
    final seat = _picked;
    if (seat == null) return;
    setState(() => _b.passTo(seat));
  }

  void _destroy() => setState(_b.destroy);

  void _undo() {
    setState(() {
      _b.undo();
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${widget.state.dayNumber} 天　警徽流'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _b.finished ? '警徽流結果' : '${_b.formerSheriff} 號警長出局',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!_b.finished) ...[
                  const SizedBox(height: 4),
                  Text(
                    _b.mustDestroy
                        ? '場上沒有存活玩家可以接任，只能撕毀'
                        : '問「警徽給誰？」—— 點選接任者，或直接撕毀',
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
                    onTap: _b.finished
                        ? (_) {}
                        : (seat) => setState(
                              () => _picked = _picked == seat ? null : seat,
                            ),
                    selectableSeats: _b.finished ? const {} : _b.candidates,
                    showRoleName: true,
                  ),
                  if (_b.finished) _resultCard(scheme),
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
                  if (_b.canUndo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: _undo,
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: Text('撤銷上一步（${_b.undoLabel}）'),
                      ),
                    ),
                  if (_b.finished)
                    FilledButton(
                      onPressed: widget.onFinished,
                      child: const Text('繼續'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _picked == null ? null : _pass,
                      icon: const Icon(Icons.shield_rounded),
                      label: Text(
                        _picked == null ? '請先選擇接任者' : '警徽移交給 $_picked 號',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _destroy,
                      icon: const Icon(Icons.local_fire_department_rounded),
                      label: const Text('撕毀警徽'),
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

  /// 結果卡。法官照著這張卡宣布，確認無誤才按繼續。
  Widget _resultCard(ColorScheme scheme) {
    final passed = _b.outcome == BadgeOutcome.passed;

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
              for (final note in _b.notes)
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                passed
                    ? '新警長的票算 '
                        '${_formatVotes(widget.state.preset.rules.sheriffVoteWeight)}'
                        ' 票，發言方向也由他決定。'
                    : '之後投票不再有加權票，發言順序改由上帝隨機決定。',
                style: TextStyle(
                  fontSize: 13,
                  color: passed ? WgmTheme.godColor : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 1.5 顯示成 1.5，2.0 顯示成 2。
  String _formatVotes(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
