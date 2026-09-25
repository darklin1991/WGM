import 'package:flutter/material.dart';

import '../../core/engine/badge_succession.dart';
import '../../core/engine/speech_timer.dart';
import '../../core/engine/vote_resolver.dart';
import '../../core/engine/win_checker.dart';
import '../../core/models/game_state.dart';
import '../../shared/theme.dart';
import '../night/seat_picker.dart';
import '../review/game_over_page.dart';
import '../review/review_log_button.dart';
import 'speech_timer_page.dart';
import 'speech_timer_view.dart';

/// 放逐投票頁。
///
/// 投票採**按對象歸票**，與警長競選同一套操作：法官喊「投 N 號的請舉手」，
/// 先點上方的對象，再圈選舉手的人。
///
/// 規則（誰有票、警長加權、平票、放逐後的死亡連鎖）全在 [ExileVote] 裡。
class ExileVotePage extends StatefulWidget {
  const ExileVotePage({
    super.key,
    required this.state,
    required this.onFinished,
  });

  final GameState state;

  /// 放逐流程跑完、且還沒分出勝負時要做什麼（警徽流，或直接進下一夜）。
  ///
  /// 放逐、開槍、殉情都可能當場結束遊戲 —— 那種情況直接進結果頁，不會呼叫這個。
  final VoidCallback onFinished;

  static Route<void> route(
    GameState state, {
    required Route<void> Function() next,
  }) =>
      MaterialPageRoute<void>(
        builder: (context) => ExileVotePage(
          state: state,
          onFinished: () => Navigator.of(context).pushReplacement(next()),
        ),
      );

  @override
  State<ExileVotePage> createState() => _ExileVotePageState();
}

class _ExileVotePageState extends State<ExileVotePage> {
  late final ExileVote _v;

  /// 開槍階段選定的目標。
  int? _shotTarget;

  @override
  void initState() {
    super.initState();
    _v = ExileVote(state: widget.state);
  }

  bool get _isVoting =>
      _v.stage == ExileStage.vote || _v.stage == ExileStage.runoffVote;

  bool get _isShooting => _v.stage == ExileStage.shoot;

  bool get _isRunoffSpeech => _v.stage == ExileStage.runoffSpeech;

  /// PK 發言那一階段的碼表。進到那一階段才建，離開就丟掉。
  SpeechTimer? _speech;

  SpeechTimer get _speechTimer => _speech ??= SpeechTimer(
        order: _v.runoffSpeechOrder,
        seconds: widget.state.preset.rules.speechSeconds,
      );

  String get _title => switch (_v.stage) {
        ExileStage.vote => '放逐投票',
        ExileStage.runoffSpeech => '平票 PK 發言',
        ExileStage.runoffVote => '平票 PK · 重新投票',
        ExileStage.shoot => '${_v.shooterSeat} 號要開槍帶走誰？',
        ExileStage.pufferfishReveal => '河豚要翻牌嗎？',
        ExileStage.done => '放逐結算',
      };

  String get _hint => switch (_v.stage) {
        ExileStage.vote || ExileStage.runoffVote => _v.focusedTarget == null
            ? '先點上方的對象，再圈選投給他的人'
            : '喊「投 ${_v.focusedTarget} 號的請舉手」，圈選舉手的人',
        ExileStage.runoffSpeech => '平票者各講一輪，講完開始重投',
        ExileStage.shoot => '不開槍請直接按下一步',
        ExileStage.pufferfishReveal =>
          '翻牌會帶走投他的 ${_v.pufferfishVoters.length} 位，被帶走的人不能開槍。'
              '不翻請直接按下一步',
        ExileStage.done => '',
      };

  Set<int> get _selectable {
    if (_isShooting) return _v.shootTargets;
    if (!_isVoting || _v.focusedTarget == null) return const {};
    return _v.eligibleVoters
        .where((s) => _v.canAssignVote(s) || _v.votes[s] == _v.focusedTarget)
        .toSet();
  }

