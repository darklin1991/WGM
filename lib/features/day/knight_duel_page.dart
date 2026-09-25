import 'package:flutter/material.dart';

import '../../core/engine/knight_duel.dart';
import '../../core/engine/win_checker.dart';
import '../../core/models/game_state.dart';
import '../../shared/theme.dart';
import '../night/seat_picker.dart';
import '../review/game_over_page.dart';

/// 騎士決鬥頁。
///
/// 規則（時機、能選誰、誰死、白天要不要就此結束）全在 [KnightDuel] 裡。
///
/// 進這一頁之前請先用 [KnightDuel.isAvailable] 判斷騎士還能不能發動。
class KnightDuelPage extends StatefulWidget {
  const KnightDuelPage({
    super.key,
    required this.state,
    required this.onDayContinues,
    required this.onDayEnds,
  });

  final GameState state;

  /// 決鬥到好人（騎士自刎）—— 白天照常繼續，回到原本的發言流程。
  final VoidCallback onDayContinues;

  /// 決鬥到狼且本局採「決鬥出狼立即進夜」—— 跳過投票直接進黑夜。
  final VoidCallback onDayEnds;

  @override
  State<KnightDuelPage> createState() => _KnightDuelPageState();
}

class _KnightDuelPageState extends State<KnightDuelPage> {
  late final KnightDuel _d;

  /// 還沒按下去之前先選起來的對手。
  int? _picked;

  @override
  void initState() {
    super.initState();
    _d = KnightDuel(state: widget.state);
  }

  void _duel() {
    final seat = _picked;
    if (seat == null) return;
    setState(() => _d.duel(seat));
  }

  void _undo() {
    setState(() {
      _d.undo();
      _picked = null;
    });
  }

  void _continue() {
    // 決鬥與殉情都可能當場分出勝負 —— 每次死亡後都要重新檢查。
    final win = WinChecker.check(widget.state);
    if (win.isOver) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GameOverPage(state: widget.state, check: win),
        ),
      );
      return;
    }

    if (_d.endsDay) {
      widget.onDayEnds();
    } else {
      widget.onDayContinues();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${widget.state.dayNumber} 天　騎士決鬥'),
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
                  _d.finished ? '決鬥結果' : '騎士（${_d.knightSeat} 號）翻牌',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!_d.finished) ...[
                  const SizedBox(height: 4),
                  Text(
                    '點選要決鬥的對象。'
                    '是狼就當場出局並直接進黑夜，是好人則騎士自刎。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
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
                    onTap: _d.finished
                        ? (_) {}
                        : (seat) => setState(
                              () => _picked = _picked == seat ? null : seat,
                            ),
                    selectableSeats: _d.finished ? const {} : _d.opponents,
                    disabledReason: _d.finished
                        ? null
                        : seatBlockReasonsZh(_d.blockedSeats),
                    showRoleName: true,
                  ),
                  if (_d.finished) _resultCard(scheme),
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
                  if (_d.canUndo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: _undo,
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: Text('撤銷上一步（${_d.undoLabel}）'),
                      ),
                    ),
                  if (_d.finished)
                    FilledButton.icon(
                      onPressed: _continue,
                      icon: Icon(
                        _d.endsDay
                            ? Icons.nightlight_round
                            : Icons.record_voice_over_rounded,
                      ),
                      label: Text(_d.endsDay ? '進入黑夜' : '回到發言'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _picked == null ? null : _duel,
                      icon: const Icon(Icons.shield_moon_rounded),
                      label: Text(
                        _picked == null ? '請先選擇對手' : '與 $_picked 號決鬥',
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 法官誤按進來時的退路 —— 還沒指定對手就什麼都沒發生。
                    OutlinedButton(
                      onPressed: widget.onDayContinues,
                      child: const Text('不決鬥，回到發言'),
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

  /// 決鬥結果。法官照著這張卡宣布。
  Widget _resultCard(ColorScheme scheme) {
    final wolfDied = _d.outcome == DuelOutcome.wolfDied;
    final color = wolfDied ? WgmTheme.godColor : WgmTheme.wolfColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _d.outcome!.labelZh,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              // notes 已經把出局、殉情、進不進夜全寫進去了，照順序念即可。
              for (final note in _d.notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    note,
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                '本輪出局：'
                '${_d.deaths.map((d) => '${d.seat} 號（${d.cause.labelZh}）').join('、')}',
                style: const TextStyle(fontSize: 13, color: WgmTheme.deadColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
