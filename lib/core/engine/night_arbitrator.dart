import '../models/game_state.dart';
import '../models/night_action.dart';
import '../models/player.dart';
import '../models/role.dart';

/// 夜晚結算器。
///
/// 純 Dart，不依賴 Flutter —— 規則組合極多（衝突規則 × 規則旗標），
/// 必須能用單元測試完整涵蓋。
///
/// 收集與結算**分兩階段**：[NightActions] 只記錄意圖，這裡才一次性
/// 套用衝突規則。
///
/// 女巫的資訊時序是特例：女巫看到的是**狼刀目標**，不套用守衛結果，
/// 因此可能對一個已被守住的人下解藥 —— 同守同救（奶穿）就是這樣發生的。
///
/// 機械狼學到守衛或女巫時，會有**第二份**守護／用藥意圖。兩份意圖對稱處理：
/// 只要有任一人守住就算被守、任一人下解藥就算被救，同守同救的判定不變。
class NightArbitrator {
  const NightArbitrator();

  /// 帶槍的身分（死亡時可開槍帶人）。機械狼學到這些才拿得到槍。
  static const gunRoleIds = Roles.gunRoleIds;

  /// 算是「吃刀」的死因 —— 機械狼學到槍牌後的開槍條件之一。
  ///
  /// 同守同救是刀口造成的死亡，一併算吃刀；吃推（放逐）由白天流程判定。
  static const knifeDeathCauses = <DeathCause>{
    DeathCause.wolfKill,
    DeathCause.guardHealConflict,
    DeathCause.exile,
  };

