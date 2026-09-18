import '../models/game_state.dart';
import '../models/night_action.dart';
import '../models/role.dart';
import 'night_arbitrator.dart';
import 'night_flow.dart';
import 'undo_stack.dart';

/// 一個步驟內的子階段。
enum NightSub {
  /// 登記座次：「守衛請睜眼，你是幾號」。
  registerSeats,

  /// 狼隊登記完後指認特殊成員（狼王、狼美人）。
  pickSpecial,

  /// 選擇技能目標。
  chooseTarget,

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

  /// 女巫：解藥與毒藥在**同一畫面**收。
  ///
  /// 刀口寫在中間，解藥與毒藥並列在下方 —— 法官一眼看完再決定，
  /// 不必按兩次「下一步」摸黑往前走。
  witchPotion,

  /// 獵人：法官給「可否開槍」的手勢。
  hunterGesture,

  /// 夜晚結尾：法官告知機械狼學到的身分，並給開槍手勢。
  mechanicReveal,

  /// 走過場：這一步的角色已全部出局，但仍要照常喊一次再閉眼。
  ///
  /// 直接跳過會讓玩家從流程長度聽出誰死光了。
  passThrough,
}

/// 座次不可選的原因。
///
/// 只回傳原因本身，顯示文字由 UI 決定 —— 引擎不碰呈現。
enum SeatBlockReason {
  /// 守衛昨晚守過這位（不可連守同一人）。
  guardedLastNight,

  /// 狼美人昨晚魅惑過這位（不可連續兩晚魅惑同一人）。
  charmedLastNight,

  /// 狼美人不能被自刀。
  wolfBeautySelfKill,

  /// 機械狼不能學自己。
  mechanicSelfLearn,

  /// 本局不可同夜雙藥。
  witchDualUse,
}

/// 夜晚流程走到哪裡 —— 撤銷時要連這個一起還原。
///
/// 只還原 [GameState] 不夠：局面回去了，但流程還停在後面一步，
/// 已經收到的行動意圖也還在，法官會看到對不上的畫面。
class NightCursor {
  const NightCursor({
    required this.stepIndex,
    required this.sub,
    required this.specialIndex,
    required this.picked,
    required this.actions,
  });

  final int stepIndex;
  final NightSub sub;
  final int specialIndex;
  final Set<int> picked;
  final NightActions actions;
}

/// 夜晚流程狀態機。
///
/// 純 Dart，不依賴 Flutter —— 「哪一步之後接哪一步」是**規則**不是排版，
/// 規則就該能用單元測試涵蓋。UI 只負責把 [title] 之類的狀態畫出來，
/// 並把使用者操作轉成 [toggleSeat] 與 [next]。
///
/// 狀態機會就地修改 [state]（登記身分、結算套用），呼叫端負責在建立之前
/// 存好撤銷快照。
class NightFlowMachine {
  NightFlowMachine({
    required this.state,
    required this.night,
    required this.isFirstNight,
  })  : steps = isFirstNight
            ? NightFlow.firstNightSteps(state.preset)
            : NightFlow.laterNightStepsFor(state, night: night),
        actions = NightActions(night: night) {
    _sub = _initialSubFor(step);
  }

  static const _arbitrator = NightArbitrator();

  final GameState state;

  /// 第幾夜，首夜為 1。
  final int night;

  final bool isFirstNight;

  /// 本夜的所有步驟。角色全滅的步驟不會被移除，改走過場。
  final List<NightStep> steps;

  /// 本夜收集到的行動意圖。撤銷時整份換回快照，所以不是 final。
  NightActions actions;

  /// 撤銷堆疊。每按一次「下一步」存一筆，顆粒度到單一夜晚行動。
  final UndoStack undoStack = UndoStack();

  int _stepIndex = 0;
  late NightSub _sub;
  int _specialIndex = 0;
  final Set<int> _picked = {};

  /// 結算結果；[finished] 為 true 之前是 null。
  NightOutcome? outcome;

  /// 首夜自動填為平民的座次。
  List<int> autoFilledVillagers = const [];

  /// 是否已走完全部步驟並完成結算。
  bool get finished => outcome != null;

  int get stepIndex => _stepIndex;
  NightSub get sub => _sub;
  Set<int> get picked => _picked;

  NightStep get step => steps[_stepIndex];

