import 'role.dart';

/// 一個夜晚收集到的所有行動意圖。
///
/// **只記錄意圖，不做判定。**衝突裁決（同守同救、毒穿守等）全部留到
/// 結算階段一次性套用，因為規則需要全局資訊。
class NightActions {
  NightActions({required this.night});

  /// 第幾夜，首夜為 1。
  final int night;

  /// 守衛守護的座次。
  int? guardTarget;

  /// 狼刀的座次。null 表示空刀。
  int? wolfTarget;

  /// 第二刀 —— 只有在機械狼學到狼人時才會用到。
  ///
  /// 與 [wolfTarget] **指向同一人時會破盾**（守衛的守護失效），
  /// 指向不同人則兩刀各自結算。
  int? wolfSecondTarget;

  /// 本夜所有刀口（可能有兩刀；同一人被砍兩次會出現兩次）。
  List<int> get wolfTargets => [?wolfTarget, ?wolfSecondTarget];

  /// 女巫解藥目標。一般等於 [wolfTarget]（女巫看到的是刀口）。
  int? witchHealTarget;

  /// 女巫毒藥目標。
  int? witchPoisonTarget;

  /// 預言家查驗的座次。
  int? seerTarget;

  /// 通靈師查驗的座次（查到的是真實身分，不只好人／狼人）。
  int? psychicTarget;

  /// 狼美人魅惑的座次。狼美人出局時，被魅惑者殉情。
  int? wolfBeautyCharmTarget;

  /// 機械狼本晚要學習誰的身分技能。整局限一次，隔夜起生效。
  int? mechanicWolfLearnTarget;

  // ---- 機械狼學到技能後的行動 ----
  //
  // 機械狼學到的技能與原角色**各自獨立**（例如原守衛與機械狼可以守不同人、
  // 機械狼學到女巫時另有自己的一瓶解藥與毒藥），所以不共用上面的欄位。

  /// 機械狼（學到守衛）守護的座次。
  ///
  /// 這道守護比一般守衛強：擋得住狼刀，**也能把毒藥反彈給下毒的人**。
  int? mechanicGuardTarget;

  /// 機械狼（學到預言家或通靈師）查驗的座次。
  int? mechanicInspectTarget;

  /// 機械狼（學到女巫）毒藥目標。
  ///
  /// 機械狼學到女巫**只拿得到毒藥，沒有解藥**，所以沒有對應的解藥欄位。
  int? mechanicPoisonTarget;

  /// 機械狼（學到狼美人）魅惑的座次。
  int? mechanicCharmTarget;

  bool get witchUsedAntidote => witchHealTarget != null;
  bool get witchUsedPoison => witchPoisonTarget != null;

  NightActions copy() => NightActions(night: night)
    ..guardTarget = guardTarget
    ..wolfTarget = wolfTarget
    ..wolfSecondTarget = wolfSecondTarget
    ..witchHealTarget = witchHealTarget
    ..witchPoisonTarget = witchPoisonTarget
    ..seerTarget = seerTarget
    ..psychicTarget = psychicTarget
    ..wolfBeautyCharmTarget = wolfBeautyCharmTarget
    ..mechanicWolfLearnTarget = mechanicWolfLearnTarget
    ..mechanicGuardTarget = mechanicGuardTarget
    ..mechanicInspectTarget = mechanicInspectTarget
    ..mechanicPoisonTarget = mechanicPoisonTarget
    ..mechanicCharmTarget = mechanicCharmTarget;
}

/// 死亡原因，用於復盤與獵人開槍判定。
enum DeathCause {
  wolfKill('狼刀'),
  poison('毒殺'),
  guardHealConflict('同守同救'),
  hunterShot('獵人開槍'),
  exile('放逐'),

  /// 殉情：狼美人出局，被魅惑者隨之死亡。
  loveSuicide('殉情'),

  /// 騎士決鬥致死（決鬥到狼，或騎士決鬥到好人而自刎）。
  knightDuel('騎士決鬥');

  const DeathCause(this.labelZh);

  final String labelZh;
}

/// 一名死者。
class Death {
  const Death({required this.seat, required this.cause});

  final int seat;
  final DeathCause cause;
}

/// 通靈師查驗結果：真實身分，不只好人／狼人。
class PsychicResult {
  const PsychicResult({required this.seat, required this.revealedRole});

  final int seat;

  /// 查到的真實身分。座次尚未登記身分時為 null。
  final Role? revealedRole;
}

/// 夜晚結算結果。
class NightOutcome {
  const NightOutcome({
    required this.deaths,
    required this.notes,
    required this.seerTarget,
    required this.seerSawWolf,
    required this.hunterMayShoot,
    this.wolfKingMayShoot = false,
    this.psychicResult,
    this.mechanicLearnedRole,
    this.mechanicSeerTarget,
    this.mechanicSeerSawWolf = false,
    this.mechanicPsychicResult,
    this.charmSuicideSeat,
    this.poisonReflectedTo,
    this.shieldBrokenSeats = const <int>[],
  });

  /// 通靈師查驗結果，null 表示本夜未查驗（或板子沒有通靈師）。
  final PsychicResult? psychicResult;

  /// 機械狼本夜學到的身分，null 表示沒學（或已學過）。
  final Role? mechanicLearnedRole;

  /// 機械狼（學到預言家）本夜查驗的座次。
  final int? mechanicSeerTarget;

  /// 機械狼（學到預言家）的查驗結果是否為狼。
  final bool mechanicSeerSawWolf;

  /// 機械狼（學到通靈師）本夜的查驗結果。
  final PsychicResult? mechanicPsychicResult;

  /// 本夜因狼美人出局而殉情的座次，null 表示沒有殉情。
  final int? charmSuicideSeat;

  /// 毒藥被機械狼的守護反彈，改為毒死的座次（下毒者）。null 表示沒有反彈。
  final int? poisonReflectedTo;

  /// 被雙刀集中而破盾的座次 —— 守衛的守護與女巫的解藥都被打穿。
  final List<int> shieldBrokenSeats;

  /// 死者，依座次排序。空陣列表示平安夜。
  final List<Death> deaths;

  /// 裁決說明，供法官核對與復盤，例如「3 號同守同救，仍然死亡」。
  final List<String> notes;

  /// 預言家查驗的座次，null 表示本夜未查驗。
  final int? seerTarget;

  /// 查驗結果是否為狼（查殺）。[seerTarget] 為 null 時無意義。
  final bool seerSawWolf;

  /// 獵人是否可以開槍。只有獵人本夜死亡且規則允許時才為 true。
  final bool hunterMayShoot;

  /// 狼王是否可以開槍。
  ///
  /// 狼王的條件與獵人不同：**被自刀出局才能開槍**（就算同時吃毒也能開），
  /// 沒被自刀而死就一定是被毒，不能開。狼隊自己知道有沒有自刀，
  /// 所以狼王不需要每晚給手勢，白天起來直接發動。
  final bool wolfKingMayShoot;

  bool get isPeacefulNight => deaths.isEmpty;

  List<int> get deadSeats => deaths.map((d) => d.seat).toList();
}