  /// 結算一個夜晚，回傳結果。**不修改 [state]** —— 套用結果請用 [apply]。
  NightOutcome settle(GameState state, NightActions actions) {
    final rules = state.preset.rules;
    final notes = <String>[];
    final deaths = <int, DeathCause>{};

    // 機械狼學到守衛時另有一份守護，與原守衛合併看待。
    // （機械狼學到女巫只拿得到毒藥，所以解藥永遠只有原女巫那一瓶。）
    final guardedSeats = <int>{
      if (actions.guardTarget != null) actions.guardTarget!,
      if (actions.mechanicGuardTarget != null) actions.mechanicGuardTarget!,
    };
    final healedSeats = <int>{
      if (actions.witchHealTarget != null) actions.witchHealTarget!,
    };

    // ---- 狼刀 ----
    // 機械狼學到狼人時會有第二刀。兩刀砍同一人可以**破盾** —— 守衛守了也沒用。
    final shieldBroken = <int>[];
    final knifeHits = <int, int>{};
    for (final seat in actions.wolfTargets) {
      knifeHits[seat] = (knifeHits[seat] ?? 0) + 1;
    }

    if (knifeHits.isEmpty) {
      notes.add('狼人空刀');
    }
    for (final entry in knifeHits.entries) {
      final knifed = entry.key;

      // 破盾：兩刀集中同一人，守衛的守護與女巫的解藥**都**擋不住，必死。
      if (entry.value >= 2 && rules.mechanicDoubleKnifeBreaksShield) {
        if (guardedSeats.contains(knifed) || healedSeats.contains(knifed)) {
          shieldBroken.add(knifed);
          notes.add('$knifed 號被雙刀集中，破盾 —— 守衛的守護與女巫的解藥都失效');
        }
        deaths[knifed] = DeathCause.wolfKill;
        continue;
      }

      final guarded = guardedSeats.contains(knifed);
      final healed = healedSeats.contains(knifed);

      if (guarded && healed) {
        // 同守同救（奶穿）。
        if (rules.guardHealKills) {
          deaths[knifed] = DeathCause.guardHealConflict;
          notes.add('$knifed 號同守同救（奶穿），依規則仍然死亡');
        } else {
          notes.add('$knifed 號同守同救，依本局規則存活');
        }
      } else if (guarded) {
        notes.add('$knifed 號被守衛守住，存活');
      } else if (healed) {
        notes.add('$knifed 號被女巫解藥救回，存活');
      } else {
        deaths[knifed] = DeathCause.wolfKill;
      }
    }

    // ---- 毒藥 ----
    // 一般守衛防不了毒；但機械狼學到的守衛更強 —— 會把毒**反彈給下毒的人**。
    // 被刀又被毒也是死。毒的判定覆蓋前面的存活結論。
    final reflected = _resolvePoison(
      state: state,
      actions: actions,
      guardedSeats: guardedSeats,
      deaths: deaths,
      notes: notes,
    );

    // ---- 殉情 ----
    // 狼美人今晚出局，被魅惑者隨之死亡。魅惑目標以本晚新指定的為準；
    // 本晚沒重新魅惑就沿用原本的對象。
    //
    // 「被騎士決鬥致死不觸發殉情」是白天的事，不在夜晚結算範圍內。
    final charmSuicide = _resolveCharmSuicide(
      state: state,
      actions: actions,
      deaths: deaths,
      notes: notes,
    );

    // ---- 開槍資格 ----
    var hunterMayShoot = false;

    // 獵人本人：死因不是毒就能開槍。
    final hunterSeat = state.seatOfRole(Roles.hunter.id);
    if (hunterSeat != null && deaths.containsKey(hunterSeat)) {
      final cause = deaths[hunterSeat]!;
      if (cause == DeathCause.poison && rules.poisonedHunterCannotShoot) {
        notes.add('獵人（$hunterSeat 號）被毒死，依規則不可開槍');
      } else {
        hunterMayShoot = true;
        notes.add('獵人（$hunterSeat 號）死亡，可以開槍');
      }
    }

    // 機械狼學到槍牌（獵人／狼王）：**只有吃刀或吃推**才能開槍。
    // 吃毒不能開，殉情之類的其他死法也不能 —— 比獵人本人的條件嚴格。
    final mechanicSeat = state.seatOfRole(Roles.mechanicWolf.id);
    final learnedGun = state.mechanicWolfLearnedRole;
    if (mechanicSeat != null &&
        learnedGun != null &&
        gunRoleIds.contains(learnedGun.id) &&
        deaths.containsKey(mechanicSeat)) {
      final cause = deaths[mechanicSeat]!;
      if (knifeDeathCauses.contains(cause)) {
        hunterMayShoot = true;
        notes.add(
          '機械狼（$mechanicSeat 號，已學到${learnedGun.nameZh}）吃刀出局，可以開槍',
        );
      } else {
        notes.add(
          '機械狼（$mechanicSeat 號，已學到${learnedGun.nameZh}）'
          '死因為${cause.labelZh}，不是吃刀或吃推，不可開槍',
        );
      }
    }

    // ---- 預言家查驗 ----
    final seerTarget = actions.seerTarget;
    var seerSawWolf = false;
    if (seerTarget != null) {
      seerSawWolf = state.playerAt(seerTarget).role?.camp == Camp.wolf;
    }

    // ---- 通靈師查驗（看到的是真實身分，不只好人／狼人）----
    PsychicResult? psychicResult;
    if (actions.psychicTarget != null) {
      psychicResult = PsychicResult(
        seat: actions.psychicTarget!,
        revealedRole: state.playerAt(actions.psychicTarget!).role,
      );
    }

    // ---- 機械狼 ----
    Role? mechanicLearnedRole;
    if (actions.mechanicWolfLearnTarget != null) {
      mechanicLearnedRole =
          state.playerAt(actions.mechanicWolfLearnTarget!).role;
      notes.add(
        '機械狼學習 ${actions.mechanicWolfLearnTarget} 號'
        '（${mechanicLearnedRole?.nameZh ?? "身分未登記"}），隔夜起生效',
      );
    }

    int? mechanicSeerTarget;
    var mechanicSeerSawWolf = false;
    PsychicResult? mechanicPsychicResult;
    final inspect = actions.mechanicInspectTarget;
    if (inspect != null) {
      final learned = state.mechanicWolfLearnedRole;
      if (learned?.id == Roles.psychic.id) {
        mechanicPsychicResult = PsychicResult(
          seat: inspect,
          revealedRole: state.playerAt(inspect).role,
        );
      } else {
        mechanicSeerTarget = inspect;
        mechanicSeerSawWolf = state.playerAt(inspect).role?.camp == Camp.wolf;
      }
    }

    final sorted = deaths.keys.toList()..sort();

    return NightOutcome(
      deaths: [
        for (final seat in sorted) Death(seat: seat, cause: deaths[seat]!),
      ],
      notes: notes,
      seerTarget: seerTarget,
      seerSawWolf: seerSawWolf,
      hunterMayShoot: hunterMayShoot,
      psychicResult: psychicResult,
      mechanicLearnedRole: mechanicLearnedRole,
      mechanicSeerTarget: mechanicSeerTarget,
      mechanicSeerSawWolf: mechanicSeerSawWolf,
      mechanicPsychicResult: mechanicPsychicResult,
      charmSuicideSeat: charmSuicide,
      poisonReflectedTo: reflected,
      shieldBrokenSeats: shieldBroken,
    );
  }