  /// 目前要指認的特殊狼隊成員（狼王／狼美人）。
  Role get specialRole => step.specialPicks[_specialIndex];

  /// 這一步要喊的身分名稱。
  ///
  /// 用角色名而不是步驟標題 —— 標題可能是「機械狼（守衛）」，喊出來會露餡。
  String get callName => step.primaryRole?.nameZh ?? step.title;

  /// 目前這一步實際要收的技能。
  ///
  /// 機械狼那一輪的 [NightStep.skill] 固定是 [NightSkill.mechanicTurn]，
  /// 真正要收的技能記在 [NightStep.mechanicSubSkill]。
  NightSkill get effectiveSkill => step.skill == NightSkill.mechanicTurn
      ? step.mechanicSubSkill
      : step.skill;

  /// 機械狼今晚是否多一刀 —— 要已經帶刀（小狼全滅）且學到狼人。
  bool get hasExtraKnife => state.mechanicHasExtraKnifeOn(night);

  // ---- 步驟性質 ----

  /// 該步驟的角色是否全部出局。
  bool allRolesDead(NightStep s) {
    for (final role in s.roles) {
      final alive =
          state.seatsOfRole(role.id).any((seat) => state.playerAt(seat).alive);
      if (alive) return false;
    }
    return true;
  }

  /// 角色已全部出局，但仍要照常喊一次的步驟。
  ///
  /// **每個角色都適用。** 法官若因為某個身分死光就不喊它，玩家馬上就從
  /// 流程長度聽出誰出局了 —— 所以照喊不誤，只是沒有東西要收。
  bool isPassThrough(NightStep s) => !isFirstNight && allRolesDead(s);

  NightSub _initialSubFor(NightStep s) {
    if (isPassThrough(s)) {
      // 機械狼學到狼人時，狼隊這一格就是牠的第二刀 ——
      // 第一刀在自己那一輪（夜晚開頭）已經砍過了。
      if (s.skill == NightSkill.wolfKill && hasExtraKnife) {
        return NightSub.secondKnife;
      }
      return NightSub.passThrough;
    }
    if (isFirstNight && s.seatCount > 0) return NightSub.registerSeats;
    return _skillSubFor(s);
  }

  /// 登記完成後（或本來就不用登記時），該步驟要進入的技能子階段。
  NightSub _skillSubFor(NightStep s) => switch (s.skill) {
        NightSkill.witchPotion => NightSub.witchPotion,
        NightSkill.hunterGesture => NightSub.hunterGesture,
        NightSkill.mechanicReveal => NightSub.mechanicReveal,
        // 機械狼那一輪永遠從開刀手勢開始。
        NightSkill.mechanicTurn => NightSub.mechanicKnifeGesture,
        _ => NightSub.chooseTarget,
      };

  // ---- 選取 ----

  /// 尚未登記身分的座次 —— 登記階段只能從這裡挑。
  Set<int> get _unassignedSeats =>
      state.players.where((p) => p.role == null).map((p) => p.seat).toSet();

  Set<int> get _aliveSeats =>
      state.alivePlayers.map((p) => p.seat).toSet();

  int get requiredPickCount => switch (_sub) {
        NightSub.registerSeats => step.seatCount,
        NightSub.pickSpecial => 1,
        NightSub.hunterGesture ||
        NightSub.mechanicReveal ||
        NightSub.mechanicKnifeGesture ||
        NightSub.passThrough =>
          0,
        // 女巫那一頁選的是毒藥目標；解藥另外用按鈕挑。
        _ => 1,
      };

  // ---- 女巫那一頁 ----

  /// 今晚的刀口，排序後去重。空的表示平安夜（或還沒收到狼刀）。
  List<int> get knifedSeats => actions.wolfTargets.toSet().toList()..sort();

  /// 解藥救得到的座次 —— 只有今晚的刀口，且受自救規則限制。
  ///
  /// 機械狼學到女巫**只拿得到毒藥**，所以牠那一頁永遠是空的。
  List<int> get healableSeats {
    if (step.byMechanicWolf) return const [];
    if (!antidoteAvailable) return const [];
    // 本局不可同夜雙藥時，已經選了毒藥目標就不能再用解藥。
    if (!state.preset.rules.witchDualUseSameNight && _picked.isNotEmpty) {
      return const [];
    }
    final seats = knifedSeats;
    final self = potionOwnerSeat;
    if (self != null && !state.preset.rules.witchMaySelfHeal(actions.night)) {
      return seats.where((s) => s != self).toList();
    }
    return seats;
  }

