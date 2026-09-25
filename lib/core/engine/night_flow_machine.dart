import '../models/game_state.dart';
import '../models/log_entry.dart';
import '../models/night_action.dart';
import '../models/role.dart';
import 'night_arbitrator.dart';
import 'night_flow.dart';
import 'seat_block_reason.dart';
import 'undo_stack.dart';

export 'seat_block_reason.dart';

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

  /// 熊：法官給「咆哮／不咆哮」—— 兩側鄰座裡有沒有狼。
  bearGrowl,

  /// 覺醒石像鬼轉換一位。**逐隻問過去**，一隻一次；兩隻的鄰座都能選。
  gargoyleConvert,

  /// 夜晚結尾：法官告知機械狼學到的身分，並給開槍手勢。
  mechanicReveal,

  /// 查驗結果：法官**當場**把金水／查殺（通靈師則是真實身分）比給查驗者看。
  ///
  /// 非有不可 —— 查驗者只有這一刻是睜著眼的。夜晚結算頁固然也會列出結果，
  /// 但那是整夜跑完之後的事，那時查驗者早就閉眼了，法官已經沒機會告知。
  /// 這一步之於預言家，等同 [hunterGesture] 之於獵人。
  inspectResult,

  /// 走過場：這一步的角色已全部出局，但仍要照常喊一次再閉眼。
  ///
  /// 直接跳過會讓玩家從流程長度聽出誰死光了。
  passThrough,

  /// 第二夜起，轉換者那一輪的第一段：法官比手勢告知今晚有沒有刀。
  ///
  /// 一格一位，叫滿石像鬼的數量。那一位已出局（或當初選到機械狼、轉換白費）
  /// 照樣喊、照樣停頓（見 [NightSkill.convertedTurn]）。
  convertedKnifeGesture,

  /// 有刀的轉換者選刀口。
  convertedKnife,

  /// 首夜最後：逐一叫醒被轉換者，告知他已轉換進狼隊。
  ///
  /// 叫的次數固定是石像鬼的數量（見 [NightSkill.convertedNotify]）。
  convertedNotify,
}

/// [NightSub.inspectResult] 那一頁的內容：法官要比給查驗者看的答案。
///
/// 只帶資料，不帶措辭 —— 「金水」「查殺」怎麼寫是 UI 的事。
class InspectReveal {
  const InspectReveal({
    required this.seat,
    required this.isPsychic,
    required this.role,
    required this.sawWolf,
    required this.byMechanicWolf,
  });

  /// 被查驗的座次。
  final int seat;

  /// 通靈師（看真實身分）還是預言家（只分好人／狼人）。
  final bool isPsychic;

  /// 查驗者**看到的**身分，不一定是真身 —— 機械狼學過之後看到的是
  /// 牠學到的身分（見 `NightArbitrator.apparentRoleAt`）。
  ///
  /// **尚未登記時為 null** —— 首夜邊問邊登記的用法下，排在查驗者
  /// 後面的角色這時還沒登記。
  final Role? role;

  /// 這次查驗是機械狼用學來的技能做的。
  final bool byMechanicWolf;

