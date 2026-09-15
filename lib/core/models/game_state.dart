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
        );

  GameState._({
    required this.preset,
    required this.players,
    required this.dayNumber,
    required this.phase,
    required this.sheriffSeat,
    required this.witchAntidoteAvailable,
    required this.witchPoisonAvailable,
    required this.lastGuardTarget,
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
      );
}