  /// 目前選定要用解藥救的座次；null 表示不用解藥。
  int? get healTarget => actions.witchHealTarget;

  /// 毒藥現在能不能用 —— 沒藥了、或本局不可同夜雙藥而已經下了解藥，就不能。
  bool get poisonUsable {
    if (!poisonAvailable) return false;
    if (!state.preset.rules.witchDualUseSameNight && healTarget != null) {
      return false;
    }
    return true;
  }

  /// 點解藥按鈕：對 [seat] 下解藥；再點一次取消。
  ///
  /// 不在 [healableSeats] 裡就沒有作用（規則守在引擎，不只靠 UI 擋）。
  void toggleHeal(int seat) {
    if (actions.witchHealTarget == seat) {
      actions.witchHealTarget = null;
      return;
    }
    if (!healableSeats.contains(seat)) return;
    actions.witchHealTarget = seat;
    // 不可同夜雙藥時，下了解藥就把已選的毒藥目標清掉。
    if (!state.preset.rules.witchDualUseSameNight) _picked.clear();
  }

  bool get canProceed {
    switch (_sub) {
      case NightSub.registerSeats:
      case NightSub.pickSpecial:
        return _picked.length == requiredPickCount;
      default:
        // 技能目標可以放棄（空刀、不用藥）；手勢與走過場沒有要選的東西。
        return true;
    }
  }

  /// 可選座次；null 表示所有存活座次都可選。
  Set<int>? get selectableSeats {
    switch (_sub) {
      case NightSub.hunterGesture:
      case NightSub.mechanicKnifeGesture:
      case NightSub.mechanicReveal:
      case NightSub.passThrough:
        return const {};
      case NightSub.registerSeats:
        return _unassignedSeats;
      case NightSub.pickSpecial:
        // 只能從剛登記的狼隊成員裡挑（尚未被指認為其他特殊身分的）。
        return state.seatsOfRole(Roles.wolf.id).toSet();
      case NightSub.mechanicKnife:
      case NightSub.secondKnife:
        // 第二刀可以砍同一人（破盾），所以不排除第一刀的目標。
        return _aliveSeats;
      case NightSub.witchPotion:
        // 這一頁的座位格選的是**毒藥**目標；解藥用下方的按鈕挑。
        return poisonUsable ? _aliveSeats : const {};
      case NightSub.chooseTarget:
        final blocked = blockedSeats;
        if (blocked == null) return null;
        return _aliveSeats.difference(blocked.keys.toSet());
    }
  }

  /// 不可選的座次與原因。null 表示沒有額外限制。
  Map<int, SeatBlockReason>? get blockedSeats {
    if (_sub == NightSub.witchPotion) {
      // 已經下了解藥、而本局不可同夜雙藥 → 毒藥整排都不能選。
      if (!poisonUsable && healTarget != null) {
        return {
          for (final p in state.players) p.seat: SeatBlockReason.witchDualUse,
        };
      }
      return null;
    }
    if (_sub != NightSub.chooseTarget) return null;

    switch (effectiveSkill) {
      case NightSkill.guardProtect:
        final last = lastGuardOfActor;
        if (last != null && state.preset.rules.guardCannotRepeatTarget) {
          return {last: SeatBlockReason.guardedLastNight};
        }
      case NightSkill.charm:
        final last = lastCharmOfActor;
        if (last != null && state.preset.rules.charmCannotRepeatTarget) {
          return {last: SeatBlockReason.charmedLastNight};
        }
      case NightSkill.wolfKill:
        if (state.preset.rules.wolfBeautyCannotSelfKill) {
          final beauty = state.seatOfRole(Roles.wolfBeauty.id);
          if (beauty != null) {
            return {beauty: SeatBlockReason.wolfBeautySelfKill};
          }
        }
      case NightSkill.mechanicLearn:
        // 學習對象是別人 —— 學自己沒有意義。
        final self = state.seatOfRole(Roles.mechanicWolf.id);
        if (self != null) return {self: SeatBlockReason.mechanicSelfLearn};
      default:
        return null;
    }
    return null;
  }

  // ---- 行動者相關（機械狼學到技能時與原角色各自獨立）----

