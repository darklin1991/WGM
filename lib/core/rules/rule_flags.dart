import '../models/preset_format_exception.dart';

/// 平票處理方式。
enum TieBreak {
  /// 平票者發言後重投，仍平票則無人出局。
  pkThenNone('pk_then_none', '平票 PK，再平票則無人出局'),

  /// 平票者發言後重投，平票者本身不投。
  pkThenRevote('pk_then_revote', '平票 PK 後重投（平票者不投）'),

  /// 直接無人出局。
  none('none', '平票直接無人出局');

  const TieBreak(this.jsonValue, this.labelZh);

  final String jsonValue;
  final String labelZh;

  static TieBreak? fromJson(String value) {
    for (final v in values) {
      if (v.jsonValue == value) return v;
    }
    return null;
  }
}

/// 勝負判定方式。
enum WinCondition {
  /// 屠邊：神職全滅 **或** 平民全滅即狼人勝。
  sideElimination('sideElimination', '屠邊'),

  /// 屠城：所有好人全滅才算狼人勝。
  totalElimination('totalElimination', '屠城');

  const WinCondition(this.jsonValue, this.labelZh);

  final String jsonValue;
  final String labelZh;

  static WinCondition? fromJson(String value) {
    for (final v in values) {
      if (v.jsonValue == value) return v;
    }
    return null;
  }
}

/// 規則變體旗標。
///
/// 所有規則差異集中在此，引擎讀旗標決策，不要把
/// 「同守同救是否致死」這類判斷散落到各處。
class RuleFlags {
  const RuleFlags({
    this.guardHealKills = true,
    this.witchSelfHealNight = 0,
    this.witchDualUseSameNight = false,
    this.guardCannotRepeatTarget = true,
    this.poisonedHunterCannotShoot = true,
    this.sheriffVoteWeight = 1.5,
    this.tieBreak = TieBreak.pkThenNone,
    this.winCondition = WinCondition.sideElimination,
    this.wolfSelfDetonateEndsDay = true,
    this.charmCannotRepeatTarget = true,
    this.wolfBeautyCannotSelfKill = true,
    this.knightDuelBlocksCharmSuicide = true,
    this.knightDuelEndsDay = true,
    this.mechanicGuardReflectsPoison = true,
    this.mechanicDoubleKnifeBreaksShield = true,
    this.sheriffElection = true,
    this.speechSeconds = 120,
  });

  /// 每位玩家的發言額度（秒）。預設 2 分鐘。
  ///
  /// 這是**建議值**，不是硬性限制 —— 計時頁上法官隨時可以改，時間到了也
  /// 只是提示，不會強制中斷。警上發言、白天發言、平票 PK 發言與遺言
  /// 共用同一個額度。
  final int speechSeconds;

  /// 本局是否有警長競選（警長局）。
  ///
  /// 關掉的話第一天直接公布死訊，不跑上警流程。
  final bool sheriffElection;

  /// 機械狼（學到守衛）的守護是否會把毒藥**反彈給下毒的人**。
  ///
  /// 這是機械狼版守衛比一般守衛強的地方 —— 一般守衛防不了毒。
  final bool mechanicGuardReflectsPoison;

  /// 機械狼（學到狼人）雙刀集中同一人時，是否破盾。
  ///
  /// 破盾會讓**守衛的守護與女巫的解藥都失效**，目標必死；
  /// 因此也不會構成同守同救。
  final bool mechanicDoubleKnifeBreaksShield;

  /// 狼美人是否不可連續兩晚魅惑同一人（應在輸入階段就擋住）。
  final bool charmCannotRepeatTarget;

  /// 狼美人是否不能自刀（狼隊不可把刀指向狼美人自己）。
  final bool wolfBeautyCannotSelfKill;

  /// 狼美人被騎士決鬥致死時，殉情是否不發動。
  ///
  /// 多數賽制為 true —— 騎士決鬥掉狼美人可以救下被魅惑者。
  final bool knightDuelBlocksCharmSuicide;

  /// 騎士決鬥到狼人後，是否立即結束白天進入黑夜（跳過投票）。
  ///
  /// 決鬥到好人時騎士出局，白天照常繼續，不受此旗標影響。
  final bool knightDuelEndsDay;

  /// 同守同救（奶穿）是否致死。true 為多數賽制。
  final bool guardHealKills;

  /// 女巫可自救的夜次：0 不可、1 僅首夜、-1 不限。
  ///
  /// 未在板子設定檔指定時，依人數由 [defaultWitchSelfHealNight] 推導。
  final int witchSelfHealNight;

  /// 女巫自救的預設規則：**9 人以上不可自救**；8 人以下的小局僅首夜可自救。
  ///
  /// 這是依人數決定的通則，所以做成推導而不是寫死在每份設定檔裡 ——
  /// 新增板子時不必記得填這個欄位。個別板子若採用不同賽制，
  /// 仍可在 `rules.witchSelfHealNight` 明確覆寫。
  static int defaultWitchSelfHealNight(int playerCount) =>
      playerCount >= 9 ? 0 : 1;

  /// 同一夜是否可同時使用解藥與毒藥。
  final bool witchDualUseSameNight;

