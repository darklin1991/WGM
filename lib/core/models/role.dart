/// 陣營：好人 / 狼人。
enum Camp { good, wolf }

/// 角色類別。屠邊判定需要區分神職與平民，故不能只用陣營。
enum RoleKind { villager, god, wolf }

/// 單一角色定義。
class Role {
  const Role({
    required this.id,
    required this.nameZh,
    required this.camp,
    required this.kind,
    this.nightPriority,
  });

  /// 程式用識別碼，對應板子設定檔中的 `role` 欄位。
  final String id;

  /// 中文名稱，顯示用。
  final String nameZh;

  final Camp camp;
  final RoleKind kind;

  /// 夜晚行動優先級，數字小者先行動。
  /// null 表示沒有主動夜間行動（例如獵人、白痴、平民）。
  final int? nightPriority;

  /// 是否有主動夜間行動。
  bool get actsAtNight => nightPriority != null;

  @override
  String toString() => 'Role($id)';
}

/// 角色定義表。
///
/// 角色定義寫在程式碼、不放 JSON，因為每個角色都帶行為邏輯（夜間行動、
/// 死亡技能），純資料化沒有意義。設定檔驅動的部分是**板子**
/// （角色組合＋規則旗標），見 `assets/presets/`。
///
/// 夜晚行動優先級沿用一般賽制順序：守衛 → 狼人 → 女巫 → 預言家。
/// 實際順序仍以板子設定檔的 `nightOrder` 為準，此處的數字只用於
/// 沒有明確指定時的排序依據。
abstract final class Roles {
  static const guard = Role(
    id: 'guard',
    nameZh: '守衛',
    camp: Camp.good,
    kind: RoleKind.god,
    nightPriority: 10,
  );

  static const wolf = Role(
    id: 'wolf',
    nameZh: '狼人',
    camp: Camp.wolf,
    kind: RoleKind.wolf,
    nightPriority: 20,
  );

  /// 狼王：與狼人同時行動，出局時可開槍帶人。
  static const wolfKing = Role(
    id: 'wolfKing',
    nameZh: '狼王',
    camp: Camp.wolf,
    kind: RoleKind.wolf,
    nightPriority: 20,
  );

  static const witch = Role(
    id: 'witch',
    nameZh: '女巫',
    camp: Camp.good,
    kind: RoleKind.god,
    nightPriority: 30,
  );

  static const seer = Role(
    id: 'seer',
    nameZh: '預言家',
    camp: Camp.good,
    kind: RoleKind.god,
    nightPriority: 40,
  );

  /// 獵人：無夜間行動，死亡時觸發開槍（被毒死除外，依規則旗標）。
  static const hunter = Role(
    id: 'hunter',
    nameZh: '獵人',
    camp: Camp.good,
    kind: RoleKind.god,
  );

  /// 白痴：無夜間行動，被放逐時翻牌不死、失去投票權。
  static const idiot = Role(
    id: 'idiot',
    nameZh: '白痴',
    camp: Camp.good,
    kind: RoleKind.god,
  );

  static const villager = Role(
    id: 'villager',
    nameZh: '平民',
    camp: Camp.good,
    kind: RoleKind.villager,
  );

  static const all = <Role>[
    guard,
    wolf,
    wolfKing,
    witch,
    seer,
    hunter,
    idiot,
    villager,
  ];

  static final Map<String, Role> _byId = {
    for (final r in all) r.id: r,
  };

  /// 依 id 取角色；找不到回傳 null（呼叫端負責產生錯誤訊息）。
  static Role? byId(String id) => _byId[id];
}
