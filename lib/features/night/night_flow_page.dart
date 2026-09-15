import 'package:flutter/material.dart';

import '../../core/engine/night_arbitrator.dart';
import '../../core/engine/night_flow.dart';
import '../../core/models/game_state.dart';
import '../../core/models/night_action.dart';
import '../../core/models/role.dart';
import '../../shared/theme.dart';
import 'night_result_page.dart';
import 'seat_picker.dart';

/// 一個步驟內的子階段。
enum _Sub {
  /// 登記座次：「守衛請睜眼，你是幾號」。
  registerSeats,

  /// 狼隊登記完後指定哪一位是狼王。
  pickWolfKing,

  /// 選擇技能目標。
  chooseTarget,

  /// 女巫：是否對刀口下解藥。
  witchHeal,

  /// 女巫：是否毒人。
  witchPoison,

  /// 獵人：法官給「可否開槍」的手勢。
  hunterGesture,
}

/// 夜晚流程頁。
///
/// 首夜的流程是「先登記是誰，再發動技能」，依板子的夜晚順序逐一進行；
/// 第二夜起身分已知，直接收集技能目標。
/// 走完所有特殊身分後，剩下的座次自動填為平民。
class NightFlowPage extends StatefulWidget {
  const NightFlowPage({super.key, required this.state});

  final GameState state;

  @override
  State<NightFlowPage> createState() => _NightFlowPageState();
}

class _NightFlowPageState extends State<NightFlowPage> {
  static const _arbitrator = NightArbitrator();

  GameState get _state => widget.state;

  late final bool _isFirstNight;
  late final List<NightStep> _steps;
  late final NightActions _actions;

  int _stepIndex = 0;
  _Sub _sub = _Sub.registerSeats;
  final Set<int> _picked = {};

  @override
  void initState() {
    super.initState();
    _isFirstNight = _state.dayNumber == 0;
    _state.dayNumber = _isFirstNight ? 1 : _state.dayNumber + 1;
    _state.phase = GamePhase.night;
    _steps = _isFirstNight
        ? NightFlow.firstNightSteps(_state.preset)
        : NightFlow.laterNightSteps(_state.preset);
    _actions = NightActions(night: _state.dayNumber);
    // 開場也可能要跳過（例如守衛已死，第一個步驟就該略過）。
    _stepIndex = _firstPlayableStepFrom(0);
    _sub = _initialSubFor(_step);
  }

  NightStep get _step => _steps[_stepIndex];

  _Sub _initialSubFor(NightStep step) {
    if (_isFirstNight && step.seatCount > 0) return _Sub.registerSeats;
    if (step.skill == NightSkill.witchPotion) return _Sub.witchHeal;
    if (step.skill == NightSkill.hunterGesture) return _Sub.hunterGesture;
    return _Sub.chooseTarget;
  }

  /// 該步驟的角色是否全部出局 —— 死人不睜眼，這種步驟要跳過。
  ///
  /// 首夜不跳過（全員存活，且需要登記身分）。
  bool _shouldSkip(NightStep step) {
    if (_isFirstNight) return false;
    for (final role in step.roles) {
      final alive = _state
          .seatsOfRole(role.id)
          .any((seat) => _state.playerAt(seat).alive);
      if (alive) return false;
    }
    return true;
  }

  /// 從 [from] 起找第一個還需要進行的步驟；找不到回傳 [_steps].length。
  int _firstPlayableStepFrom(int from) {
    var i = from;
    while (i < _steps.length && _shouldSkip(_steps[i])) {
      i++;
    }
    return i;
  }

  /// 尚未登記身分的座次 —— 登記階段只能從這裡挑。
  Set<int> get _unassignedSeats => _state.players
      .where((p) => p.role == null)
      .map((p) => p.seat)
      .toSet();

  int get _requiredPickCount => switch (_sub) {
        _Sub.registerSeats => _step.seatCount,
        _Sub.pickWolfKing => _step.wolfKingCount,
        _Sub.hunterGesture => 0,
        _ => 1,
      };

