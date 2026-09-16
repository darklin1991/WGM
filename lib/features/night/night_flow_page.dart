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

  /// 狼隊登記完後指認特殊成員（狼王、狼美人）。
  pickSpecial,

  /// 選擇技能目標。
  chooseTarget,

  /// 夜晚結尾：法官告知機械狼學到的身分，並給開槍手勢。
  mechanicReveal,

  /// 機械狼那一輪的第一段：法官比手勢告知今晚有沒有刀。
  ///
  /// 機械狼不與小狼相認，自己不知道小狼死光了沒，所以每晚都要給這個手勢。
  mechanicKnifeGesture,

  /// 機械狼帶刀時的刀口。
  mechanicKnife,

  /// 機械狼帶刀且學到狼人時，多出來的第二刀。
  ///
  /// 與第一刀分成兩個子階段，才選得到「兩刀集中同一人」（破盾）。
  secondKnife,

  /// 女巫：是否對刀口下解藥。
  witchHeal,

  /// 女巫：是否毒人。
  witchPoison,

  /// 獵人：法官給「可否開槍」的手勢。
  hunterGesture,

  /// 走過場：這一步的角色已全部出局，但仍要照常喊一次再閉眼。
  ///
  /// 直接跳過會讓玩家從流程長度聽出誰死光了。
  passThrough,
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

  /// 目前正在指認第幾個特殊狼隊成員（[NightStep.specialPicks] 的索引）。
  int _specialIndex = 0;

  @override
  void initState() {
    super.initState();
    _isFirstNight = _state.dayNumber == 0;
    _state.dayNumber = _isFirstNight ? 1 : _state.dayNumber + 1;
    _state.phase = GamePhase.night;
    _steps = _isFirstNight
        ? NightFlow.firstNightSteps(_state.preset)
        : NightFlow.laterNightStepsFor(_state, night: _state.dayNumber);
    _actions = NightActions(night: _state.dayNumber);
    // 沒有步驟會被跳過 —— 角色全滅的步驟改走過場，見 [_isPassThrough]。
    _stepIndex = 0;
    _sub = _initialSubFor(_step);
  }

  NightStep get _step => _steps[_stepIndex];

  _Sub _initialSubFor(NightStep step) {
    if (_isPassThrough(step)) {
      // 機械狼學到狼人時，狼隊這一格就是牠的第二刀 ——
      // 第一刀在自己那一輪（夜晚開頭）已經砍過了。
      if (step.skill == NightSkill.wolfKill && _hasExtraKnife) {
        return _Sub.secondKnife;
      }
      return _Sub.passThrough;
    }
    if (_isFirstNight && step.seatCount > 0) return _Sub.registerSeats;
    // 機械狼學到女巫只拿得到毒藥，沒有解藥，所以直接跳到毒藥。
    if (step.skill == NightSkill.witchPotion) {
      return step.byMechanicWolf ? _Sub.witchPoison : _Sub.witchHeal;
    }
    if (step.skill == NightSkill.hunterGesture) return _Sub.hunterGesture;
    if (step.skill == NightSkill.mechanicReveal) return _Sub.mechanicReveal;
    // 機械狼那一輪永遠從開刀手勢開始。
    if (step.skill == NightSkill.mechanicTurn) return _Sub.mechanicKnifeGesture;
    return _Sub.chooseTarget;
  }

  /// 該步驟的角色是否全部出局。
  bool _allRolesDead(NightStep step) {
    for (final role in step.roles) {
      final alive = _state
          .seatsOfRole(role.id)
          .any((seat) => _state.playerAt(seat).alive);
      if (alive) return false;
    }
    return true;
  }

  /// 角色已全部出局，但仍要照常喊一次的步驟。
  ///
  /// **每個角色都適用。** 法官若因為某個身分死光就不喊它，玩家馬上就從
  /// 流程長度聽出誰出局了 —— 所以照喊不誤，只是沒有東西要收。
  bool _isPassThrough(NightStep step) => !_isFirstNight && _allRolesDead(step);

  /// 尚未登記身分的座次 —— 登記階段只能從這裡挑。
  Set<int> get _unassignedSeats => _state.players
      .where((p) => p.role == null)
      .map((p) => p.seat)
      .toSet();

  /// 目前要指認的特殊狼隊成員（狼王／狼美人）。
  Role get _specialRole => _step.specialPicks[_specialIndex];

  /// 這一步要喊的身分名稱。
  ///
  /// 用角色名而不是步驟標題 —— 標題可能是「機械狼（守衛）」，喊出來會露餡。
  String get _callName => _step.primaryRole?.nameZh ?? _step.title;


  int get _requiredPickCount => switch (_sub) {
        _Sub.registerSeats => _step.seatCount,
        _Sub.pickSpecial => 1,
        _Sub.hunterGesture ||
        _Sub.mechanicReveal ||
        _Sub.mechanicKnifeGesture ||
        _Sub.passThrough =>
          0,
        _ => 1,
      };

  /// 機械狼今晚是否多一刀 —— 要已經帶刀（小狼全滅）且學到狼人。
  bool get _hasExtraKnife => _state.mechanicHasExtraKnifeOn(_actions.night);

  /// 目前這一步實際要收的技能。
  ///
  /// 機械狼那一輪的 [NightStep.skill] 固定是 [NightSkill.mechanicTurn]，
  /// 真正要收的技能記在 [NightStep.mechanicSubSkill]。
  NightSkill get _effectiveSkill => _step.skill == NightSkill.mechanicTurn
      ? _step.mechanicSubSkill
      : _step.skill;

  /// 開刀手勢給完後，接著進入技能那一段。
  void _goToMechanicSkill() {
    switch (_step.mechanicSubSkill) {
      case NightSkill.none:
        _advanceStep();
      case NightSkill.witchPotion:
        // 機械狼學到女巫只有毒藥，沒有解藥。
        _sub = _Sub.witchPoison;
      default:
        _sub = _Sub.chooseTarget;
    }
  }

  bool get _canProceed {
    switch (_sub) {
      case _Sub.registerSeats:
      case _Sub.pickSpecial:
        return _picked.length == _requiredPickCount;
      case _Sub.chooseTarget:
      case _Sub.mechanicKnife:
      case _Sub.secondKnife:
      case _Sub.witchHeal:
      case _Sub.witchPoison:
        // 技能目標可以放棄（空刀、不用藥），因此不強制選取。
        return true;
      case _Sub.hunterGesture:
      case _Sub.mechanicReveal:
      case _Sub.mechanicKnifeGesture:
      case _Sub.passThrough:
        // 只是告知、確認手勢或走過場，沒有要選的東西。
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
          if (_step.needsSpecialPick) {
            _specialIndex = 0;
            _sub = _Sub.pickSpecial;
          } else {
            _afterRegistration();
          }

        case _Sub.pickSpecial:
          _state.playerAt(_picked.first).role = _specialRole;
          _picked.clear();
          if (_specialIndex + 1 < _step.specialPicks.length) {
            _specialIndex++;
          } else {
            _afterRegistration();
          }

        case _Sub.chooseTarget:
          _commitTarget();
          _picked.clear();
          _advanceStep();

        case _Sub.mechanicKnifeGesture:
          // 手勢給完：有刀就問刀口，沒刀就直接進技能那一段。
          if (_state.mechanicWolfCarriesKnife) {
            _sub = _Sub.mechanicKnife;
          } else {
            _goToMechanicSkill();
          }

        case _Sub.mechanicKnife:
          // 第一刀。第二刀（學到狼人時）留到狼隊那一格再收。
          _actions.wolfTarget = _picked.isEmpty ? null : _picked.first;
          _picked.clear();
          _goToMechanicSkill();

        case _Sub.secondKnife:
          _actions.wolfSecondTarget = _picked.isEmpty ? null : _picked.first;
          _picked.clear();
          _advanceStep();

        case _Sub.mechanicReveal:
          // 只是告知結果，沒有要記錄的行動。
          _advanceStep();

        case _Sub.passThrough:
          // 走過場，沒有要記錄的行動。
          _advanceStep();

        case _Sub.witchHeal:
          // 只有女巫本人有解藥（機械狼學到女巫不會走到這個子階段）。
          _actions.witchHealTarget = _picked.isEmpty ? null : _picked.first;
          _picked.clear();
          _sub = _Sub.witchPoison;

        case _Sub.witchPoison:
          final poison = _picked.isEmpty ? null : _picked.first;
          if (_step.byMechanicWolf) {
            _actions.mechanicPoisonTarget = poison;
          } else {
            _actions.witchPoisonTarget = poison;
          }
          _picked.clear();
          _advanceStep();

        case _Sub.hunterGesture:
          // 只是確認手勢，沒有要記錄的行動。
          _advanceStep();
      }
    });
  }

  /// 登記（與特殊成員指認）完成後，接著進入本步驟的技能子階段。
  void _afterRegistration() {
    switch (_step.skill) {
      case NightSkill.none:
        _advanceStep();
      case NightSkill.witchPotion:
        _sub = _step.byMechanicWolf ? _Sub.witchPoison : _Sub.witchHeal;
      case NightSkill.hunterGesture:
        _sub = _Sub.hunterGesture;
      case NightSkill.mechanicReveal:
        _sub = _Sub.mechanicReveal;
      case NightSkill.mechanicTurn:
        _sub = _Sub.mechanicKnifeGesture;
      default:
        _sub = _Sub.chooseTarget;
    }
  }

  /// 把登記的座次寫成身分。狼隊先全部記為一般狼，稍後再挑出狼王／狼美人。
  void _commitSeatRegistration() {
    final role = _step.roles.first;
    for (final seat in _picked) {
      _state.playerAt(seat).role = role;
    }
  }

  void _commitTarget() {
    final target = _picked.isEmpty ? null : _picked.first;
    // 機械狼用學來的技能時，目標記在牠自己的欄位 —— 與原角色各自獨立，
    // 否則兩人守同一晚會互相覆蓋。
    final byMechanic = _step.byMechanicWolf;
    switch (_effectiveSkill) {
      case NightSkill.guardProtect:
        if (byMechanic) {
          _actions.mechanicGuardTarget = target;
        } else {
          _actions.guardTarget = target;
        }
      case NightSkill.wolfKill:
        _actions.wolfTarget = target;
      case NightSkill.seerInspect:
      case NightSkill.psychicInspect:
        if (byMechanic) {
          _actions.mechanicInspectTarget = target;
        } else if (_effectiveSkill == NightSkill.psychicInspect) {
          _actions.psychicTarget = target;
        } else {
          _actions.seerTarget = target;
        }
      case NightSkill.charm:
        if (byMechanic) {
          _actions.mechanicCharmTarget = target;
        } else {
          _actions.wolfBeautyCharmTarget = target;
        }
      case NightSkill.mechanicLearn:
        _actions.mechanicWolfLearnTarget = target;
      case NightSkill.witchPotion:
      case NightSkill.hunterGesture:
      case NightSkill.mechanicReveal:
      case NightSkill.mechanicTurn:
      case NightSkill.none:
        break;
    }
  }

  void _advanceStep() {
    final next = _stepIndex + 1;
    if (next >= _steps.length) {
      _finish();
      return;
    }
    _stepIndex = next;
    _specialIndex = 0;
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

  /// 手勢卡的對象 —— 獵人本人，或學到槍牌的機械狼。
  ///
  /// 兩者的開槍條件不同（機械狼只有吃刀／吃推能開），所以不能共用獵人的判斷。
  bool get _gestureForMechanic => _step.byMechanicWolf;

  int? get _gestureSeat => _gestureForMechanic
      ? _state.seatOfRole(Roles.mechanicWolf.id)
      : _state.seatOfRole(Roles.hunter.id);

  bool get _gestureCanShoot => _gestureForMechanic
      ? _arbitrator.mechanicCanShootTonight(_state, _actions)
      : _hunterCanShoot;

  /// 機械狼目前的身分（含本夜剛學到、還沒套用的）。
  Role? get _mechanicLearnedRoleNow =>
      _arbitrator.mechanicLearnedRoleNow(_state, _actions);

  String get _gestureOwnerLabel => _gestureForMechanic
      ? '機械狼（已學到${_state.mechanicWolfLearnedRole?.nameZh ?? "槍牌"}）'
      : '獵人';

  String get _title => switch (_sub) {
        _Sub.registerSeats => '${_step.title}請睜眼',
        _Sub.pickSpecial => '哪一位是${_specialRole.nameZh}？',
        _Sub.witchHeal => '${_step.title}：要用解藥嗎？',
        _Sub.witchPoison => '${_step.title}：要用毒藥嗎？',
        _Sub.hunterGesture => '${_step.title}請睜眼',
        _Sub.mechanicReveal => '機械狼請睜眼',
        _Sub.mechanicKnifeGesture => '機械狼請睜眼',
        _Sub.passThrough => '$_callName請睜眼',
        _Sub.mechanicKnife =>
          _hasExtraKnife ? '機械狼第一刀要砍誰？' : '機械狼要刀誰？',
        _Sub.secondKnife => '機械狼第二刀要砍誰？',
        _Sub.chooseTarget => switch (_effectiveSkill) {
            NightSkill.guardProtect => '${_step.title}要守誰？',
            NightSkill.wolfKill => '${_step.title}要刀誰？',
            NightSkill.seerInspect => '${_step.title}要查驗誰？',
            NightSkill.psychicInspect => '${_step.title}要查驗誰的身分？',
            NightSkill.charm => '${_step.title}要魅惑誰？',
            NightSkill.mechanicLearn => '機械狼要學習誰的技能？',
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
        _Sub.pickSpecial => _specialRole.id == Roles.wolfKing.id
            ? '狼王出局時可以開槍帶人，需要單獨記錄'
            : '狼美人出局時被魅惑者會殉情，需要單獨記錄',
        _Sub.witchHeal => _witchHealHint,
        _Sub.witchPoison => _poisonAvailable
            ? '不使用請直接按下一步'
            : '毒藥已在之前的夜晚用掉了',
        _Sub.mechanicReveal => '法官依下面的內容比給機械狼看',
        _Sub.mechanicKnifeGesture => '機械狼不知道小狼死光了沒，'
            '每晚都要由法官比手勢告知今晚有沒有刀',
        _Sub.passThrough => '照常喊完再讓他們閉眼，不要跳過',
        _Sub.mechanicKnife => '空刀請直接按下一步',
        _Sub.secondKnife => '機械狼已學到狼人，這晚多一刀。'
            '${_actions.wolfTarget == null ? "第一刀空刀。" : "第一刀砍了 ${_actions.wolfTarget} 號，"}'
            '砍同一人可破盾（守衛與解藥都擋不住），不砍請直接按下一步',
        _Sub.chooseTarget => switch (_effectiveSkill) {
            NightSkill.wolfKill => '空刀請直接按下一步',
            NightSkill.guardProtect => _guardHint,
            NightSkill.charm => _charmHint,
            NightSkill.psychicInspect => '通靈師看到的是真實身分，不只好人／狼人',
            NightSkill.mechanicLearn =>
              '整局只能學一次，隔夜起才生效。不學請直接按下一步',
            _ => '',
          },
      };

  /// 機械狼學到守衛時，守護紀錄與原守衛各自獨立，提示要跟著換。
  int? get _lastGuardOfActor => _step.byMechanicWolf
      ? _state.lastMechanicGuardTarget
      : _state.lastGuardTarget;

  String get _guardHint {
    final last = _lastGuardOfActor;
    if (last != null && _state.preset.rules.guardCannotRepeatTarget) {
      return '不可連續兩晚守同一人（昨晚守了 $last 號）';
    }
    return '不守請直接按下一步';
  }

  int? get _lastCharmOfActor => _step.byMechanicWolf
      ? _state.lastMechanicCharmTarget
      : _state.lastCharmTarget;

  String get _charmHint {
    final last = _lastCharmOfActor;
    if (last != null && _state.preset.rules.charmCannotRepeatTarget) {
      return '不可連續兩晚魅惑同一人（昨晚魅惑了 $last 號）';
    }
    return '不魅惑請直接按下一步';
  }

  /// 解藥只有女巫那一瓶 —— 機械狼學到女巫也拿不到解藥。
  bool get _antidoteAvailable => _state.witchAntidoteAvailable;

  bool get _poisonAvailable => _step.byMechanicWolf
      ? _state.mechanicPoisonAvailable
      : _state.witchPoisonAvailable;

  /// 同夜雙藥的限制只對女巫本人成立（機械狼沒有解藥，不可能雙藥）。
  int? get _healTargetOfActor =>
      _step.byMechanicWolf ? null : _actions.witchHealTarget;

  /// 解藥持有者的座次 —— 只有女巫，用來判斷是不是自救。
  int? get _potionOwnerSeat => _state.seatOfRole(Roles.witch.id);

  String get _witchHealHint {
    if (!_antidoteAvailable) return '解藥已在之前的夜晚用掉了';
    final knives = _actions.wolfTargets.toSet().toList()..sort();
    if (knives.isEmpty) return '今晚沒有人被刀';

    final selfSeat = _potionOwnerSeat;
    final maySelfHeal = _state.preset.rules.witchMaySelfHeal(_actions.night);
    if (knives.length == 1 && knives.first == selfSeat && !maySelfHeal) {
      return '今晚 ${knives.first} 號被刀，但那是女巫自己，本局規則不可自救';
    }

    final list = knives.join('、');
    if (knives.length > 1) {
      return '今晚 $list 號被刀（雙刀）。解藥只有一瓶，最多救一位';
    }
    return '今晚 $list 號被刀。要救請點選，不救請直接按下一步';
  }

  /// 登記階段只能挑未指定身分的座次；技能階段可挑存活座次。
  Set<int>? get _selectableSeats {
    switch (_sub) {
      case _Sub.hunterGesture:
        return const {};
      case _Sub.registerSeats:
        return _unassignedSeats;
      case _Sub.pickSpecial:
        // 只能從剛登記的狼隊成員裡挑（尚未被指認為其他特殊身分的）。
        return _state.seatsOfRole(Roles.wolf.id).toSet();
      case _Sub.mechanicKnifeGesture:
      case _Sub.mechanicReveal:
      case _Sub.passThrough:
        return const {};
      case _Sub.mechanicKnife:
      case _Sub.secondKnife:
        // 第二刀可以砍同一人（破盾），所以不排除第一刀的目標。
        return _state.alivePlayers.map((p) => p.seat).toSet();
      case _Sub.witchHeal:
        if (!_antidoteAvailable) return const {};
        // 解藥只能救今晚的刀口（雙刀時兩個刀口都可救，但只救得了一個）。
        final knives = _actions.wolfTargets.toSet();
        if (knives.isEmpty) return const {};
        final selfSeat = _potionOwnerSeat;
        if (selfSeat != null &&
            !_state.preset.rules.witchMaySelfHeal(_actions.night)) {
          knives.remove(selfSeat);
        }
        return knives;
      case _Sub.witchPoison:
        if (!_poisonAvailable) return const {};
        if (!_state.preset.rules.witchDualUseSameNight &&
            _healTargetOfActor != null) {
          return const {};
        }
        return null;
      case _Sub.chooseTarget:
        if (_effectiveSkill == NightSkill.guardProtect) {
          final all = _state.alivePlayers.map((p) => p.seat).toSet();
          final last = _lastGuardOfActor;
          if (last != null && _state.preset.rules.guardCannotRepeatTarget) {
            all.remove(last);
          }
          return all;
        }
        if (_effectiveSkill == NightSkill.charm) {
          final all = _state.alivePlayers.map((p) => p.seat).toSet();
          final last = _lastCharmOfActor;
          if (last != null && _state.preset.rules.charmCannotRepeatTarget) {
            all.remove(last);
          }
          return all;
        }
        if (_effectiveSkill == NightSkill.mechanicLearn) {
          // 學習對象是別人 —— 學自己沒有意義。
          final all = _state.alivePlayers.map((p) => p.seat).toSet();
          final self = _state.seatOfRole(Roles.mechanicWolf.id);
          if (self != null) all.remove(self);
          return all;
        }
        if (_effectiveSkill == NightSkill.wolfKill &&
            _state.preset.rules.wolfBeautyCannotSelfKill) {
          // 狼美人不能自刀。
          final all = _state.alivePlayers.map((p) => p.seat).toSet();
          final beauty = _state.seatOfRole(Roles.wolfBeauty.id);
          if (beauty != null) all.remove(beauty);
          return all;
        }
        return null;
    }
  }

  Map<int, String>? get _disabledReasons {
    if (_sub == _Sub.chooseTarget &&
        _effectiveSkill == NightSkill.guardProtect &&
        _lastGuardOfActor != null &&
        _state.preset.rules.guardCannotRepeatTarget) {
      return {_lastGuardOfActor!: '昨晚已守'};
    }
    if (_sub == _Sub.chooseTarget &&
        _effectiveSkill == NightSkill.charm &&
        _lastCharmOfActor != null &&
        _state.preset.rules.charmCannotRepeatTarget) {
      return {_lastCharmOfActor!: '昨晚已魅惑'};
    }
    if (_sub == _Sub.chooseTarget &&
        _effectiveSkill == NightSkill.wolfKill &&
        _state.preset.rules.wolfBeautyCannotSelfKill) {
      final beauty = _state.seatOfRole(Roles.wolfBeauty.id);
      if (beauty != null) return {beauty: '狼美人不能自刀'};
    }
    if (_sub == _Sub.chooseTarget &&
        _effectiveSkill == NightSkill.mechanicLearn) {
      final self = _state.seatOfRole(Roles.mechanicWolf.id);
      if (self != null) return {self: '不能學自己'};
    }
    if (_sub == _Sub.witchPoison &&
        !_state.preset.rules.witchDualUseSameNight &&
        _healTargetOfActor != null) {
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
              child: _sub == _Sub.passThrough
                  ? _PassThroughCard(name: _callName)
                  : _sub == _Sub.mechanicKnifeGesture
                  ? _MechanicKnifeGestureCard(
                      seat: _state.seatOfRole(Roles.mechanicWolf.id),
                      hasKnife: _state.mechanicWolfCarriesKnife,
                      extraKnife: _hasExtraKnife,
                    )
                  : _sub == _Sub.mechanicReveal
                  ? _MechanicRevealCard(
                      seat: _state.seatOfRole(Roles.mechanicWolf.id),
                      learnedRole: _mechanicLearnedRoleNow,
                      learnedTonight: _state.mechanicWolfLearnedRole == null &&
                          _actions.mechanicWolfLearnTarget != null,
                      canShoot:
                          _arbitrator.mechanicCanShootTonight(_state, _actions),
                    )
                  : _sub == _Sub.hunterGesture
                  ? _HunterGestureCard(
                      ownerLabel: _gestureOwnerLabel,
                      seat: _gestureSeat,
                      canShoot: _gestureCanShoot,
                      poisonedTonight: _gestureSeat != null &&
                          (_actions.witchPoisonTarget == _gestureSeat ||
                              _actions.mechanicPoisonTarget == _gestureSeat),
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
        _Sub.pickSpecial => '請指定${_specialRole.nameZh}',
        _ => '下一步',
      };
}

/// 走過場卡：角色已全滅，但這一步照喊不誤。
///
/// 法官如果因為狼死光就不喊「狼人請睜眼」，玩家馬上從流程長度聽出來 ——
/// 所以這張卡的重點是提醒法官**照常喊、照常停頓**，不要露餡。
class _PassThroughCard extends StatelessWidget {
  const _PassThroughCard({required this.name});

  /// 要喊的身分名稱（不含「（守衛）」這類後綴）。
  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.volume_up_rounded,
                size: 56,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                '照常喊「$name請睜眼」',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '$name已全數出局，沒有人會睜眼 —— 但還是要照常喊、照常停頓幾秒'
                '再喊閉眼。跳過的話，玩家從流程長度就聽得出來。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 機械狼的開刀手勢卡。
///
/// 機械狼不與小狼相認，自己不知道小狼是不是死光了 —— 有沒有刀只有法官知道，
/// 所以每晚都要比這個手勢。做成一眼可辨的大卡片，現場光線差、動作要快。
class _MechanicKnifeGestureCard extends StatelessWidget {
  const _MechanicKnifeGestureCard({
    required this.seat,
    required this.hasKnife,
    required this.extraKnife,
  });

  final int? seat;

  /// 今晚有沒有刀（其餘小狼是否已全數出局）。
  final bool hasKnife;

  /// 有刀且學到狼人時，這晚可以砍兩刀。
  final bool extraKnife;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = hasKnife ? WgmTheme.wolfColor : scheme.onSurfaceVariant;

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
                    hasKnife
                        ? Icons.thumb_up_rounded
                        : Icons.thumb_down_rounded,
                    size: 72,
                    color: color,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    hasKnife ? '拇指向上' : '拇指向下',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasKnife
                        ? (extraKnife ? '今晚有刀，可以砍兩刀' : '今晚有刀')
                        : '今晚沒有刀',
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
              _ when seat == null => '此局沒有機械狼',
              _ when !hasKnife => '還有小狼存活，機械狼（$seat 號）今晚沒有刀。'
                  '要等其餘小狼全數出局才開得了刀。',
              _ when extraKnife => '小狼已全數出局，機械狼（$seat 號）獨自帶刀；'
                  '牠學到狼人，這晚可以砍兩刀 —— 第二刀留到「狼人請睜眼」那一步再問。',
              _ => '小狼已全數出局，機械狼（$seat 號）獨自帶刀。',
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

/// 機械狼的夜晚結尾告知卡。
///
/// 機械狼是第一個睜眼的，那時候身分都還沒登記完、女巫的毒也還沒收 ——
/// 所以「學到什麼」和「能不能開槍」都得等到夜晚結尾才告知得了。
class _MechanicRevealCard extends StatelessWidget {
  const _MechanicRevealCard({
    required this.seat,
    required this.learnedRole,
    required this.learnedTonight,
    required this.canShoot,
  });

  final int? seat;

  /// 機械狼目前的身分；null 表示還沒學過。
  final Role? learnedRole;

  /// 是不是本夜剛學到的（本夜才要告知身分；之前學的只是每晚給手勢）。
  final bool learnedTonight;

  /// 學到槍牌時，今晚出局能不能開槍。
  final bool canShoot;

  bool get _hasGun =>
      learnedRole != null && Roles.gunRoleIds.contains(learnedRole!.id);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    learnedTonight ? '今晚學到的身分' : '目前持有的身分',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    learnedRole?.nameZh ?? '今晚沒有學習',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    switch (true) {
                      _ when learnedRole == null =>
                        '機械狼沒有指定學習對象，之後的夜晚仍可再學。',
                      _ when learnedTonight =>
                        '請比給 $seat 號機械狼看。技能自**下一夜**起生效，整局只能學這一次。',
                      _ => '之前的夜晚已經學到，這裡只是再確認一次。',
                    },
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_hasGun) ...[
            const SizedBox(height: 12),
            _HunterGestureCard(
              ownerLabel: '機械狼（已學到${learnedRole!.nameZh}）',
              seat: seat,
              canShoot: canShoot,
              poisonedTonight: !canShoot,
            ),
          ],
        ],
      ),
    );
  }
}

/// 獵人開槍手勢卡。
///
/// 法官每晚都要叫獵人起來，用手勢告知技能是否可用。做成一眼可辨的大卡片，
/// 因為現場光線差、動作要快，法官不該還要自己推「被毒了所以不能開槍」。
class _HunterGestureCard extends StatelessWidget {
  const _HunterGestureCard({
    required this.ownerLabel,
    required this.seat,
    required this.canShoot,
    required this.poisonedTonight,
  });

  /// 這張手勢卡是給誰的：「獵人」或「機械狼（已學到獵人）」。
  final String ownerLabel;

  final int? seat;
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
              _ when seat == null => '此局沒有$ownerLabel',
              _ when poisonedTonight => '$ownerLabel（$seat 號）今晚被毒，'
                  '依規則不可開槍',
              _ when canShoot => '$ownerLabel為 $seat 號，技能正常',
              _ => '$ownerLabel（$seat 號）目前無法開槍',
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
