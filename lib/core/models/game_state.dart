import '../log/game_log.dart';
import 'player.dart';
import 'preset.dart';
import 'role.dart';

/// 遊戲階段。
enum GamePhase {
  /// 開局配置：登記玩家身分、座次。
  setup('配置'),

  /// 夜晚：依 nightOrder 收集行動後結算。
  night('夜晚'),

  /// 白天：競選、發言、投票。
  day('白天'),

  /// 已結束。
  ended('結束');

  const GamePhase(this.labelZh);

  final String labelZh;
}

/// 完整局面狀態。
///
/// 依擔當決定採「狀態直接修改」，此類別為可變物件，不使用事件溯源。
/// 因此：
/// - 復盤紀錄要在修改狀態的同一處另外寫入 log
/// - 撤銷靠 [copy] 產生的深拷貝快照
class GameState {
  GameState({required this.preset})
      : players = List.generate(
          preset.playerCount,
          (i) => Player(seat: i + 1),
          growable: false,
        ),
        log = GameLog();

  GameState._({
    required this.preset,
    required this.players,
    required this.dayNumber,
    required this.phase,
    required this.sheriffSeat,
    required this.witchAntidoteAvailable,
    required this.witchPoisonAvailable,
    required this.lastGuardTarget,
    required this.charmedSeat,
    required this.lastCharmTarget,
    required this.mechanicWolfLearnedRole,
    required this.mechanicWolfLearnedNight,
    required this.mechanicPoisonAvailable,
    required this.lastMechanicGuardTarget,
    required this.mechanicCharmedSeat,
    required this.lastMechanicCharmTarget,
    required this.knightDuelUsed,
    required this.log,
  });

  final Preset preset;

  /// 依座次排列，索引 0 為 1 號。
  final List<Player> players;

  /// 目前第幾天／第幾夜，開局為 0，首夜為 1。
  int dayNumber = 0;

  GamePhase phase = GamePhase.setup;

  /// 警長座次，null 表示尚無警長（或警徽已撕）。
  int? sheriffSeat;

  /// 女巫解藥是否還在（整局限一次）。
  bool witchAntidoteAvailable = true;

  /// 女巫毒藥是否還在（整局限一次）。
  bool witchPoisonAvailable = true;

  /// 守衛前一晚守的座次，用於「不可連守同一人」的檢查。
  int? lastGuardTarget;

  // ---- 狼美人 ----

  /// 昨晚被狼美人魅惑的座次。狼美人出局時，這位殉情。
  ///
  /// **每晚重設** —— 狼美人沒選就是沒魅惑，不會沿用前一晚的對象。
  /// 留著這個欄位是給白天用的：狼美人被放逐或被騎士決鬥掉時，
  /// 殉情的對象就是昨晚指定的那位。
  int? charmedSeat;

  /// 狼美人前一晚魅惑的座次，用於「不可連續兩晚魅惑同一人」的檢查。
  int? lastCharmTarget;

  // ---- 機械狼 ----
  //
  // 機械狼整局只能學一次，且**隔夜起**才取得技能。學到的技能與原角色
  // 各自獨立，所以藥量、守護紀錄都另外記。

  /// 機械狼學到的身分，null 表示還沒學。
  Role? mechanicWolfLearnedRole;

  /// 機械狼是第幾夜學的（首夜為 1）。技能自 `learnedNight + 1` 夜起生效。
  int? mechanicWolfLearnedNight;

  /// 機械狼（學到女巫）的毒藥是否還在。
  ///
  /// 機械狼學到女巫**只拿得到毒藥，沒有解藥**，所以沒有對應的解藥欄位。
  bool mechanicPoisonAvailable = true;

  /// 機械狼（學到守衛）前一晚守的座次。
  int? lastMechanicGuardTarget;

  /// 機械狼（學到狼美人）目前魅惑的座次。
  int? mechanicCharmedSeat;

  /// 機械狼（學到狼美人）前一晚魅惑的座次。
  int? lastMechanicCharmTarget;

  // ---- 騎士 ----

  /// 騎士是否已經翻牌決鬥過。**整局只能決鬥一次**（擔當 2026-09-19 指定），
  /// 所以決鬥完就算活下來也不能再發動。
  bool knightDuelUsed = false;

