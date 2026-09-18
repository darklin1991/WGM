import 'package:flutter/material.dart';

import '../../core/engine/day_controller.dart';
import '../../core/models/game_state.dart';
import '../../shared/theme.dart';
import '../night/seat_picker.dart';

/// 警長競選頁。
///
/// 第一天天亮後的第一件事，**排在公布死訊之前** —— 昨晚死的人這時還沒被公布，
/// 照樣可以上警、可以投票。
///
/// 規則（誰能投、票怎麼算、平票怎麼處理）全在 [SheriffElection] 裡，
/// 這一頁只負責畫出來並把操作轉回去。
class SheriffElectionPage extends StatefulWidget {
  const SheriffElectionPage({
    super.key,
    required this.state,
    required this.onFinished,
  });

  final GameState state;

  /// 競選結束後要做什麼（通常是接著公布死訊）。
  final VoidCallback onFinished;

  @override
  State<SheriffElectionPage> createState() => _SheriffElectionPageState();
}

class _SheriffElectionPageState extends State<SheriffElectionPage> {
  late final SheriffElection _e;

  @override
  void initState() {
    super.initState();
    _e = SheriffElection(state: widget.state);
  }

  bool get _isVoting =>
      _e.stage == ElectionStage.vote || _e.stage == ElectionStage.runoffVote;

  void _next() {
    setState(_e.next);
    if (_e.finished) widget.onFinished();
  }

  String get _title => switch (_e.stage) {
        ElectionStage.nominate => '要上警的請舉手',
        ElectionStage.withdraw => '有人要退水嗎？',
        ElectionStage.vote => '警長投票',
        ElectionStage.runoffVote => '平票 PK · 重新投票',
        ElectionStage.done => '競選結束',
      };

  String get _hint => switch (_e.stage) {
        ElectionStage.nominate =>
          '圈選所有上警的人。沒人上警就直接按下一步，本局無警長',
        ElectionStage.withdraw =>
          '警上發言結束後問一次。沒人退水就直接按下一步',
        ElectionStage.vote || ElectionStage.runoffVote =>
          _e.focusedCandidate == null
              ? '先點上方的候選人，再圈選投給他的人'
              : '喊「投 ${_e.focusedCandidate} 號的請舉手」，圈選舉手的人',
        ElectionStage.done => '',
      };

  /// 這一步座位格能選誰。
  Set<int> get _selectable {
    switch (_e.stage) {
      case ElectionStage.nominate:
        return _e.state.alivePlayers.map((p) => p.seat).toSet();
      case ElectionStage.withdraw:
        return _e.candidates;
      case ElectionStage.vote:
      case ElectionStage.runoffVote:
        if (_e.focusedCandidate == null) return const {};
        // 已投給目前候選人的要留著（才點得掉），投給別人的擋住。
        return _e.eligibleVoters
            .where((s) => _e.canAssignVote(s) || _e.votes[s] == _e.focusedCandidate)
            .toSet();
      case ElectionStage.done:
        return const {};
    }
  }

  /// 目前圈起來的座次。
  Set<int> get _selected => switch (_e.stage) {
        ElectionStage.nominate => _e.candidates,
        ElectionStage.withdraw => _e.withdrawn,
        ElectionStage.vote || ElectionStage.runoffVote => {
            for (final entry in _e.votes.entries)
              if (entry.value == _e.focusedCandidate) entry.key,
          },
        ElectionStage.done => const {},
      };

  Map<int, String>? get _disabledReasons {
    if (!_isVoting) return null;
    final reasons = <int, String>{};
    for (final seat in _e.state.alivePlayers.map((p) => p.seat)) {
      if (!_e.eligibleVoters.contains(seat)) {
        reasons[seat] = _e.withdrawn.contains(seat) ? '已退水' : '候選人';
      } else if (_e.votes.containsKey(seat) &&
          _e.votes[seat] != _e.focusedCandidate) {
        reasons[seat] = '已投 ${_e.votes[seat]} 號';
      }
    }
    return reasons.isEmpty ? null : reasons;
  }

  void _tapSeat(int seat) {
    setState(() {
      switch (_e.stage) {
        case ElectionStage.nominate:
          _e.toggleCandidate(seat);
        case ElectionStage.withdraw:
          _e.toggleWithdraw(seat);
        case ElectionStage.vote:
        case ElectionStage.runoffVote:
          _e.toggleVote(seat);
        case ElectionStage.done:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('第 1 天　警長競選')),
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
                  // 投票階段：上方先挑要歸票的候選人。
                  if (_isVoting) _candidateRow(scheme),
                  SeatPicker(
                    state: _e.state,
                    selected: _selected,
                    onTap: _tapSeat,
                    selectableSeats: _selectable,
                    disabledReason: _disabledReasons,
                    showRoleName: true,
                  ),
                  if (_isVoting) _tallyCard(scheme),
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
                  if (_e.canUndo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => setState(_e.undo),
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: Text('撤銷上一步（${_e.undoLabel}）'),
                      ),
                    ),
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

  String get _nextLabel => switch (_e.stage) {
        ElectionStage.nominate =>
          _e.candidates.isEmpty ? '沒人上警，跳過競選' : '上警完畢',
        ElectionStage.withdraw => '退水完畢，開始投票',
        ElectionStage.vote || ElectionStage.runoffVote => '算票',
        ElectionStage.done => '下一步',
      };

  /// 候選人那一排 —— 點一個就是「現在要歸誰的票」。
  Widget _candidateRow(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '候選人',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final seat in (_e.activeCandidates.toList()..sort()))
                ChoiceChip(
                  label: Text('$seat 號'),
                  selected: _e.focusedCandidate == seat,
                  onSelected: (_) => setState(() => _e.focusCandidate(seat)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 即時票數與未投票名單 —— 法官不必心算，也不會漏人。
  Widget _tallyCard(ColorScheme scheme) {
    final tally = _e.tally;
    final pending = _e.notYetVoted.toList()..sort();

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
              Wrap(
                spacing: 14,
                children: [
                  for (final seat in (tally.keys.toList()..sort()))
                    Text(
                      '$seat 號 ${tally[seat]} 票',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                pending.isEmpty
                    ? '所有人都投完了'
                    : '尚未投票：${pending.join('、')} 號'
                        '（按下一步就當棄票）',
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
}