  bool get _canProceed {
    switch (_sub) {
      case _Sub.registerSeats:
      case _Sub.pickWolfKing:
        return _picked.length == _requiredPickCount;
      case _Sub.chooseTarget:
      case _Sub.witchHeal:
      case _Sub.witchPoison:
        // 技能目標可以放棄（空刀、不用藥），因此不強制選取。
        return true;
      case _Sub.hunterGesture:
        // 只是確認手勢，沒有要選的東西。
        return true;
    }
  }

  void _toggleSeat(int seat) {
    setState(() {
      if (_picked.contains(seat)) {
        _picked.remove(seat);
        return;
      }
      if (_requiredPickCount == 1) {
        _picked
          ..clear()
          ..add(seat);
      } else if (_picked.length < _requiredPickCount) {
        _picked.add(seat);
      }
    });
  }

  void _next() {
    setState(() {
      switch (_sub) {
        case _Sub.registerSeats:
          _commitSeatRegistration();
          _picked.clear();
          if (_step.needsWolfKingPick) {
            _sub = _Sub.pickWolfKing;
          } else if (_step.skill == NightSkill.none) {
            _advanceStep();
          } else if (_step.skill == NightSkill.witchPotion) {
            _sub = _Sub.witchHeal;
          } else if (_step.skill == NightSkill.hunterGesture) {
            _sub = _Sub.hunterGesture;
          } else {
            _sub = _Sub.chooseTarget;
          }

        case _Sub.pickWolfKing:
          _state.playerAt(_picked.first).role = Roles.wolfKing;
          _picked.clear();
          _sub = _Sub.chooseTarget;

        case _Sub.chooseTarget:
          _commitTarget();
          _picked.clear();
          _advanceStep();

        case _Sub.witchHeal:
          _actions.witchHealTarget = _picked.isEmpty ? null : _picked.first;
          _picked.clear();
          _sub = _Sub.witchPoison;

        case _Sub.witchPoison:
          _actions.witchPoisonTarget = _picked.isEmpty ? null : _picked.first;
          _picked.clear();
          _advanceStep();

        case _Sub.hunterGesture:
          // 只是確認手勢，沒有要記錄的行動。
          _advanceStep();
      }
    });
  }

  /// 把登記的座次寫成身分。狼隊先全部記為一般狼，稍後再挑出狼王。
  void _commitSeatRegistration() {
    final role = _step.roles.first;
    for (final seat in _picked) {
      _state.playerAt(seat).role = role;
    }
  }

  void _commitTarget() {
    final target = _picked.isEmpty ? null : _picked.first;
    switch (_step.skill) {
      case NightSkill.guardProtect:
        _actions.guardTarget = target;
      case NightSkill.wolfKill:
        _actions.wolfTarget = target;
      case NightSkill.seerInspect:
        _actions.seerTarget = target;
      case NightSkill.witchPotion:
      case NightSkill.hunterGesture:
      case NightSkill.none:
        break;
    }
  }

  void _advanceStep() {
    final next = _firstPlayableStepFrom(_stepIndex + 1);
    if (next >= _steps.length) {
      _finish();
      return;
    }
    _stepIndex = next;
    _sub = _initialSubFor(_step);
  }