  /// 機械狼學到守衛時，守護紀錄與原守衛各自獨立。
  int? get lastGuardOfActor => step.byMechanicWolf
      ? state.lastMechanicGuardTarget
      : state.lastGuardTarget;

  int? get lastCharmOfActor =>
      step.byMechanicWolf ? state.lastMechanicCharmTarget : state.lastCharmTarget;

  /// 解藥只有女巫那一瓶 —— 機械狼學到女巫也拿不到解藥。
  bool get antidoteAvailable => state.witchAntidoteAvailable;

  bool get poisonAvailable => step.byMechanicWolf
      ? state.mechanicPoisonAvailable
      : state.witchPoisonAvailable;

  /// 同夜雙藥的限制只對女巫本人成立（機械狼沒有解藥，不可能雙藥）。
  int? get healTargetOfActor =>
      step.byMechanicWolf ? null : actions.witchHealTarget;

  /// 解藥持有者的座次 —— 只有女巫，用來判斷是不是自救。
  int? get potionOwnerSeat => state.seatOfRole(Roles.witch.id);

  /// 機械狼目前的身分（含本夜剛學到、還沒套用的）。
  Role? get mechanicLearnedRoleNow =>
      _arbitrator.mechanicLearnedRoleNow(state, actions);

  /// 獵人今晚若出局能不能開槍 —— 法官給手勢用。
  bool get hunterCanShootTonight =>
      _arbitrator.hunterCanShootTonight(state, actions);

  /// 機械狼（學到槍牌）今晚若出局能不能開槍。
  bool get mechanicCanShootTonight =>
      _arbitrator.mechanicCanShootTonight(state, actions);

  // ---- 操作 ----

  /// [seat] 這一步能不能選。
  ///
  /// 規則要守在引擎裡 —— UI 的座位格雖然也會擋，但不能只靠它，
  /// 否則換一個呼叫端（模擬、匯入存檔）就繞過去了。
  bool canPick(int seat) {
    if (requiredPickCount == 0) return false;
    // 登記階段挑的是還沒指定身分的座次，死活無關。
    if (_sub != NightSub.registerSeats && !state.playerAt(seat).alive) {
      return false;
    }
    final allow = selectableSeats;
    return allow == null || allow.contains(seat);
  }

  void toggleSeat(int seat) {
    if (_picked.contains(seat)) {
      _picked.remove(seat);
      return;
    }
    if (!canPick(seat)) return;
    if (requiredPickCount == 1) {
      _picked
        ..clear()
        ..add(seat);
    } else if (_picked.length < requiredPickCount) {
      _picked.add(seat);
    }
  }

  // ---- 撤銷 ----

  bool get canUndo => undoStack.canUndo;

  /// 上一步是哪個身分，顯示在撤銷按鈕上。
  String? get undoLabel => undoStack.topLabel;

  NightCursor get _cursor => NightCursor(
        stepIndex: _stepIndex,
        sub: _sub,
        specialIndex: _specialIndex,
        picked: {..._picked},
        actions: actions.copy(),
      );

  /// 退回上一次按「下一步」之前的狀態。沒有東西可撤時回傳 false。
  ///
  /// 局面與流程位置一起還原 —— 只還原其中一邊會讓畫面對不上。
  bool undo() {
    final snap = undoStack.undo();
    if (snap == null) return false;

    state.restoreFrom(snap.state);
    final cursor = snap.cursor! as NightCursor;
    _stepIndex = cursor.stepIndex;
    _sub = cursor.sub;
    _specialIndex = cursor.specialIndex;
    _picked
      ..clear()
      ..addAll(cursor.picked);
    actions = cursor.actions.copy();
    // 撤銷回夜晚中途，就不再是「已結算」的狀態。
    outcome = null;
    autoFilledVillagers = const [];
    return true;
  }