  /// 復盤日誌。**只寫入，不用來推導狀態** —— 局面的真相在這個物件的其他
  /// 欄位裡，這份只是給人看的。撤銷會連它一起退回去。
  final GameLog log;

  /// 機械狼在第 [night] 夜是否已能使用學到的技能。
  ///
  /// 學習當晚不生效 —— 規則是「隔夜起獲得對應技能」。
  bool mechanicSkillActiveOn(int night) {
    final learnedNight = mechanicWolfLearnedNight;
    if (mechanicWolfLearnedRole == null || learnedNight == null) return false;
    return night > learnedNight;
  }

  /// 機械狼（學到狼人）在第 [night] 夜是否能多砍一刀。
  ///
  /// 三個條件缺一不可：
  /// 1. 學到的是狼人，且技能已生效（學習當晚不算）
  /// 2. **已經帶刀** —— 機械狼要等其餘小狼全數出局才開得了刀，
  ///    小狼還活著時牠根本沒有刀，也就談不上「多砍一刀」
  /// 3. 機械狼本人還活著
  bool mechanicHasExtraKnifeOn(int night) {
    if (mechanicWolfLearnedRole?.id != Roles.wolf.id) return false;
    if (!mechanicSkillActiveOn(night)) return false;
    if (!mechanicWolfCarriesKnife) return false;
    final seat = seatOfRole(Roles.mechanicWolf.id);
    return seat != null && playerAt(seat).alive;
  }

  /// 機械狼是否已經獨自帶刀 —— 其餘小狼（含狼王、狼美人）全數出局時才成立。
  ///
  /// 板子裡沒有機械狼時回傳 false。
  ///
  /// **狼隊還沒登記完時一律回傳 false。** 首夜機械狼第一個睜眼，那時小狼的
  /// 身分都還沒登記，光看「場上有沒有活著的狼隊成員」會誤判成狼隊全滅，
  /// 機械狼首夜就拿到刀。
  bool get mechanicWolfCarriesKnife {
    if (seatOfRole(Roles.mechanicWolf.id) == null) return false;

    final configured = preset.roles
        .where((s) => Roles.wolfTeamIds.contains(s.role.id))
        .fold<int>(0, (sum, s) => sum + s.count);
    final registered = players
        .where((p) => p.role != null && Roles.wolfTeamIds.contains(p.role!.id))
        .length;
    if (registered < configured) return false;

    return !players.any(
      (p) =>
          p.alive &&
          p.role != null &&
          Roles.wolfTeamIds.contains(p.role!.id),
    );
  }

  Player playerAt(int seat) => players[seat - 1];

  Iterable<Player> get alivePlayers => players.where((p) => p.alive);

  int get aliveCount => alivePlayers.length;

  int aliveCountOfKind(RoleKind kind) =>
      alivePlayers.where((p) => p.role?.kind == kind).length;

  int get aliveWolfCount => aliveCountOfKind(RoleKind.wolf);
  int get aliveGodCount => aliveCountOfKind(RoleKind.god);
  int get aliveVillagerCount => aliveCountOfKind(RoleKind.villager);

  /// 是否所有玩家都已登記身分 —— 開始遊戲的前提。
  bool get allRolesAssigned => players.every((p) => p.role != null);

  /// 尚未登記身分的座次。
  List<int> get unassignedSeats =>
      players.where((p) => p.role == null).map((p) => p.seat).toList();

