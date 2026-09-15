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

  /// 女巫解藥目標。一般等於 [wolfTarget]（女巫看到的是刀口）。
  int? witchHealTarget;

  /// 女巫毒藥目標。
  int? witchPoisonTarget;

  /// 預言家查驗的座次。
  int? seerTarget;

  bool get witchUsedAntidote => witchHealTarget != null;
  bool get witchUsedPoison => witchPoisonTarget != null;

  NightActions copy() => NightActions(night: night)
    ..guardTarget = guardTarget
    ..wolfTarget = wolfTarget
    ..witchHealTarget = witchHealTarget
    ..witchPoisonTarget = witchPoisonTarget
    ..seerTarget = seerTarget;
}

/// 死亡原因，用於復盤與獵人開槍判定。
enum DeathCause {
  wolfKill('狼刀'),
  poison('毒殺'),
  guardHealConflict('同守同救'),
  hunterShot('獵人開槍'),
  exile('放逐');

  const DeathCause(this.labelZh);

  final String labelZh;
}

/// 一名死者。
class Death {
  const Death({required this.seat, required this.cause});

  final int seat;
  final DeathCause cause;
}

/// 夜晚結算結果。
class NightOutcome {
  const NightOutcome({
    required this.deaths,
    required this.notes,
    required this.seerTarget,
    required this.seerSawWolf,
    required this.hunterMayShoot,
  });

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

  bool get isPeacefulNight => deaths.isEmpty;

  List<int> get deadSeats => deaths.map((d) => d.seat).toList();
}