  /// 預言家的答案：查殺為 true，金水為 false。
  ///
  /// **不是從 [role] 推出來的** —— 被轉換者身上兩者會不一致：
  /// 預言家看到查殺，通靈師看到的卻是他原本的身分（例如女巫）。
  /// 所以由引擎分別算好再帶進來，見 `NightArbitrator.apparentCampAt`。
  ///
  /// 身分尚未登記時視為好人 —— 夜晚結算會把剩下的座次補成平民。
  final bool sawWolf;
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
    required this.gargoyleIndex,
    required this.picked,
    required this.actions,
  });

  final int stepIndex;
  final NightSub sub;
  final int specialIndex;
  final int gargoyleIndex;
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
    // 開頭若正好是沒事可做的步驟就先跳過（見 [_isNoOpStep]）。
    // 實務上第一步一定是狼隊或守衛，這個迴圈只是防呆。
    while (_stepIndex + 1 < steps.length && _isNoOpStep(steps[_stepIndex])) {
      _stepIndex++;
    }
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
  int _gargoyleIndex = 0;
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

  /// 這一步是被轉換者喪失原技能後的走過場 —— 人還活著、會睜眼，
  /// 與「角色全滅」的走過場說明不同，畫面要分開寫。
  bool get isLostSkillsStep =>
      !isFirstNight && step.skill == NightSkill.none && !allRolesDead(step);

  NightSub _initialSubFor(NightStep s) {
    // 轉換者那一輪沒有固定角色（roles 是空的），不能拿「角色全滅」判斷 ——
    // 每一格自己看有沒有人，見 [convertedTurnSeat]。
    if (s.skill == NightSkill.convertedTurn) {
      return NightSub.convertedKnifeGesture;
    }
    if (isPassThrough(s)) {
      // 機械狼學到狼人時，狼隊這一格就是牠的第二刀 ——
      // 第一刀在自己那一輪（夜晚開頭）已經砍過了。
      if (s.skill == NightSkill.wolfKill && hasExtraKnife) {
        return NightSub.secondKnife;
      }
      // 被轉換者接刀時（開刀順位第 3 順位），刀在他自己那一輪
      //（[NightSkill.convertedTurn]）開，狼隊這一格照樣走過場。
      return NightSub.passThrough;
    }
    if (isFirstNight && needsRegistration(s)) return NightSub.registerSeats;
    return _skillSubFor(s);
  }

  /// 首夜這一步還需不需要登記座次。
  ///
  /// 法官有兩種用法，兩種都要能跑：
  ///
  /// 1. **夜裡邊問邊登記** —— 登記頁只確認人數就開局，首夜依夜晚順序
  ///    「守衛請睜眼，你是幾號」逐一問出來。
  /// 2. **開局前就配好** —— 登記頁把 12 個身分全部指定好（`隨機發牌`
  ///    或手動點完）再進第一夜。這時身分**已經都在 [GameState] 裡了**，
  ///    沒有東西可登記。
  ///
  /// 第 2 種以前會整個卡死：這一步照樣進登記子階段，但可選座次取的是
  /// 「尚未登記身分的座次」＝空集合，[canProceed] 永遠是 false，
  /// 下一步鍵變灰，法官過不了第一夜。角色照樣要喊、技能照樣要收，
  /// **只是不必再問一次座次**。
  bool needsRegistration(NightStep s) {
    if (s.seatCount == 0) return false;
    final assigned = s.roles.fold<int>(
      0,
      (n, r) => n + state.seatsOfRole(r.id).length,
    );
    return assigned < s.seatCount;
  }

  static bool _isInspectSkill(NightSkill skill) =>
      skill == NightSkill.seerInspect || skill == NightSkill.psychicInspect;

  /// [NightSub.inspectResult] 這一頁要給法官看的東西。
  ///
  /// 不在這一頁時回傳 null。
  InspectReveal? get inspectReveal {
    if (_sub != NightSub.inspectResult) return null;
    final seat = _inspectedSeat;
    if (seat == null) return null;
    return InspectReveal(
      seat: seat,
      // 通靈師看到的是真實身分；預言家只分好人／狼人。
      isPsychic: effectiveSkill == NightSkill.psychicInspect,
      // 機械狼學過就顯示牠學到的身分（連本夜剛學的也算）——
      // 與結算共用 `NightArbitrator.apparentRoleAt`，兩邊不會給出不同答案。
      role: NightArbitrator.apparentRoleAt(
        state,
        seat,
        learnTargetTonight: actions.mechanicWolfLearnTarget,
      ),
      // 陣營另外算 —— 被轉換者的身分與陣營會給出不同答案。
      sawWolf: NightArbitrator.apparentCampAt(
            state,
            seat,
            learnTargetTonight: actions.mechanicWolfLearnTarget,
          ) ==
          Camp.wolf,
      byMechanicWolf: step.byMechanicWolf,
    );
  }

  /// 把熊今晚的咆哮記進復盤日誌。
  ///
  /// 咆哮不動局面，所以不經過結算器的 `_writeLog()` —— 但它是法官給出去的
  /// **情報**，事後對帳一定要看得到，所以在給完手勢的當下就寫。
  void _logBearGrowl() {
    final neighbours = bearNeighbors;
    if (neighbours.isEmpty) return;
    state.log.add(
      round: night,
      isNight: true,
      kind: LogKind.info,
      text: '${step.byMechanicWolf ? "機械狼（熊）" : "熊"}的鄰座是 '
          '${neighbours.join("、")} 號，'
          '${bearGrowls ? "咆哮（有狼）" : "不咆哮（沒有狼）"}',
      seats: neighbours,
    );
  }

  // ---- 覺醒石像鬼的轉換 ----

  /// 場上的覺醒石像鬼座次，依座號排序。
  List<int> get gargoyleSeats =>
      state.seatsOfRole(Roles.awakenedGargoyle.id)..sort();

  /// 目前輪到哪一隻石像鬼轉換；不在那一步時為 null。
  int? get currentGargoyleSeat {
    if (_sub != NightSub.gargoyleConvert) return null;
    final seats = gargoyleSeats;
    return _gargoyleIndex < seats.length ? seats[_gargoyleIndex] : null;
  }

  /// 目前這隻石像鬼的轉換範圍 —— **兩隻石像鬼的左右鄰座都算**
  /// （擔當 2026-09-25 指定：可以選另一隻石像鬼旁邊的位置）。
  ///
  /// 兩隻互認、一起行動，所以範圍共用。座次是環狀的，鄰座取的是最近的
  /// 兩位存活玩家（與熊同一套走訪）。狼隊自己人與另一隻已經轉換的人
  /// 也在範圍裡，由 [blockedSeats] 擋掉並標出原因。
  Set<int> get gargoyleConvertRange {
    if (currentGargoyleSeat == null) return const {};
    return {
      for (final gargoyle in gargoyleSeats)
        ...NightArbitrator.aliveNeighbors(state, gargoyle),
    };
  }

  /// 這一夜到目前為止**實際生效**的轉換 —— 選到機械狼的那一次不算
  ///（見 `NightArbitrator.effectiveConversions`）。
  Set<int> get convertedTonight =>
      NightArbitrator.effectiveConversions(state, actions);

  // ---- 轉換者（首夜最後的告知、第二夜起的開刀手勢）----
  //
  // 沿用 [_gargoyleIndex] 當格數：一隻石像鬼最多轉換一人，所以格數＝石像鬼數，
  // 撤銷游標也早就記著它。

  /// 要叫幾次 —— 固定是石像鬼的數量，不看實際轉換了幾位。
  int get convertedNotifySlots => gargoyleSeats.length;

  /// 第 [index] 格對應的座次；這一格沒有人時為 null。
  static int? _slotSeat(Iterable<int> seats, int index) {
    final sorted = seats.toList()..sort();
    return index < sorted.length ? sorted[index] : null;
  }

  /// 現在叫的是第幾位（1 起算）；不在那一步時為 null。
  int? get convertedNotifyOrdinal =>
      _sub == NightSub.convertedNotify ? _gargoyleIndex + 1 : null;

  /// 這一格要告知的被轉換者。那隻石像鬼選到機械狼（轉換悄悄白費）時是
  /// null —— 照樣喊、照樣停頓，沒有人睜眼。
  int? get convertedNotifySeat => _sub == NightSub.convertedNotify
      ? _slotSeat(convertedTonight, _gargoyleIndex)
      : null;

  bool get _inConvertedTurn =>
      _sub == NightSub.convertedKnifeGesture || _sub == NightSub.convertedKnife;

  /// 開刀手勢現在叫的是第幾位（1 起算）；不在那一輪時為 null。
  int? get convertedTurnOrdinal => _inConvertedTurn ? _gargoyleIndex + 1 : null;

  /// 這一格的被轉換者 —— **依座號排，出局的也佔一格**，每晚同一位對到同一格。
  /// 那隻石像鬼當初選到機械狼（轉換白費）時為 null。
  int? get convertedTurnSeat =>
      _inConvertedTurn ? _slotSeat(state.convertedSeats, _gargoyleIndex) : null;

  /// 這一格的人還活著、會睜眼。出局或沒有人時照樣喊，只是沒有人睜眼。
  bool get convertedTurnSeatAlive {
    final seat = convertedTurnSeat;
    return seat != null && state.playerAt(seat).alive;
  }

  /// 這一格的人今晚有刀 —— 石像鬼與機械狼都出局、而且只剩他一位被轉換者
  ///（開刀順位第 3 順位，見 `GameState.convertedKnifeHolder`）。
  bool get convertedTurnHasKnife {
    final seat = convertedTurnSeat;
    return seat != null && seat == state.convertedKnifeHolder;
  }

  /// 今晚實際持刀的被轉換者；沒有就是 null。
  int? get convertedKnifeHolder => state.convertedKnifeHolder;

  /// 這一步持有熊技能的人：熊本人，或學到熊的機械狼。
  int? get _bearSeat => step.byMechanicWolf
      ? state.seatOfRole(Roles.mechanicWolf.id)
      : state.seatOfRole(Roles.bear.id);

  /// 熊今晚兩側的鄰座 —— 鄰座死亡會往外順延，所以每晚重算。
  List<int> get bearNeighbors =>
      NightArbitrator.bearNeighbors(state, seat: _bearSeat);

  /// 熊今晚會不會咆哮。
  bool get bearGrowls => NightArbitrator.bearGrowls(
        state,
        convertedTonight: convertedTonight,
        seat: _bearSeat,
      );

  /// 剛剛查驗的座次 —— 目標已經寫進 [actions]，從那裡取回來。
  int? get _inspectedSeat {
    if (step.byMechanicWolf) return actions.mechanicInspectTarget;
    return effectiveSkill == NightSkill.psychicInspect
        ? actions.psychicTarget
        : actions.seerTarget;
  }

  /// 這一步完全沒有事要做，該整個跳過。
  ///
  /// 白痴、騎士這類角色**沒有夜間技能**，首夜那一步存在的唯一目的就是
  /// 問出座次。法官若在登記頁就把身分配好了，座次已知，這一步就沒有
  /// 任何內容 —— 既沒得登記，也沒有技能可收。
  ///
  /// 跳掉不會洩漏資訊：第二夜起本來就不會再叫這些角色
  /// （[NightFlow.laterNightSteps] 不含他們），所以每一夜的流程長度一致。
  ///
  /// 走過場的步驟不算在內 —— 那是「角色死光了仍要照喊」，刻意要保留的。
  bool _isNoOpStep(NightStep s) =>
      isFirstNight &&
      !isPassThrough(s) &&
      s.skill == NightSkill.none &&
      !needsRegistration(s);

  /// 登記完成後（或本來就不用登記時），該步驟要進入的技能子階段。
  NightSub _skillSubFor(NightStep s) => switch (s.skill) {
        NightSkill.witchPotion => NightSub.witchPotion,
        NightSkill.hunterGesture => NightSub.hunterGesture,
        NightSkill.bearGrowl => NightSub.bearGrowl,
        NightSkill.gargoyleConvert => NightSub.gargoyleConvert,
        NightSkill.mechanicReveal => NightSub.mechanicReveal,
        // 機械狼那一輪永遠從開刀手勢開始。
        NightSkill.mechanicTurn => NightSub.mechanicKnifeGesture,
        NightSkill.convertedNotify => NightSub.convertedNotify,
        NightSkill.convertedTurn => NightSub.convertedKnifeGesture,
        // 第二夜起只剩一種 none 步驟：被轉換者接刀後喪失原技能的那一步。
        // 人還活著、會睜眼，但沒有東西要收 —— 走過場，不是全員可點的選座頁。
        // （首夜的 none 步驟由 _isNoOpStep 與 _afterRegistration 處理，到不了這裡。）
        NightSkill.none => NightSub.passThrough,
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
        NightSub.bearGrowl ||
        NightSub.mechanicReveal ||
        NightSub.mechanicKnifeGesture ||
        NightSub.inspectResult ||
        NightSub.passThrough ||
        NightSub.convertedNotify ||
        NightSub.convertedKnifeGesture =>
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
      case NightSub.gargoyleConvert:
        // 一定要轉換（擔當 2026-09-25 指定：一定轉換兩位）。只有轉換範圍
        // 都是石像鬼或已被轉換、根本沒得選時才放行，否則流程會卡死。
        return _picked.isNotEmpty || (selectableSeats?.isEmpty ?? true);
      default:
        // 技能目標可以放棄（空刀、不用藥）；手勢與走過場沒有要選的東西。
        return true;
    }
  }

  /// 可選座次；null 表示所有存活座次都可選。
  Set<int>? get selectableSeats {
    switch (_sub) {
      case NightSub.hunterGesture:
      case NightSub.bearGrowl:
      case NightSub.mechanicKnifeGesture:
      case NightSub.mechanicReveal:
      case NightSub.inspectResult:
      case NightSub.passThrough:
      case NightSub.convertedNotify:
      case NightSub.convertedKnifeGesture:
        return const {};
      case NightSub.gargoyleConvert:
        // 兩隻石像鬼的左右鄰座都能選，扣掉狼隊自己人與另一隻已經轉換的人。
        return gargoyleConvertRange.difference(_blockedKeys);
      case NightSub.registerSeats:
        return _unassignedSeats;
      case NightSub.pickSpecial:
        // 只能從剛登記的狼隊成員裡挑（尚未被指認為其他特殊身分的）。
        return state.seatsOfRole(Roles.wolf.id).toSet();
      case NightSub.mechanicKnife:
      case NightSub.secondKnife:
      case NightSub.convertedKnife:
        // 第二刀可以砍同一人（破盾），所以不排除第一刀的目標。
        return _aliveSeats.difference(_blockedKeys);
      case NightSub.witchPotion:
        // 這一頁的座位格選的是**毒藥**目標；解藥用下方的按鈕挑。
        return poisonUsable ? _aliveSeats.difference(_blockedKeys) : const {};
      case NightSub.chooseTarget:
        final blocked = blockedSeats;
        if (blocked == null) return null;
        return _aliveSeats.difference(blocked.keys.toSet());
    }
  }

  Set<int> get _blockedKeys => blockedSeats?.keys.toSet() ?? const {};

  /// 不可選的座次與原因。null 表示沒有額外限制。
  Map<int, SeatBlockReason>? get blockedSeats {
    // 白貓翻牌後到正式離場之間**禁止成為任何技能的目標**
    // （擔當 2026-09-22 指定）。擋在輸入階段，不是收完再判定無效 ——
    // 這也順便免掉「延後期間又被殺一次」該怎麼結算的問題。
    final pendingCats = pendingCatBlocks(state);

    if (_sub == NightSub.witchPotion) {
      // 已經下了解藥、而本局不可同夜雙藥 → 毒藥整排都不能選。
      if (!poisonUsable && healTarget != null) {
        return {
          for (final p in state.players) p.seat: SeatBlockReason.witchDualUse,
        };
      }
      return pendingCats.isEmpty ? null : pendingCats;
    }
    if (_sub == NightSub.gargoyleConvert) {
      // 只擋石像鬼自己人（兩隻互認）。**機械狼不擋** —— 石像鬼不認得牠，
      // 擋了等於告訴石像鬼那一位是狼；選到的話轉換悄悄白費
      //（見 `NightArbitrator.effectiveConversions`）。
      final blocked = <int, SeatBlockReason>{
        for (final seat in gargoyleConvertRange)
          if (state.playerAt(seat).role?.id == Roles.awakenedGargoyle.id)
            seat: SeatBlockReason.convertGargoyle
          else if (actions.gargoyleConvertTargets.contains(seat))
            seat: SeatBlockReason.alreadyConverted,
      };
      return blocked.isEmpty ? null : blocked;
    }
    // 機械狼與轉換者的刀也是刀 —— 延後中的白貓同樣不能選。
    if (_sub == NightSub.mechanicKnife ||
        _sub == NightSub.secondKnife ||
        _sub == NightSub.convertedKnife) {
      return pendingCats.isEmpty ? null : pendingCats;
    }
    if (_sub != NightSub.chooseTarget) return null;

    // 各角色自己的限制與白貓那條擋的是**不同座次**，兩者要疊加 ——
    // 以前有白貓就只回白貓，機械狼因此能學自己、守衛能連守。
    // 同一座次兩者都成立時標白貓（寫在後面蓋過去）。
    final blocked = <int, SeatBlockReason>{
      ...?_skillBlockedSeats,
      ...pendingCats,
    };
    return blocked.isEmpty ? null : blocked;
  }

  /// 各角色自己的輸入限制（連守、連魅惑、自刀、學自己、暗戀自己）。
  Map<int, SeatBlockReason>? get _skillBlockedSeats {
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
      case NightSkill.secretAdmire:
        // 暗戀自己等於沒有勝負條件，擋掉。
        final self = state.seatOfRole(Roles.secretAdmirer.id);
        if (self != null) return {self: SeatBlockReason.secretAdmirerSelf};
      default:
        return null;
    }
    return null;
  }

  /// 反查某個原因擋住了哪一個座次；該限制目前未生效時回傳 null。
  ///
  /// 給 UI 寫提示文案用 —— 「昨晚守了 N 號」這種句子需要知道號碼，
  /// 但**不該讓頁面自己去讀規則旗標再算一次**。旗標的判斷只做在
  /// [blockedSeats] 一處，這裡只是換個角度取同一份結果。
  ///
  /// 只適用於單一座次的限制（連守、連魅惑、自刀、學自己）。
  /// [SeatBlockReason.witchDualUse] 擋的是整排，不該用這個查。
  int? blockedSeatFor(SeatBlockReason reason) {
    final blocked = blockedSeats;
    if (blocked == null) return null;
    for (final entry in blocked.entries) {
      if (entry.value == reason) return entry.key;
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

  /// 獵人的開槍預告（能不能開、不能的話死於什麼）—— 法官給手勢用。
  ///
  /// 每次取都會試算一次結算，頁面在一次畫面裡取一次就好。
  GunForecast get hunterGunForecast =>
      _arbitrator.hunterGunForecast(state, actions);

  /// 機械狼（學到槍牌）的開槍預告。
  GunForecast get mechanicGunForecast =>
      _arbitrator.mechanicGunForecast(state, actions);

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
        gargoyleIndex: _gargoyleIndex,
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
    _gargoyleIndex = cursor.gargoyleIndex;
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
    // 規則守在引擎：該選的沒選（登記座次、轉換）就不往下走 ——
    // 不能只靠畫面把按鈕反灰。
    if (!canProceed) return;

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
        final wasInspect = _isInspectSkill(effectiveSkill);
        final inspected = _picked.isNotEmpty;
        _commitTarget();
        _picked.clear();
        // 查驗完不直接跳下一步 —— 先停在結果那一頁，讓法官比給查驗者看。
        // 空驗（沒選人）就沒有結果可給，照常往下走。
        if (wasInspect && inspected) {
          _sub = NightSub.inspectResult;
        } else {
          _advanceStep();
        }

      case NightSub.inspectResult:
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

      case NightSub.gargoyleConvert:
        // 收下這一隻的轉換對象，再問下一隻。第二隻選不到第一隻選過的人
        //（[SeatBlockReason.alreadyConverted]），所以不會撞車。
        if (_picked.isNotEmpty) {
          actions.gargoyleConvertTargets.add(_picked.first);
        }
        _picked.clear();
        if (_gargoyleIndex + 1 < gargoyleSeats.length) {
          _gargoyleIndex++;
        } else {
          _advanceStep();
        }

      case NightSub.convertedNotify:
        // 一格一位，叫滿石像鬼的數量才換下一步。
        if (_gargoyleIndex + 1 < convertedNotifySlots) {
          _gargoyleIndex++;
        } else {
          _advanceStep();
        }

      case NightSub.convertedKnifeGesture:
        // 手勢給完：有刀就問刀口，沒刀就換下一位。
        if (convertedTurnHasKnife) {
          _sub = NightSub.convertedKnife;
        } else {
          _nextConvertedSlot();
        }

      case NightSub.convertedKnife:
        actions.wolfTarget = _picked.isEmpty ? null : _picked.first;
        _picked.clear();
        _nextConvertedSlot();

      case NightSub.bearGrowl:
        // 咆哮是**資訊**，不動任何狀態，但要進復盤 ——
        // 事後對帳時得看得出當晚給的是哪個答案。
        _logBearGrowl();
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
      case NightSkill.bearGrowl:
        // 學到熊：比咆哮手勢，看的是機械狼自己的鄰座。
        _sub = NightSub.bearGrowl;
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
      case NightSkill.secretAdmire:
        actions.secretAdmirerTarget = target;
      case NightSkill.dreamWeave:
        if (byMechanic) {
          actions.mechanicDreamTarget = target;
        } else {
          actions.dreamTarget = target;
        }
      case NightSkill.gargoyleConvert:
        // 轉換在 `next()` 裡逐隻收，這裡不處理。
        break;
      case NightSkill.witchPotion:
      case NightSkill.hunterGesture:
      case NightSkill.bearGrowl:
      case NightSkill.mechanicReveal:
      case NightSkill.mechanicTurn:
      case NightSkill.convertedNotify:
      case NightSkill.convertedTurn:
      case NightSkill.none:
        break;
    }
  }

  /// 轉換者那一輪換下一格；叫滿石像鬼的數量就換下一步。
  void _nextConvertedSlot() {
    if (_gargoyleIndex + 1 < convertedNotifySlots) {
      _gargoyleIndex++;
      _sub = NightSub.convertedKnifeGesture;
    } else {
      _advanceStep();
    }
  }

  void _advanceStep() {
    // 沒事可做的步驟一路跳過（見 [_isNoOpStep]）；全部跳完就結算。
    var next = _stepIndex + 1;
    while (next < steps.length && _isNoOpStep(steps[next])) {
      next++;
    }
    if (next >= steps.length) {
      _finish();
      return;
    }
    _stepIndex = next;
    _specialIndex = 0;
    _gargoyleIndex = 0;
    _sub = _initialSubFor(step);
  }

  void _finish() {
    // 走完所有特殊身分，剩下的座次就是平民。
    autoFilledVillagers =
        isFirstNight ? state.assignRemainingAsVillager() : const [];

    final settled = _arbitrator.settle(state, actions);
    _arbitrator.apply(state, actions, settled);
    outcome = settled;

    // 結算完就天亮了。要排在 apply 之後 —— 夜裡判死的白貓要在 night
    // 階段延後（當天投票後生效），白天判死的才會被當成隔天生效。
    state.phase = GamePhase.day;
  }
}
