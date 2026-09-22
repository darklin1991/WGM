import '../models/game_state.dart';
import '../models/log_entry.dart';
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

  /// 查驗類技能（預言家、通靈師）看到的身分。
  ///
  /// 機械狼學習之後，查驗看到的是**牠學到的身分**，不是機械狼本身
  /// —— 擔當 2026-09-19 指定，而且**預言家也一起騙過**：學到好人身分
  /// 就給金水。偽裝是機械狼的核心強度，不只騙通靈師。
  ///
  /// **學習當晚就生效**（擔當同日指定），所以要把本夜還沒結算的學習意圖
  /// [learnTargetTonight] 一起算進來 —— 學到的身分寫進 [GameState] 是
  /// 結算之後的事，光看局面會慢一夜。技能隔夜生效、偽裝當晚生效，
  /// 兩者刻意不同步，不要「順手」改成一致。
  ///
  /// 查驗與結算共用這一個判定 —— 分兩處算遲早會給出不一致的答案。
  static Role? apparentRoleAt(
    GameState state,
    int seat, {
    int? learnTargetTonight,
  }) {
    final actual = state.playerAt(seat).role;
    if (actual?.id != Roles.mechanicWolf.id) return actual;

    // 本夜剛學的優先；否則用之前學到的。學習對象的身分若還沒登記
    // （首夜邊問邊登記），就沒得偽裝，照實顯示機械狼。
    final pending = learnTargetTonight == null
        ? null
        : state.playerAt(learnTargetTonight).role;
    return pending ?? state.mechanicWolfLearnedRole ?? actual;
  }

  /// 熊兩側的鄰座 —— 環狀座次上**最近的兩位存活玩家**。
  ///
  /// 鄰座死亡時**往外順延**（擔當 2026-09-22 指定），所以不是固定的號碼，
  /// 每晚都要重算。回傳 `[逆時鐘那位, 順時鐘那位]`，人數不足時可能少於兩位、
  /// 甚至是空的（只剩熊自己）。
  ///
  /// 兩側順延到同一個人時只算一位 —— 場上剩三人時會發生。
  static List<int> bearNeighbors(GameState state) {
    final bear = state.seatOfRole(Roles.bear.id);
    if (bear == null || !state.playerAt(bear).alive) return const [];

    final seats = <int>{};
    for (final clockwise in [false, true]) {
      final seat = state.nextAliveSeat(bear, clockwise: clockwise);
      // 只剩熊自己時會繞回自己，那不算鄰座。
      if (seat != null && seat != bear) seats.add(seat);
    }
    return seats.toList()..sort();
  }

  /// 熊今晚會不會咆哮 —— 兩側鄰座裡有狼就咆哮。
  ///
  /// **被轉換者立刻算狼，沒有首夜延遲**（擔當 2026-09-22 指定）。
  /// 查驗那邊是第一夜金水、第二夜起查殺，熊沒有這個延遲 —— 所以熊
  /// 比預言家早一夜察覺轉換，這是熊在風聲諜影的價值。
  /// 兩者刻意不同步，不要為了「一致」把它們改成同一套。
  static bool bearGrowls(GameState state) => bearNeighbors(state).any(
        (seat) =>
            state.playerAt(seat).role?.camp == Camp.wolf ||
            state.isConverted(seat),
      );

  /// **預言家**看到的陣營（金水／查殺）。
  ///
  /// 與 [apparentRoleAt] 分開是必要的：被轉換者身上兩者會**給出不同答案**。
  ///
  /// | 查驗者 | 查被轉換的女巫（第二夜起） |
  /// |---|---|
  /// | 預言家（看陣營） | **查殺** |
  /// | 通靈師／魔鏡少女（看身分） | **女巫** —— 他確實還是女巫 |
  ///
  /// 擔當 2026-09-22 指定如此。兩邊對不上正是識破轉換的線索，
  /// 不要為了「一致」把其中一邊改掉。
  ///
  /// 被轉換者**第一夜仍是好人**，第二夜起才是狼。
  static Camp? apparentCampAt(
    GameState state,
    int seat, {
    int? learnTargetTonight,
  }) {
    if (state.convertedShowsAsWolf(seat)) return Camp.wolf;
    return apparentRoleAt(state, seat, learnTargetTonight: learnTargetTonight)
        ?.camp;
  }

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

    // ---- 攝夢 ----
    // 夢遊者免疫今晚的一切傷害（**連毒都擋**，比守衛強一截），
    // 但連續兩晚被攝的人會夢死，而夢死**擋不住**。
    // 必須排在刀、毒、殉情之後：免疫是把已經判定的死亡拿掉。
    _resolveDream(
      state: state,
      actions: actions,
      deaths: deaths,
      notes: notes,
    );

    // ---- 開槍資格 ----
    var hunterMayShoot = false;

    // 獵人本人：死因不是毒、也不是夢死就能開槍。
    //
    // 兩者不可混為一談：「被毒不可開槍」是板子可設定的旗標
    // （`poisonedHunterCannotShoot`），夢死則是**寫死的規則**，
    // 不受任何旗標影響。
    final hunterSeat = state.seatOfRole(Roles.hunter.id);
    if (hunterSeat != null && deaths.containsKey(hunterSeat)) {
      final cause = deaths[hunterSeat]!;
      if (cause == DeathCause.dreamDeath) {
        notes.add('獵人（$hunterSeat 號）夢死，不可開槍');
      } else if (cause == DeathCause.poison && rules.poisonedHunterCannotShoot) {
        notes.add('獵人（$hunterSeat 號）被毒死，依規則不可開槍');
      } else {
        hunterMayShoot = true;
        notes.add('獵人（$hunterSeat 號）死亡，可以開槍');
      }
    }

    // 狼王：**被自刀出局才能開槍**，同時吃毒也不影響；沒被自刀而死就是被毒，
    // 不能開。狼隊自己知道有沒有自刀，所以狼王不需要每晚給手勢。
    // 注意這裡看的是「有沒有被刀」而不是死因 —— 刀＋毒的死因會記成毒。
    var wolfKingMayShoot = false;
    final wolfKingSeat = state.seatOfRole(Roles.wolfKing.id);
    if (wolfKingSeat != null && deaths.containsKey(wolfKingSeat)) {
      if (actions.wolfTargets.contains(wolfKingSeat)) {
        wolfKingMayShoot = true;
        notes.add('狼王（$wolfKingSeat 號）被自刀出局，可以開槍');
      } else {
        notes.add('狼王（$wolfKingSeat 號）未被自刀而出局（被毒），不可開槍');
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
      seerSawWolf = apparentCampAt(
            state,
            seerTarget,
            learnTargetTonight: actions.mechanicWolfLearnTarget,
          ) ==
          Camp.wolf;
    }

    // ---- 通靈師查驗（看到的是真實身分，不只好人／狼人）----
    PsychicResult? psychicResult;
    if (actions.psychicTarget != null) {
      psychicResult = PsychicResult(
        seat: actions.psychicTarget!,
        revealedRole: apparentRoleAt(
          state,
          actions.psychicTarget!,
          learnTargetTonight: actions.mechanicWolfLearnTarget,
        ),
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
      // 機械狼不會查自己（學習對象不能選自己，查驗目標也一樣），
      // 但仍走同一個判定 —— 偽裝規則只有一份。
      final seen = apparentRoleAt(
        state,
        inspect,
        learnTargetTonight: actions.mechanicWolfLearnTarget,
      );
      if (learned?.id == Roles.psychic.id) {
        mechanicPsychicResult = PsychicResult(
          seat: inspect,
          revealedRole: seen,
        );
      } else {
        mechanicSeerTarget = inspect;
        mechanicSeerSawWolf = apparentCampAt(
              state,
              inspect,
              learnTargetTonight: actions.mechanicWolfLearnTarget,
            ) ==
            Camp.wolf;
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
      wolfKingMayShoot: wolfKingMayShoot,
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

  /// 攝夢人的結算：夢遊者的免疫、連兩晚的夢死、攝夢人出局的連帶。
  ///
  /// **順序很重要**，三件事必須照這個先後做：
  ///
  /// 1. **免疫** —— 把夢遊者從死亡名單裡拿掉。連女巫的毒都擋
  ///    （守衛擋不住毒，攝夢人擋得住，這是他的核心強度）。
  /// 2. **夢死** —— 與上一晚是同一人就死，而且**擋不住**：免疫剛拿掉的
  ///    死亡不會救回他，守護與解藥也一樣。所以要排在免疫**之後**寫入。
  /// 3. **攝夢人出局的連帶** —— 攝夢人今晚死了，當晚的夢遊者一併死亡。
  ///
  /// 第 1 與第 2 看似矛盾，其實不是：免疫擋的是**別人造成的**傷害，
  /// 夢死是被攝這件事本身造成的，不在免疫範圍內。
  void _resolveDream({
    required GameState state,
    required NightActions actions,
    required Map<int, DeathCause> deaths,
    required List<String> notes,
  }) {
    final dreamer = actions.dreamTarget;
    if (dreamer == null) return;

    // 1. 免疫：今晚落在夢遊者身上的死亡全部取消。
    final blocked = deaths.remove(dreamer);
    if (blocked != null) {
      notes.add('$dreamer 號在夢遊，免疫今晚的${blocked.labelZh}');
    }

    // 2. 夢死：連續兩晚被攝。擋不住，所以直接寫進死亡名單。
    if (dreamer == state.lastDreamTarget) {
      deaths[dreamer] = DeathCause.dreamDeath;
      notes.add('$dreamer 號連續兩晚被攝，夢死（擋不住，也不能開槍）');
      return;
    }

    // 3. 攝夢人今晚出局 → 當晚的夢遊者一併死亡。
    final weaver = state.seatOfRole(Roles.dreamWeaver.id);
    if (weaver != null && deaths.containsKey(weaver)) {
      deaths[dreamer] = DeathCause.dreamDeath;
      notes.add('攝夢人（$weaver 號）出局，夢遊中的 $dreamer 號一併死亡');
    }
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

    // 魅惑只看**本晚指定的對象** —— 沒選就是沒魅惑，不沿用前一晚的。
    check(Roles.wolfBeauty.id, actions.wolfBeautyCharmTarget, '狼美人');
    check(
      Roles.mechanicWolf.id,
      actions.mechanicCharmTarget,
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

    // 被轉換者接下狼刀的那一刻正式「轉換」：同時**喪失尚未使用的原技能**
    // （擔當 2026-09-22 指定）。在那之前他的神職技能照常能用，
    // 所以不能一被轉換就標記 —— 要等真的輪到他持刀。
    final knifeHolder = state.convertedKnifeHolder;
    if (knifeHolder != null && !state.hasLostSkills(knifeHolder)) {
      state.convertedActivatedSeats.add(knifeHolder);
      state.log.add(
        round: actions.night,
        isNight: true,
        kind: LogKind.ruling,
        text: '$knifeHolder 號（被轉換者）接下狼刀，原本的技能就此失效',
        seats: [knifeHolder],
      );
    }

    // 覺醒石像鬼的轉換：只有首夜會有，寫進去就固定了。
    //
    // 兩隻選到同一人時 `gargoyleConvertTargets` 本來就只有一筆 ——
    // 「只有那一個人轉換進狼隊，另一次白費」（擔當指定）自然成立。
    if (actions.gargoyleConvertTargets.isNotEmpty &&
        state.conversionNight == null) {
      state.convertedSeats.addAll(actions.gargoyleConvertTargets);
      state.conversionNight = actions.night;
    }

    // 攝夢人：記住今晚攝的是誰，明晚才判斷得出「連續兩晚」。
    // **每晚都要更新**，包含沒攝（null）—— 中間斷一晚就不算連續。
    state.lastDreamTarget = actions.dreamTarget;

    // 暗戀者：首夜選定，**當下的陣營就固定下來**（擔當 2026-09-22 指定）。
    //
    // 存陣營而不是每次去讀對象現在站哪邊 —— 對象之後若被轉換成狼，
    // 暗戀者跟的仍是選的時候那一邊。對象死了也不改。
    final admired = actions.secretAdmirerTarget;
    if (admired != null && state.secretAdmirerCamp == null) {
      state.secretAdmirerTarget = admired;
      state.secretAdmirerCamp = state.playerAt(admired).role?.camp;
    }

    // 魅惑每晚重設：**沒選就是沒魅惑**，前一晚的對象一併解除。
    // 存進狀態是為了白天用 —— 狼美人若被放逐或被騎士決鬥掉，
    // 殉情的對象就是昨晚指定的那位。
    state.charmedSeat = actions.wolfBeautyCharmTarget;
    state.mechanicCharmedSeat = actions.mechanicCharmTarget;

    for (final d in outcome.deaths) {
      // 白貓不會當場離場 —— 翻牌之後還能活到下一次放逐投票結束。
      // 延後期間他算存活，所以連 `alive` 都不動。
      if (state.deferWhiteCatDeath(d.seat, d.cause)) continue;
      state.playerAt(d.seat).alive = false;
    }

    state.lastGuardTarget = actions.guardTarget;
    state.lastMechanicGuardTarget = actions.mechanicGuardTarget;
    state.lastCharmTarget = actions.wolfBeautyCharmTarget;
    state.lastMechanicCharmTarget = actions.mechanicCharmTarget;

    _writeLog(state, actions, outcome);
  }

  /// 把這一夜寫進復盤日誌。
  ///
  /// 和狀態變更寫在同一處（[apply] 的結尾）—— 分開寫就會有一邊漏掉。
  void _writeLog(GameState state, NightActions actions, NightOutcome outcome) {
    final log = state.log;
    final night = actions.night;

    void action(String text, [List<int> seats = const []]) => log.add(
          round: night,
          isNight: true,
          kind: LogKind.nightAction,
          text: text,
          seats: seats,
        );
    void info(String text, [List<int> seats = const []]) => log.add(
          round: night,
          isNight: true,
          kind: LogKind.info,
          text: text,
          seats: seats,
        );

    // ---- 行動 ----
    if (actions.guardTarget != null) {
      action('守衛守 ${actions.guardTarget} 號', [actions.guardTarget!]);
    }
    for (final seat in actions.wolfTargets.toSet()) {
      final times = actions.wolfTargets.where((t) => t == seat).length;
      action(times > 1 ? '狼刀 $seat 號（兩刀集中）' : '狼刀 $seat 號', [seat]);
    }
    if (actions.wolfBeautyCharmTarget != null) {
      action('狼美人魅惑 ${actions.wolfBeautyCharmTarget} 號',
          [actions.wolfBeautyCharmTarget!]);
    }
    if (actions.witchHealTarget != null) {
      action('女巫用解藥救 ${actions.witchHealTarget} 號',
          [actions.witchHealTarget!]);
    }
    if (actions.witchPoisonTarget != null) {
      action('女巫用毒藥毒 ${actions.witchPoisonTarget} 號',
          [actions.witchPoisonTarget!]);
    }

    // ---- 機械狼 ----
    if (outcome.mechanicLearnedRole != null) {
      action('機械狼學到${outcome.mechanicLearnedRole!.nameZh}（隔夜生效）');
    }
    if (actions.mechanicGuardTarget != null) {
      action('機械狼（守衛）守 ${actions.mechanicGuardTarget} 號',
          [actions.mechanicGuardTarget!]);
    }
    if (actions.mechanicPoisonTarget != null) {
      action('機械狼（女巫）毒 ${actions.mechanicPoisonTarget} 號',
          [actions.mechanicPoisonTarget!]);
    }

    // ---- 情報 ----
    if (outcome.seerTarget != null) {
      info(
        '預言家查驗 ${outcome.seerTarget} 號 → '
        '${outcome.seerSawWolf ? "查殺" : "金水"}',
        [outcome.seerTarget!],
      );
    }
    if (outcome.psychicResult != null) {
      final r = outcome.psychicResult!;
      info('通靈師查驗 ${r.seat} 號 → ${r.revealedRole?.nameZh ?? "尚未登記"}',
          [r.seat]);
    }
    if (outcome.mechanicSeerTarget != null) {
      info(
        '機械狼（預言家）查驗 ${outcome.mechanicSeerTarget} 號 → '
        '${outcome.mechanicSeerSawWolf ? "查殺" : "金水"}',
        [outcome.mechanicSeerTarget!],
      );
    }
    if (outcome.mechanicPsychicResult != null) {
      final r = outcome.mechanicPsychicResult!;
      info('機械狼（通靈師）查驗 ${r.seat} 號 → ${r.revealedRole?.nameZh ?? "尚未登記"}',
          [r.seat]);
    }

    // ---- 裁決與結果 ----
    log.addAll(
      round: night,
      isNight: true,
      kind: LogKind.ruling,
      texts: outcome.notes,
    );

    if (outcome.deaths.isEmpty) {
      log.add(
        round: night,
        isNight: true,
        kind: LogKind.death,
        text: '平安夜，沒有人出局',
      );
    } else {
      for (final d in outcome.deaths) {
        log.add(
          round: night,
          isNight: true,
          kind: LogKind.death,
          text: '${d.seat} 號出局'
              '（${state.playerAt(d.seat).role?.nameZh ?? "未知"}・'
              '${d.cause.labelZh}）',
          seats: [d.seat],
        );
      }
    }
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
