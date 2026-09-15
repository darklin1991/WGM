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
      slots.add(RoleSlot(role: role, count: count));
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