  /// 狼美人（或學到狼美人的機械狼）今晚出局時，處理殉情。
  ///
  /// 回傳殉情者座次；沒有殉情回傳 null。
  int? _resolveCharmSuicide({
    required GameState state,
    required NightActions actions,
    required Map<int, DeathCause> deaths,
    required List<String> notes,
  }) {
    int? victim;

    void check(String roleId, int? charmedNow, String label) {
      final seat = state.seatOfRole(roleId);
      if (seat == null || !deaths.containsKey(seat)) return;
      if (charmedNow == null) return;
      if (deaths.containsKey(charmedNow)) {
        // 已經因別的原因死了，不重複記一次死因。
        notes.add('$charmedNow 號被 $label（$seat 號）魅惑，但本夜已另因他故死亡');
        return;
      }
      deaths[charmedNow] = DeathCause.loveSuicide;
      victim = charmedNow;
      notes.add('$label（$seat 號）出局，$charmedNow 號殉情');
    }

    check(
      Roles.wolfBeauty.id,
      actions.wolfBeautyCharmTarget ?? state.charmedSeat,
      '狼美人',
    );
    check(
      Roles.mechanicWolf.id,
      actions.mechanicCharmTarget ?? state.mechanicCharmedSeat,
      '機械狼（已學到狼美人）',
    );

    return victim;
  }

  /// 結算毒藥，含機械狼守護的反彈。
  ///
  /// 回傳被反彈毒死的座次（下毒者）；沒有反彈回傳 null。
  int? _resolvePoison({
    required GameState state,
    required NightActions actions,
    required Set<int> guardedSeats,
    required Map<int, DeathCause> deaths,
    required List<String> notes,
  }) {
    final rules = state.preset.rules;
    final mechanicGuard = actions.mechanicGuardTarget;
    int? reflectedTo;

    // 下毒者與其目標配成一組 —— 反彈要知道毒是誰下的。
    final shots = <({int target, int? poisoner, String label})>[
      if (actions.witchPoisonTarget != null)
        (
          target: actions.witchPoisonTarget!,
          poisoner: state.seatOfRole(Roles.witch.id),
          label: '女巫',
        ),
      if (actions.mechanicPoisonTarget != null)
        (
          target: actions.mechanicPoisonTarget!,
          poisoner: state.seatOfRole(Roles.mechanicWolf.id),
          label: '機械狼（已學到女巫）',
        ),
    ];

    for (final shot in shots) {
      final poisoned = shot.target;

      // 機械狼的守護會把毒反彈回下毒的人；一般守衛則防不了毒。
      if (mechanicGuard == poisoned && rules.mechanicGuardReflectsPoison) {
        final poisoner = shot.poisoner;
        notes.add('$poisoned 號被機械狼守護，毒藥反彈');
        if (poisoner == null) {
          notes.add('找不到下毒者的座次，反彈無對象');
          continue;
        }
        deaths[poisoner] = DeathCause.poison;
        reflectedTo = poisoner;
        notes.add('${shot.label}（$poisoner 號）被自己的毒反彈毒死');
        continue;
      }

      if (guardedSeats.contains(poisoned)) {
        notes.add('$poisoned 號雖被守衛守護，但守衛防不了毒，死亡');
      }
      deaths[poisoned] = DeathCause.poison;
    }

    return reflectedTo;
  }