  /// 前進到下一個子階段或步驟；走完全部步驟時進行結算並設定 [outcome]。
  void next() {
    // 先存快照再動 —— 存的是「這一步發生之前」的局面。
    undoStack.push(state, step.title, cursor: _cursor);

    switch (_sub) {
      case NightSub.registerSeats:
        _commitSeatRegistration();
        _picked.clear();
        if (step.needsSpecialPick) {
          _specialIndex = 0;
          _sub = NightSub.pickSpecial;
        } else {
          _afterRegistration();
        }

      case NightSub.pickSpecial:
        state.playerAt(_picked.first).role = specialRole;
        _picked.clear();
        if (_specialIndex + 1 < step.specialPicks.length) {
          _specialIndex++;
        } else {
          _afterRegistration();
        }

      case NightSub.chooseTarget:
        _commitTarget();
        _picked.clear();
        _advanceStep();

      case NightSub.mechanicKnifeGesture:
        // 手勢給完：有刀就問刀口，沒刀就直接進技能那一段。
        if (state.mechanicWolfCarriesKnife) {
          _sub = NightSub.mechanicKnife;
        } else {
          _goToMechanicSkill();
        }

      case NightSub.mechanicKnife:
        // 第一刀。第二刀（學到狼人時）留到狼隊那一格再收。
        actions.wolfTarget = _picked.isEmpty ? null : _picked.first;
        _picked.clear();
        _goToMechanicSkill();

      case NightSub.secondKnife:
        actions.wolfSecondTarget = _picked.isEmpty ? null : _picked.first;
        _picked.clear();
        _advanceStep();

      case NightSub.witchPotion:
        // 解藥在 actions.witchHealTarget 裡（由 toggleHeal 設），
        // 這裡只要收座位格選的毒藥目標。
        final poison = _picked.isEmpty ? null : _picked.first;
        if (step.byMechanicWolf) {
          actions.mechanicPoisonTarget = poison;
        } else {
          actions.witchPoisonTarget = poison;
        }
        _picked.clear();
        _advanceStep();

      case NightSub.hunterGesture:
      case NightSub.mechanicReveal:
      case NightSub.passThrough:
        // 只是告知、確認手勢或走過場，沒有要記錄的行動。
        _advanceStep();
    }
  }

  /// 登記（與特殊成員指認）完成後，接著進入本步驟的技能子階段。
  ///
  /// 沒有夜間行動的角色（白痴、騎士）登記完就直接換下一步。
  void _afterRegistration() {
    if (step.skill == NightSkill.none) {
      _advanceStep();
    } else {
      _sub = _skillSubFor(step);
    }
  }

  /// 開刀手勢給完後，接著進入技能那一段。
  void _goToMechanicSkill() {
    switch (step.mechanicSubSkill) {
      case NightSkill.none:
        _advanceStep();
      case NightSkill.witchPotion:
        // 機械狼學到女巫只有毒藥，沒有解藥 —— 同一頁，但解藥那排是暗的。
        _sub = NightSub.witchPotion;
      default:
        _sub = NightSub.chooseTarget;
    }
  }

  /// 把登記的座次寫成身分。狼隊先全部記為一般狼，稍後再挑出狼王／狼美人。
  void _commitSeatRegistration() {
    final role = step.roles.first;
    for (final seat in _picked) {
      state.playerAt(seat).role = role;
    }
  }

  void _commitTarget() {
    final target = _picked.isEmpty ? null : _picked.first;
    // 機械狼用學來的技能時，目標記在牠自己的欄位 —— 與原角色各自獨立，
    // 否則兩人守同一晚會互相覆蓋。
    final byMechanic = step.byMechanicWolf;
    switch (effectiveSkill) {
      case NightSkill.guardProtect:
        if (byMechanic) {
          actions.mechanicGuardTarget = target;
        } else {
          actions.guardTarget = target;
        }
      case NightSkill.wolfKill:
        actions.wolfTarget = target;
      case NightSkill.seerInspect:
      case NightSkill.psychicInspect:
        if (byMechanic) {
          actions.mechanicInspectTarget = target;
        } else if (effectiveSkill == NightSkill.psychicInspect) {
          actions.psychicTarget = target;
        } else {
          actions.seerTarget = target;
        }
      case NightSkill.charm:
        if (byMechanic) {
          actions.mechanicCharmTarget = target;
        } else {
          actions.wolfBeautyCharmTarget = target;
        }
      case NightSkill.mechanicLearn:
        actions.mechanicWolfLearnTarget = target;
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
    if (next >= steps.length) {
      _finish();
      return;
    }
    _stepIndex = next;
    _specialIndex = 0;
    _sub = _initialSubFor(step);
  }

  void _finish() {
    // 走完所有特殊身分，剩下的座次就是平民。
    autoFilledVillagers =
        isFirstNight ? state.assignRemainingAsVillager() : const [];

    final settled = _arbitrator.settle(state, actions);
    _arbitrator.apply(state, actions, settled);
    outcome = settled;
  }
}
