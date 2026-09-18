import '../rules/rule_flags.dart';
import 'preset_format_exception.dart';
import 'role.dart';

/// 板子中的一個角色欄位：某角色配置幾個。
class RoleSlot {
  const RoleSlot({required this.role, required this.count});

  final Role role;
  final int count;
}

/// 板子配置：人數＋角色組合＋夜晚順序＋規則旗標。
///
/// 由 `assets/presets/*.json` 載入。新增板子只需新增一份 JSON，
/// 不需改動程式碼。
class Preset {
  const Preset({
    required this.presetId,
    required this.name,
    required this.playerCount,
    required this.roles,
    required this.nightOrder,
    required this.rules,
  });

  final String presetId;
  final String name;
  final int playerCount;
  final List<RoleSlot> roles;

  /// 夜晚行動順序。只包含有主動夜間行動的角色。
  final List<Role> nightOrder;

  final RuleFlags rules;

  /// 解析並**驗證**設定檔。
  ///
  /// [sourceName] 是來源檔名，用於 presetId 本身就讀不到時的錯誤訊息。
  factory Preset.fromJson(
    Map<String, dynamic> json, {
    required String sourceName,
  }) {
    final presetId = json['presetId'] as String? ?? sourceName;

    final name = json['name'] as String?;
    if (name == null || name.isEmpty) {
      throw PresetFormatException(
        presetId: presetId,
        field: 'name',
        message: '必填，且不可為空字串',
      );
    }

    final playerCount = json['playerCount'];
    if (playerCount is! int || playerCount < 3) {
      throw PresetFormatException(
        presetId: presetId,
        field: 'playerCount',
        message: '必須是 3 以上的整數，實際為 $playerCount',
      );
    }

    final rawRoles = json['roles'];
    if (rawRoles is! List || rawRoles.isEmpty) {
      throw PresetFormatException(
        presetId: presetId,
        field: 'roles',
        message: '必須是非空陣列',
      );
    }

    final slots = <RoleSlot>[];
    for (var i = 0; i < rawRoles.length; i++) {
      final entry = rawRoles[i];
      if (entry is! Map) {
        throw PresetFormatException(
          presetId: presetId,
          field: 'roles[$i]',
          message: '必須是物件，格式為 { "role": "...", "count": n }',
        );
      }
      final roleId = entry['role'] as String?;
      final role = roleId == null ? null : Roles.byId(roleId);
      if (role == null) {
        throw PresetFormatException(
          presetId: presetId,
          field: 'roles[$i].role',
          message: '無法辨識的角色 "$roleId"，'
              '可用角色：${Roles.all.map((r) => r.id).join('、')}',
        );
      }
      final count = entry['count'];
      if (count is! int || count < 1) {
        throw PresetFormatException(
          presetId: presetId,
          field: 'roles[$i].count',
          message: '必須是正整數，實際為 $count',
        );
      }
      // 每個板子裡，一般狼與平民以外的身分只會有一位 —— 引擎依此假設
      // （`seatOfRole` 只回傳第一個），多填會讓第二位的技能直接消失。
      if (count != 1 && !role.allowsMultiple) {
        throw PresetFormatException(
          presetId: presetId,
          field: 'roles[$i].count',
          message: '${role.nameZh} 每個板子只能有 1 位，實際為 $count',
        );
      }
      slots.add(RoleSlot(role: role, count: count));
    }

    // 同一角色不可重複列出（否則單人限制會被繞過）。
    final seenIds = <String>{};
    for (var i = 0; i < slots.length; i++) {
      final id = slots[i].role.id;
      if (!seenIds.add(id)) {
        throw PresetFormatException(
          presetId: presetId,
          field: 'roles[$i].role',
          message: '角色 "$id" 重複列出，請合併成一筆',
        );
      }
    }

    // 驗證：角色數量總和必須等於人數。
    final total = slots.fold<int>(0, (sum, s) => sum + s.count);
    if (total != playerCount) {
      throw PresetFormatException(
        presetId: presetId,
        field: 'roles',
        message: '角色數量總和為 $total，與 playerCount ($playerCount) 不符',
      );
    }

    // 驗證：夜晚順序中的角色必須都出現在 roles 裡。
    final configuredIds = slots.map((s) => s.role.id).toSet();
    final rawOrder = json['nightOrder'];
    if (rawOrder is! List) {
      throw PresetFormatException(
        presetId: presetId,
        field: 'nightOrder',
        message: '必須是陣列',
      );
    }
    final order = <Role>[];
    for (var i = 0; i < rawOrder.length; i++) {
      final roleId = rawOrder[i] as String?;
      final role = roleId == null ? null : Roles.byId(roleId);
      if (role == null) {
        throw PresetFormatException(
          presetId: presetId,
          field: 'nightOrder[$i]',
          message: '無法辨識的角色 "$roleId"',
        );
      }
      if (!configuredIds.contains(role.id)) {
        throw PresetFormatException(
          presetId: presetId,
          field: 'nightOrder[$i]',
          message: '角色 "$roleId" 未出現在 roles 裡，無法排入夜晚順序',
        );
      }
      order.add(role);
    }

    // 驗證：有夜間行動的角色都必須排進 nightOrder。
    //
    // 漏掉的話流程產生器會把它默默接在最後，法官照著跑就會出錯 ——
    // 例如漏了女巫，獵人的開槍手勢會在毒還沒收之前就給出去。
    // 狼隊成員（狼王、狼美人）與一般狼合併成一步，只要狼隊有任一成員在
    // nightOrder 裡就算涵蓋。
    final orderIds = order.map((r) => r.id).toSet();
    final wolfTeamListed = orderIds.any(Roles.wolfTeamIds.contains);
    for (final slot in slots) {
      final role = slot.role;
      if (!role.actsAtNight) continue;
      final covered = orderIds.contains(role.id) ||
          (Roles.wolfTeamIds.contains(role.id) && wolfTeamListed);
      if (!covered) {
        throw PresetFormatException(
          presetId: presetId,
          field: 'nightOrder',
          message: '${role.nameZh}（${role.id}）有夜間行動，必須排進 nightOrder',
        );
      }
    }

    return Preset(
      presetId: presetId,
      name: name,
      playerCount: playerCount,
      roles: slots,
      nightOrder: order,
      rules: RuleFlags.fromJson(
        (json['rules'] as Map?)?.cast<String, dynamic>(),
        presetId: presetId,
        playerCount: playerCount,
      ),
    );
  }

  int _countOf(RoleKind kind) => roles
      .where((s) => s.role.kind == kind)
      .fold<int>(0, (sum, s) => sum + s.count);

  int get wolfCount => _countOf(RoleKind.wolf);
  int get godCount => _countOf(RoleKind.god);
  int get villagerCount => _countOf(RoleKind.villager);

  /// 角色組成摘要，例如「4狼 4神 4民」。
  String get composition => '$wolfCount狼 $godCount神 $villagerCount民';

  /// 神職角色的中文名稱清單，顯示用。
  List<String> get godNames => roles
      .where((s) => s.role.kind == RoleKind.god)
      .map((s) => s.count > 1 ? '${s.role.nameZh}×${s.count}' : s.role.nameZh)
      .toList();

  /// 依板子設定展開成一份完整身分牌堆（長度等於 playerCount）。
  List<Role> buildRoleDeck() => [
        for (final slot in roles)
          for (var i = 0; i < slot.count; i++) slot.role,
      ];
}