  /// 把結算結果套用到 [state]。
  ///
  /// 依「狀態直接修改」的架構決定，這裡直接改狀態；呼叫端負責在此之前
  /// 存好撤銷快照、並在同一處寫入復盤日誌。
  void apply(GameState state, NightActions actions, NightOutcome outcome) {
    // 事實標記每晚重算。
    for (final p in state.players) {
      p.nightFacts.clear();
    }

    for (final seat in [actions.guardTarget, actions.mechanicGuardTarget]) {
      if (seat != null) state.playerAt(seat).nightFacts.add(FactTag.guarded);
    }
    for (final seat in actions.wolfTargets) {
      state.playerAt(seat).nightFacts.add(FactTag.knifed);
    }
    if (actions.witchHealTarget != null) {
      state.playerAt(actions.witchHealTarget!).nightFacts.add(FactTag.healed);
      state.witchAntidoteAvailable = false;
    }
    if (actions.witchPoisonTarget != null) {
      state.playerAt(actions.witchPoisonTarget!).nightFacts.add(FactTag.poisoned);
      state.witchPoisonAvailable = false;
    }
    if (actions.mechanicPoisonTarget != null) {
      state
          .playerAt(actions.mechanicPoisonTarget!)
          .nightFacts
          .add(FactTag.poisoned);
      state.mechanicPoisonAvailable = false;
    }

    // 查驗結果記為資訊標記（不影響結算，供法官備忘與復盤）。
    if (outcome.seerTarget != null) {
      state
          .playerAt(outcome.seerTarget!)
          .infoTags
          .add(outcome.seerSawWolf ? InfoTag.verifiedWolf : InfoTag.verifiedGood);
    }
    if (outcome.mechanicSeerTarget != null) {
      state.playerAt(outcome.mechanicSeerTarget!).infoTags.add(
            outcome.mechanicSeerSawWolf
                ? InfoTag.verifiedWolf
                : InfoTag.verifiedGood,
          );
    }

    // 機械狼學習：整局限一次，隔夜生效（生效判斷見
    // [GameState.mechanicSkillActiveOn]）。
    if (outcome.mechanicLearnedRole != null &&
        state.mechanicWolfLearnedRole == null) {
      state.mechanicWolfLearnedRole = outcome.mechanicLearnedRole;
      state.mechanicWolfLearnedNight = actions.night;
    }

    // 魅惑對象沿用到下一夜，直到重新指定。
    if (actions.wolfBeautyCharmTarget != null) {
      state.charmedSeat = actions.wolfBeautyCharmTarget;
    }
    if (actions.mechanicCharmTarget != null) {
      state.mechanicCharmedSeat = actions.mechanicCharmTarget;
    }

    for (final d in outcome.deaths) {
      state.playerAt(d.seat).alive = false;
    }

    state.lastGuardTarget = actions.guardTarget;
    state.lastMechanicGuardTarget = actions.mechanicGuardTarget;
    state.lastCharmTarget = actions.wolfBeautyCharmTarget;
    state.lastMechanicCharmTarget = actions.mechanicCharmTarget;
  }