  Set<int> get _selected {
    if (_isShooting) return {?_shotTarget};
    if (!_isVoting) return const {};
    return {
      for (final e in _v.votes.entries)
        if (e.value == _v.focusedTarget) e.key,
    };
  }

  Map<int, String>? get _disabledReasons {
    if (_isShooting) return seatBlockReasonsZh(_v.shootBlockedSeats);
    if (!_isVoting) return null;
    final reasons = <int, String>{};
    for (final seat in widget.state.alivePlayers.map((p) => p.seat)) {
      if (!_v.eligibleVoters.contains(seat)) {
        reasons[seat] = _v.runoffTargets.contains(seat) ? 'PK 中' : '無投票權';
      } else if (_v.votes.containsKey(seat) &&
          _v.votes[seat] != _v.focusedTarget) {
        reasons[seat] = '已投 ${_v.votes[seat]} 號';
      }
    }
    return reasons.isEmpty ? null : reasons;
  }

  void _tapSeat(int seat) {
    setState(() {
      if (_isShooting) {
        _shotTarget = _shotTarget == seat ? null : seat;
        return;
      }
      _v.toggleVote(seat);
    });
  }

  /// 遺言計時。講完退回這一頁，法官再按下一步 —— 不接管流程。
  void _toLastWords() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (inner) => SpeechTimerPage(
          state: widget.state,
          order: _v.lastWordsSeats,
          phase: SpeechPhase.lastWords,
          finishLabel: '遺言結束',
          onFinished: () => Navigator.of(inner).pop(),
        ),
      ),
    );
  }

  void _next() {
    // 已經結算完 —— 這一按是「離開這一頁」。結算完不立刻走，是要讓法官
    // 先把出局與開槍的結果宣布完，也留一個撤銷誤觸的機會。
    if (_v.finished) {
      widget.onFinished();
      return;
    }

    _advance(() {
      if (_isShooting) {
        _v.shoot(_shotTarget);
      } else {
        _v.next();
      }
    });
  }

  /// 推進一步；推到結算完就檢查勝負。
  ///
  /// 會推進流程的按鈕（下一步、河豚翻牌）都要走這裡 —— 自己呼叫 `_v` 的話，
  /// 結算完那一刻就漏掉勝負檢查，之後那一按直接走 `onFinished` 進下一夜。
  void _advance(VoidCallback action) {
    setState(() {
      action();
      _speech = null;
    });
    if (!_v.finished) return;

    // 放逐、開槍、殉情都可能當場分出勝負 —— 每次死亡後都要重新檢查。
    // 分出勝負就沒有「下一夜」可走，直接進結果頁。
    final win = WinChecker.check(widget.state);
    if (win.isOver) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GameOverPage(state: widget.state, check: win),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${widget.state.dayNumber} 天　放逐'),
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
                  _title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_hint.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _hint,
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
                  // PK 發言：整個版面換成碼表，不用座位格。
                  if (_isRunoffSpeech)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SpeechTimerView(
                        timer: _speechTimer,
                        phase: SpeechPhase.runoff,
                        onFinished: _next,
                      ),
                    )
                  else ...[
                    if (_isVoting) _targetRow(scheme),
                    SeatPicker(
                      state: widget.state,
                      selected: _selected,
                      onTap: _tapSeat,
                      selectableSeats: _selectable,
                      disabledReason: _disabledReasons,
                      showRoleName: true,
                    ),
                    if (_isVoting) _tallyCard(scheme),
                    if (_v.finished) _resultCard(scheme),
                  ],
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
                  if (_v.canUndo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _v.undo();
                          _speech = null;
                        }),
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: Text('撤銷上一步（${_v.undoLabel}）'),
                      ),
                    ),
                  // 遺言由法官決定要不要給 —— 誰有遺言權各家規則不同，
                  // App 不替桌上決定，只在有人出局時提供碼表。
                  if (_v.finished && _v.lastWordsSeats.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: _toLastWords,
                        icon: const Icon(
                          Icons.record_voice_over_outlined,
                          size: 18,
                        ),
                        label: Text(
                          '${_v.lastWordsSeats.join('、')} 號遺言計時',
                        ),
                      ),
                    ),
                  // 河豚翻牌是主動技能，要明確按下去才發動 ——
                  // 下面那顆通用的下一步是「不翻」。
                  if (_v.stage == ExileStage.pufferfishReveal)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FilledButton.icon(
                        onPressed: () => _advance(
                          () => _v.revealPufferfish(activate: true),
                        ),
                        icon: const Icon(Icons.flare_rounded, size: 18),
                        label: Text(
                          '翻牌帶走 '
                          '${(_v.pufferfishVoters.toList()..sort()).join("、")} 號',
                        ),
                      ),
                    ),
                  // PK 發言的推進鍵長在碼表上，這裡不要再放一顆。
                  if (!_isRunoffSpeech)
                    FilledButton(
                      onPressed: _next,
                      child: Text(_nextLabel),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _nextLabel => switch (_v.stage) {
        ExileStage.vote || ExileStage.runoffVote => '算票',
        ExileStage.runoffSpeech => 'PK 發言結束，開始重投',
        ExileStage.shoot =>
          _shotTarget == null ? '放棄開槍' : '開槍帶走 $_shotTarget 號',
        // 翻牌是主動技能，得另外按一顆；這顆是「不翻」。
        ExileStage.pufferfishReveal => '不翻牌',
        // 放逐或開槍把警長帶走時，下一站是警徽流而不是黑夜 —— 按鈕要講實話。
        ExileStage.done => BadgeSuccession.isDue(widget.state)
            ? '接著處理警徽流'
            : '進入下一夜',
      };

  /// 歸票對象那一排。放逐投票**任何存活玩家都能被投**，所以列出全部。
  Widget _targetRow(ColorScheme scheme) {
    final targets = _v.votableTargets.toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _v.isRunoff ? 'PK 名單' : '歸票對象',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final seat in targets)
                ChoiceChip(
                  label: Text('$seat'),
                  selected: _v.focusedTarget == seat,
                  onSelected: (_) => setState(() => _v.focusTarget(seat)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 即時票數與未投票名單。警長票是 1.5，所以會出現小數。
  Widget _tallyCard(ColorScheme scheme) {
    final tally = _v.tally;
    final pending = _v.notYetVoted.toList()..sort();
    final entries = tally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '目前票數',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              if (entries.isEmpty)
                Text(
                  '還沒有人投票',
                  style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                )
              else
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final e in entries)
                      Text(
                        '${e.key} 號 ${_formatVotes(e.value)} 票',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              if (widget.state.sheriffSeat != null) ...[
                const SizedBox(height: 6),
                Text(
                  '警長（${widget.state.sheriffSeat} 號）的票算 '
                  '${_formatVotes(widget.state.preset.rules.sheriffVoteWeight)} 票',
                  style: TextStyle(fontSize: 12, color: WgmTheme.godColor),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                pending.isEmpty
                    ? '所有人都投完了'
                    : '尚未投票：${pending.join('、')} 號（按算票就當棄票）',
                style: TextStyle(
                  fontSize: 13,
                  color: pending.isEmpty
                      ? WgmTheme.godColor
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 放逐結算摘要。法官照著這張卡宣布出局名單，確認無誤才按進下一夜。
  Widget _resultCard(ColorScheme scheme) {
    // [ExileVote.notes] 已經把平票、白痴翻牌、殉情、開槍全寫進去了，
    // 這裡照順序念出來就是完整的宣布稿，不要在頁面再組一次句子。
    final lines = _v.notes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '結算結果',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (_v.deaths.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '本輪出局：'
                  '${_v.deaths.map((d) => '${d.seat} 號（${d.cause.labelZh}）').join('、')}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: WgmTheme.deadColor,
                  ),
                ),
              ],
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