  /// 守衛是否不可連續兩晚守同一人（應在輸入階段就擋住）。
  final bool guardCannotRepeatTarget;

  /// 獵人被毒死是否不可開槍。
  final bool poisonedHunterCannotShoot;

  /// 警長票權重。
  final double sheriffVoteWeight;

  final TieBreak tieBreak;
  final WinCondition winCondition;

  /// 自爆是否立即結束白天、跳過投票進入夜晚。
  final bool wolfSelfDetonateEndsDay;

  /// 從板子設定檔的 `rules` 區塊解析。
  ///
  /// [presetId] 只用於組出可辨識的錯誤訊息。
  factory RuleFlags.fromJson(
    Map<String, dynamic>? json, {
    required String presetId,
    required int playerCount,
  }) {
    final selfHealDefault = defaultWitchSelfHealNight(playerCount);
    if (json == null) {
      return RuleFlags(witchSelfHealNight: selfHealDefault);
    }

    const defaults = RuleFlags();

    bool readBool(String key, bool fallback) {
      final v = json[key];
      if (v == null) return fallback;
      if (v is! bool) {
        throw PresetFormatException(
          presetId: presetId,
          field: 'rules.$key',
          message: '必須是 true 或 false，實際為 $v',
        );
      }
      return v;
    }

    final selfHeal = json['witchSelfHealNight'] ?? selfHealDefault;
    if (selfHeal is! int || selfHeal < -1) {
      throw PresetFormatException(
        presetId: presetId,
        field: 'rules.witchSelfHealNight',
        message: '必須是 -1（不限）、0（不可）或正整數夜次，實際為 $selfHeal',
      );
    }

    final weight = json['sheriffVoteWeight'] ?? defaults.sheriffVoteWeight;
    if (weight is! num || weight < 0) {
      throw PresetFormatException(
        presetId: presetId,
        field: 'rules.sheriffVoteWeight',
        message: '必須是 0 或正數，實際為 $weight',
      );
    }

    final speech = json['speechSeconds'] ?? defaults.speechSeconds;
    if (speech is! int || speech <= 0) {
      throw PresetFormatException(
        presetId: presetId,
        field: 'rules.speechSeconds',
        message: '必須是正整數秒數，實際為 $speech',
      );
    }

    final tieRaw = json['tieBreak'] as String? ?? defaults.tieBreak.jsonValue;
    final tie = TieBreak.fromJson(tieRaw);
    if (tie == null) {
      throw PresetFormatException(
        presetId: presetId,
        field: 'rules.tieBreak',
        message: '無法辨識的值 "$tieRaw"，'
            '可用值：${TieBreak.values.map((e) => e.jsonValue).join('、')}',
      );
    }

    final winRaw =
        json['winCondition'] as String? ?? defaults.winCondition.jsonValue;
    final win = WinCondition.fromJson(winRaw);
    if (win == null) {
      throw PresetFormatException(
        presetId: presetId,
        field: 'rules.winCondition',
        message: '無法辨識的值 "$winRaw"，'
            '可用值：${WinCondition.values.map((e) => e.jsonValue).join('、')}',
      );
    }

    return RuleFlags(
      guardHealKills: readBool('guardHealKills', defaults.guardHealKills),
      witchSelfHealNight: selfHeal,
      witchDualUseSameNight:
          readBool('witchDualUseSameNight', defaults.witchDualUseSameNight),
      guardCannotRepeatTarget:
          readBool('guardCannotRepeatTarget', defaults.guardCannotRepeatTarget),
      poisonedHunterCannotShoot: readBool(
        'poisonedHunterCannotShoot',
        defaults.poisonedHunterCannotShoot,
      ),
      sheriffVoteWeight: weight.toDouble(),
      tieBreak: tie,
      winCondition: win,
      wolfSelfDetonateEndsDay: readBool(
        'wolfSelfDetonateEndsDay',
        defaults.wolfSelfDetonateEndsDay,
      ),
      charmCannotRepeatTarget:
          readBool('charmCannotRepeatTarget', defaults.charmCannotRepeatTarget),
      wolfBeautyCannotSelfKill:
          readBool('wolfBeautyCannotSelfKill', defaults.wolfBeautyCannotSelfKill),
      knightDuelBlocksCharmSuicide: readBool(
        'knightDuelBlocksCharmSuicide',
        defaults.knightDuelBlocksCharmSuicide,
      ),
      knightDuelEndsDay:
          readBool('knightDuelEndsDay', defaults.knightDuelEndsDay),
      mechanicGuardReflectsPoison: readBool(
        'mechanicGuardReflectsPoison',
        defaults.mechanicGuardReflectsPoison,
      ),
      mechanicDoubleKnifeBreaksShield: readBool(
        'mechanicDoubleKnifeBreaksShield',
        defaults.mechanicDoubleKnifeBreaksShield,
      ),
      sheriffElection: readBool('sheriffElection', defaults.sheriffElection),
      speechSeconds: speech,
    );
  }

  /// 女巫在第 [night] 夜（首夜為 1）是否可自救。
  bool witchMaySelfHeal(int night) {
    if (witchSelfHealNight < 0) return true;
    if (witchSelfHealNight == 0) return false;
    return night <= witchSelfHealNight;
  }
}
