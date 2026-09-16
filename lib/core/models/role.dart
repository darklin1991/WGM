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

  /// 狼美人：與狼隊相認、參與狼刀，之後另外睜眼魅惑一人。
  /// 自己出局（含被毒）時，被魅惑者殉情；但被騎士決鬥致死則技能不發動。
  static const wolfBeauty = Role(
    id: 'wolfBeauty',
    nameZh: '狼美人',
    camp: Camp.wolf,
    kind: RoleKind.wolf,
    nightPriority: 25,
  );

  /// 機械狼：**不與小狼相認**，所以夜晚單獨睜眼，不併入狼隊步驟。
  /// 可於任一晚學習一名玩家的身分技能（整局限一次），隔夜起生效；
  /// 開局不帶刀，其餘小狼全數出局後才獨自帶刀。不能自爆。
  static const mechanicWolf = Role(
    id: 'mechanicWolf',
    nameZh: '機械狼',
    camp: Camp.wolf,
    kind: RoleKind.wolf,
    nightPriority: 25,
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

  /// 通靈師：每晚查驗一名玩家的**真實身分**（不只好人／狼人），無次數限制。
  /// 在夜晚順序中站預言家的位置。
  static const psychic = Role(
    id: 'psychic',
    nameZh: '通靈師',
    camp: Camp.good,
    kind: RoleKind.god,
    nightPriority: 40,
  );

  /// 騎士：無夜間行動。白天投票前可翻牌與一人決鬥 ——
  /// 對方是狼則對方死亡並立即進入黑夜，對方是好人則騎士出局、白天繼續。
  static const knight = Role(
    id: 'knight',
    nameZh: '騎士',
    camp: Camp.good,
    kind: RoleKind.god,
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
    wolfBeauty,
    mechanicWolf,
    witch,
    seer,
    psychic,
    knight,
    hunter,
    idiot,
    villager,
  ];

  /// 夜晚會與狼隊一起睜眼、互相識別並共同決定狼刀的角色。
  ///
  /// **機械狼不在其中** —— 牠不與小狼相認，必須單獨睜眼。
  static const wolfTeamIds = <String>{'wolf', 'wolfKing', 'wolfBeauty'};

  /// 槍牌：死亡時可以開槍帶人的身分。機械狼學到這些才拿得到槍。
  static const gunRoleIds = <String>{'hunter', 'wolfKing'};

  static final Map<String, Role> _byId = {
    for (final r in all) r.id: r,
  };

  /// 依 id 取角色；找不到回傳 null（呼叫端負責產生錯誤訊息）。
  static Role? byId(String id) => _byId[id];
}