  void _finish() {
    // 走完所有特殊身分，剩下的座次就是平民。
    final villagers =
        _isFirstNight ? _state.assignRemainingAsVillager() : <int>[];

    final outcome = _arbitrator.settle(_state, _actions);
    _arbitrator.apply(_state, _actions, outcome);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NightResultPage(
          state: _state,
          outcome: outcome,
          autoFilledVillagers: villagers,
        ),
      ),
    );
  }

  // ---- 以下為各子階段的呈現內容 ----

  /// 獵人今晚能不能開槍 —— 決定法官要給哪個手勢。
  bool get _hunterCanShoot =>
      _arbitrator.hunterCanShootTonight(_state, _actions);

  String get _title => switch (_sub) {
        _Sub.registerSeats => '${_step.title}請睜眼',
        _Sub.pickWolfKing => '哪一位是狼王？',
        _Sub.witchHeal => '女巫：要用解藥嗎？',
        _Sub.witchPoison => '女巫：要用毒藥嗎？',
        _Sub.hunterGesture => '獵人請睜眼',
        _Sub.chooseTarget => switch (_step.skill) {
            NightSkill.guardProtect => '守衛要守誰？',
            NightSkill.wolfKill => '狼人要刀誰？',
            NightSkill.seerInspect => '預言家要查驗誰？',
            _ => _step.title,
          },
      };

  String get _hint => switch (_sub) {
        // 獵人、白痴這類角色沒有夜間行動，只是叫起來確認號碼 ——
        // 要講明按下一步就結束，否則法官會等在這裡以為還有技能要選。
        _Sub.registerSeats => _step.skill == NightSkill.none
            ? '確認號碼即可，${_step.title}沒有夜間行動'
            : _step.skill == NightSkill.hunterGesture
                ? '請填入座次號碼，接著給開槍手勢'
                : _step.seatCount > 1
                    ? '請填入 ${_step.seatCount} 位的座次號碼'
                    : '請填入座次號碼',
        _Sub.hunterGesture => '請對獵人做出下面的手勢',
        _Sub.pickWolfKing => '狼王出局時可以開槍帶人，需要單獨記錄',
        _Sub.witchHeal => _witchHealHint,
        _Sub.witchPoison => _state.witchPoisonAvailable
            ? '不使用請直接按下一步'
            : '毒藥已在之前的夜晚用掉了',
        _Sub.chooseTarget => switch (_step.skill) {
            NightSkill.wolfKill => '空刀請直接按下一步',
            NightSkill.guardProtect =>
              _state.lastGuardTarget != null &&
                      _state.preset.rules.guardCannotRepeatTarget
                  ? '不可連續兩晚守同一人（昨晚守了 ${_state.lastGuardTarget} 號）'
                  : '不守請直接按下一步',
            _ => '',
          },
      };

  String get _witchHealHint {
    if (!_state.witchAntidoteAvailable) return '解藥已在之前的夜晚用掉了';
    final knifed = _actions.wolfTarget;
    if (knifed == null) return '今晚沒有人被刀';
    final selfSeat = _state.seatOfRole(Roles.witch.id);
    final isSelf = selfSeat == knifed;
    final maySelfHeal =
        _state.preset.rules.witchMaySelfHeal(_actions.night);
    if (isSelf && !maySelfHeal) {
      return '今晚 $knifed 號被刀，但那是女巫自己，本局規則不可自救';
    }
    return '今晚 $knifed 號被刀。要救請點選，不救請直接按下一步';
  }

  /// 登記階段只能挑未指定身分的座次；技能階段可挑存活座次。
  Set<int>? get _selectableSeats {
    switch (_sub) {
      case _Sub.hunterGesture:
        return const {};
      case _Sub.registerSeats:
        return _unassignedSeats;
      case _Sub.pickWolfKing:
        // 只能從剛登記的狼隊成員裡挑。
        return _state.seatsOfRole(Roles.wolf.id).toSet();
      case _Sub.witchHeal:
        if (!_state.witchAntidoteAvailable) return const {};
        final knifed = _actions.wolfTarget;
        if (knifed == null) return const {};
        final selfSeat = _state.seatOfRole(Roles.witch.id);
        if (selfSeat == knifed &&
            !_state.preset.rules.witchMaySelfHeal(_actions.night)) {
          return const {};
        }
        // 解藥只能救今晚的刀口。
        return {knifed};
      case _Sub.witchPoison:
        if (!_state.witchPoisonAvailable) return const {};
        if (!_state.preset.rules.witchDualUseSameNight &&
            _actions.witchHealTarget != null) {
          return const {};
        }
        return null;
      case _Sub.chooseTarget:
        if (_step.skill == NightSkill.guardProtect) {
          final all = _state.alivePlayers.map((p) => p.seat).toSet();
          final last = _state.lastGuardTarget;
          if (last != null && _state.preset.rules.guardCannotRepeatTarget) {
            all.remove(last);
          }
          return all;
        }
        return null;
    }
  }

  Map<int, String>? get _disabledReasons {
    if (_sub == _Sub.chooseTarget &&
        _step.skill == NightSkill.guardProtect &&
        _state.lastGuardTarget != null &&
        _state.preset.rules.guardCannotRepeatTarget) {
      return {_state.lastGuardTarget!: '昨晚已守'};
    }
    if (_sub == _Sub.witchPoison &&
        !_state.preset.rules.witchDualUseSameNight &&
        _actions.witchHealTarget != null) {
      return {
        for (final p in _state.players) p.seat: '本局不可同夜雙藥',
      };
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepLabel = '${_stepIndex + 1}/${_steps.length}';

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${_actions.night} 夜　$stepLabel'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 10, right: 16),
            child: Row(
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0)
                    Text(
                      ' → ',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  Text(
                    _steps[i].title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          i == _stepIndex ? FontWeight.w800 : FontWeight.w400,
                      color: i == _stepIndex
                          ? scheme.primary
                          : i < _stepIndex
                              ? scheme.onSurfaceVariant
                              : scheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                  const SizedBox(height: 6),
                  Text(
                    _hint,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: _sub == _Sub.hunterGesture
                  ? _HunterGestureCard(
                      hunterSeat: _state.seatOfRole(Roles.hunter.id),
                      canShoot: _hunterCanShoot,
                      poisonedTonight:
                          _actions.witchPoisonTarget ==
                              _state.seatOfRole(Roles.hunter.id),
                    )
                  : SeatPicker(
                      state: _state,
                      selected: _picked,
                      onTap: _toggleSeat,
                      selectableSeats: _selectableSeats,
                      disabledReason: _disabledReasons,
                      showRoleName: _sub != _Sub.registerSeats,
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  if (_requiredPickCount > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '已選 ${_picked.length}/$_requiredPickCount：'
                        '${(_picked.toList()..sort()).join('、')}',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _canProceed ? _next : null,
                    child: Text(_canProceed ? '下一步' : _blockedLabel),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _blockedLabel => switch (_sub) {
        _Sub.registerSeats =>
          '請選滿 ${_step.seatCount} 位（已選 ${_picked.length}）',
        _Sub.pickWolfKing => '請指定狼王',
        _ => '下一步',
      };
}

/// 獵人開槍手勢卡。
///
/// 法官每晚都要叫獵人起來，用手勢告知技能是否可用。做成一眼可辨的大卡片，
/// 因為現場光線差、動作要快，法官不該還要自己推「被毒了所以不能開槍」。
class _HunterGestureCard extends StatelessWidget {
  const _HunterGestureCard({
    required this.hunterSeat,
    required this.canShoot,
    required this.poisonedTonight,
  });

  final int? hunterSeat;
  final bool canShoot;
  final bool poisonedTonight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = canShoot ? WgmTheme.godColor : WgmTheme.wolfColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Column(
                children: [
                  Icon(
                    canShoot
                        ? Icons.thumb_up_rounded
                        : Icons.thumb_down_rounded,
                    size: 72,
                    color: color,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    canShoot ? '拇指向上' : '拇指向下',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    canShoot ? '可以開槍' : '不可開槍',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            switch (true) {
              _ when hunterSeat == null => '此局沒有獵人',
              _ when poisonedTonight => '獵人（$hunterSeat 號）今晚被毒，'
                  '依規則不可開槍',
              _ when canShoot => '獵人為 $hunterSeat 號，技能正常',
              _ => '獵人（$hunterSeat 號）目前無法開槍',
            },
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