  /// 守衛可否守 [seat]（不可連續兩晚守同一人）。
  bool guardMayProtect(GameState state, int seat) {
    if (!state.preset.rules.guardCannotRepeatTarget) return true;
    return state.lastGuardTarget != seat;
  }

  /// 機械狼（學到守衛）可否守 [seat]。守護紀錄與原守衛各自獨立。
  bool mechanicGuardMayProtect(GameState state, int seat) {
    if (!state.preset.rules.guardCannotRepeatTarget) return true;
    return state.lastMechanicGuardTarget != seat;
  }

  /// 狼美人可否魅惑 [seat]（不可連續兩晚魅惑同一人）。
  bool wolfBeautyMayCharm(GameState state, int seat) {
    if (!state.preset.rules.charmCannotRepeatTarget) return true;
    return state.lastCharmTarget != seat;
  }

  /// 狼隊可否把刀指向 [seat] —— 狼美人不能自刀。
  bool wolfMayKnife(GameState state, int seat) {
    if (!state.preset.rules.wolfBeautyCannotSelfKill) return true;
    return state.playerAt(seat).role?.id != Roles.wolfBeauty.id;
  }

  /// 獵人今晚若出局，能不能開槍 —— 法官在「獵人請睜眼」時據此給手勢。
  ///
  /// 這是**預告**狀態（獵人還活著時給的手勢），與
  /// [NightOutcome.hunterMayShoot]（結算後、獵人確實死亡才成立）不同。
  ///
  /// 獵人排在夜晚順序的最後，就是為了這個：法官必須先收完女巫的毒藥，
  /// 才知道該給拇指向上還是向下。
  bool hunterCanShootTonight(GameState state, NightActions actions) {
    final seat = state.seatOfRole(Roles.hunter.id);
    if (seat == null) return false;
    if (!state.playerAt(seat).alive) return false;
    if (!_poisonedTonight(state, actions, seat)) return true;
    return !state.preset.rules.poisonedHunterCannotShoot;
  }

  /// 機械狼目前的身分 —— **含本夜剛學到、還沒套用到狀態的**。
  ///
  /// 夜晚結尾要告知機械狼學到什麼，那時 [apply] 還沒跑，所以不能只看狀態。
  /// 首夜走到結尾時平民尚未登記（要等所有特殊身分登記完才自動補），
  /// 因此沒登記身分的一律視為平民。
  Role? mechanicLearnedRoleNow(GameState state, NightActions actions) {
    final already = state.mechanicWolfLearnedRole;
    if (already != null) return already;
    final target = actions.mechanicWolfLearnTarget;
    if (target == null) return null;
    return state.playerAt(target).role ?? Roles.villager;
  }

  /// 機械狼（學到槍牌）今晚若出局，能不能開槍 —— 法官給手勢用。
  ///
  /// 機械狼的條件比獵人嚴格：**只有吃刀或吃推才能開槍**。被毒不行，
  /// 所以今晚只要中了毒，手勢就要給「不可開槍」。
  bool mechanicCanShootTonight(GameState state, NightActions actions) {
    final seat = state.seatOfRole(Roles.mechanicWolf.id);
    if (seat == null) return false;
    if (!state.playerAt(seat).alive) return false;
    final learned = mechanicLearnedRoleNow(state, actions);
    if (learned == null || !gunRoleIds.contains(learned.id)) return false;
    return !_poisonedTonight(state, actions, seat);
  }

  /// [seat] 今晚是否被下了毒（且沒有被機械狼的守護反彈掉）。
  bool _poisonedTonight(GameState state, NightActions actions, int seat) {
    final hit = actions.witchPoisonTarget == seat ||
        actions.mechanicPoisonTarget == seat;
    if (!hit) return false;
    // 被機械狼守住的話毒會反彈，等於沒中毒。
    if (actions.mechanicGuardTarget == seat &&
        state.preset.rules.mechanicGuardReflectsPoison) {
      return false;
    }
    return true;
  }
}
