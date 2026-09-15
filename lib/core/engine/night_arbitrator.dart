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
class NightArbitrator {
  const NightArbitrator();

  /// 結算一個夜晚，回傳結果。**不修改 [state]** —— 套用結果請用 [apply]。
  NightOutcome settle(GameState state, NightActions actions) {
    final rules = state.preset.rules;
    final notes = <String>[];
    final deaths = <int, DeathCause>{};

    // ---- 狼刀 ----
    final knifed = actions.wolfTarget;
    if (knifed == null) {
      notes.add('狼人空刀');
    } else {
      final guarded = actions.guardTarget == knifed;
      final healed = actions.witchHealTarget == knifed;

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

    // ---- 女巫毒藥 ----
    // 守衛防不了毒；被刀又被毒也是死。毒的判定覆蓋前面的存活結論。
    final poisoned = actions.witchPoisonTarget;
    if (poisoned != null) {
      if (actions.guardTarget == poisoned) {
        notes.add('$poisoned 號雖被守衛守護，但守衛防不了毒，死亡');
      }
      deaths[poisoned] = DeathCause.poison;
    }

    // ---- 獵人開槍資格 ----
    var hunterMayShoot = false;
    final hunterSeat = state.seatOfRole(Roles.hunter.id);
    if (hunterSeat != null && deaths.containsKey(hunterSeat)) {
      final cause = deaths[hunterSeat]!;
      if (cause == DeathCause.poison && rules.poisonedHunterCannotShoot) {
        hunterMayShoot = false;
        notes.add('獵人（$hunterSeat 號）被毒死，依規則不可開槍');
      } else {
        hunterMayShoot = true;
        notes.add('獵人（$hunterSeat 號）死亡，可以開槍');
      }
    }

    // ---- 預言家查驗 ----
    final seerTarget = actions.seerTarget;
    var seerSawWolf = false;
    if (seerTarget != null) {
      seerSawWolf = state.playerAt(seerTarget).role?.camp == Camp.wolf;
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
    );
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

    if (actions.guardTarget != null) {
      state.playerAt(actions.guardTarget!).nightFacts.add(FactTag.guarded);
    }
    if (actions.wolfTarget != null) {
      state.playerAt(actions.wolfTarget!).nightFacts.add(FactTag.knifed);
    }
    if (actions.witchHealTarget != null) {
      state.playerAt(actions.witchHealTarget!).nightFacts.add(FactTag.healed);
      state.witchAntidoteAvailable = false;
    }
    if (actions.witchPoisonTarget != null) {
      state.playerAt(actions.witchPoisonTarget!).nightFacts.add(FactTag.poisoned);
      state.witchPoisonAvailable = false;
    }

    // 查驗結果記為資訊標記（不影響結算，供法官備忘與復盤）。
    if (outcome.seerTarget != null) {
      state
          .playerAt(outcome.seerTarget!)
          .infoTags
          .add(outcome.seerSawWolf ? InfoTag.verifiedWolf : InfoTag.verifiedGood);
    }

    for (final d in outcome.deaths) {
      state.playerAt(d.seat).alive = false;
    }

    state.lastGuardTarget = actions.guardTarget;
  }

  /// 守衛可否守 [seat]（不可連續兩晚守同一人）。
  bool guardMayProtect(GameState state, int seat) {
    if (!state.preset.rules.guardCannotRepeatTarget) return true;
    return state.lastGuardTarget != seat;
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
    if (actions.witchPoisonTarget == seat &&
        state.preset.rules.poisonedHunterCannotShoot) {
      return false;
    }
    return true;
  }
}