  /// 各角色已登記的數量，用於檢查是否符合板子配置。
  Map<String, int> get assignedRoleCounts {
    final counts = <String, int>{};
    for (final p in players) {
      final id = p.role?.id;
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// 已登記的身分是否與板子配置完全相符。
  bool get assignmentMatchesPreset {
    final assigned = assignedRoleCounts;
    for (final slot in preset.roles) {
      if ((assigned[slot.role.id] ?? 0) != slot.count) return false;
    }
    return assigned.length == preset.roles.length;
  }

  /// 某角色還可登記幾位（負數表示超額）。
  int remainingQuotaFor(Role role) {
    final quota = preset.roles
        .where((s) => s.role.id == role.id)
        .fold<int>(0, (sum, s) => sum + s.count);
    return quota - (assignedRoleCounts[role.id] ?? 0);
  }

  /// 座次是**環狀**的：回傳從 [fromSeat] 起、依 [clockwise] 方向的下一個
  /// 存活座次。全場皆死時回傳 null。
  int? nextAliveSeat(int fromSeat, {bool clockwise = true}) {
    final n = players.length;
    for (var step = 1; step <= n; step++) {
      final offset = clockwise ? step : -step;
      final seat = ((fromSeat - 1 + offset) % n + n) % n + 1;
      if (playerAt(seat).alive) return seat;
    }
    return null;
  }

  /// 把所有尚未指定身分的座次填為平民。
  ///
  /// 首夜依身分逐一登記後，剩下的就是平民 —— 法官不必逐一點選。
  List<int> assignRemainingAsVillager() {
    final filled = <int>[];
    for (final p in players) {
      if (p.role == null) {
        p.role = Roles.villager;
        filled.add(p.seat);
      }
    }
    return filled;
  }

  /// 依身分找座次；找不到回傳 null。
  int? seatOfRole(String roleId) {
    for (final p in players) {
      if (p.role?.id == roleId) return p.seat;
    }
    return null;
  }

  /// 依身分找所有座次（狼隊等多人角色用）。
  List<int> seatsOfRole(String roleId) =>
      players.where((p) => p.role?.id == roleId).map((p) => p.seat).toList();

  /// 從快照就地還原（撤銷用）。
  ///
  /// **新增欄位時必須同步修改這裡與 [copy]** —— 漏一個欄位撤銷就會留下殘影。
  ///
  /// 刻意不換物件：頁面、狀態機到處持有同一個 [GameState] 參照，
  /// 就地覆寫才不必把參照全部重新接一遍。[preset] 是不可變設定，不必還原。
  void restoreFrom(GameState snapshot) {
    for (var i = 0; i < players.length; i++) {
      players[i].restoreFrom(snapshot.players[i]);
    }
    dayNumber = snapshot.dayNumber;
    phase = snapshot.phase;
    sheriffSeat = snapshot.sheriffSeat;
    witchAntidoteAvailable = snapshot.witchAntidoteAvailable;
    witchPoisonAvailable = snapshot.witchPoisonAvailable;
    lastGuardTarget = snapshot.lastGuardTarget;
    charmedSeat = snapshot.charmedSeat;
    lastCharmTarget = snapshot.lastCharmTarget;
    mechanicWolfLearnedRole = snapshot.mechanicWolfLearnedRole;
    mechanicWolfLearnedNight = snapshot.mechanicWolfLearnedNight;
    mechanicPoisonAvailable = snapshot.mechanicPoisonAvailable;
    lastMechanicGuardTarget = snapshot.lastMechanicGuardTarget;
    mechanicCharmedSeat = snapshot.mechanicCharmedSeat;
    lastMechanicCharmTarget = snapshot.lastMechanicCharmTarget;
    knightDuelUsed = snapshot.knightDuelUsed;
    log.restoreFrom(snapshot.log);
  }

  /// 深拷貝快照，供撤銷使用。
  ///
  /// [preset] 為不可變設定，直接共用參考即可。
  /// **新增欄位時務必同步修改這裡**，漏一個欄位撤銷就會出現詭異狀態。
  GameState copy() => GameState._(
        preset: preset,
        players: players.map((p) => p.copy()).toList(growable: false),
        dayNumber: dayNumber,
        phase: phase,
        sheriffSeat: sheriffSeat,
        witchAntidoteAvailable: witchAntidoteAvailable,
        witchPoisonAvailable: witchPoisonAvailable,
        lastGuardTarget: lastGuardTarget,
        charmedSeat: charmedSeat,
        lastCharmTarget: lastCharmTarget,
        mechanicWolfLearnedRole: mechanicWolfLearnedRole,
        mechanicWolfLearnedNight: mechanicWolfLearnedNight,
        mechanicPoisonAvailable: mechanicPoisonAvailable,
        lastMechanicGuardTarget: lastMechanicGuardTarget,
        mechanicCharmedSeat: mechanicCharmedSeat,
        lastMechanicCharmTarget: lastMechanicCharmTarget,
        knightDuelUsed: knightDuelUsed,
        log: log.copy(),
      );
}
