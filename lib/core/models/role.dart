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

  /// 是否有主動夜間行動 —— 有的話**必須**出現在板子的 `nightOrder` 裡。
  bool get actsAtNight => nightPriority != null;

  /// 一個板子裡是否允許多於一人。
  ///
  /// 只有一般狼與平民可以多人；其餘身分每個板子只會有一位，
  /// 引擎也依此假設（`GameState.seatOfRole` 只回傳第一個）。
  bool get allowsMultiple =>
      id == 'wolf' || id == 'villager' || id == 'awakenedGargoyle';

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

  /// 覺醒石像鬼：狼隊主刀，**只有首夜**可以轉換一位相鄰座次的玩家。
  ///
  /// 兩隻互認、一起決定狼刀（就是一般的狼隊步驟）。覺醒版**沒有查驗**——
  /// 原本石像鬼的「查真實身分」換成了轉換。
  static const awakenedGargoyle = Role(
    id: 'awakenedGargoyle',
    nameZh: '覺醒石像鬼',
    camp: Camp.wolf,
    kind: RoleKind.wolf,
    nightPriority: 10,
  );

  /// 白貓：任何原因出局時翻牌，並**多活到下一次放逐投票結束**才真正離場。
  ///
  /// 延後期間**算存活** —— 有投票權、可以發言、勝負判定也算他活著
  /// （擔當 2026-09-22 指定）。所以實作上是把死亡整個延後，
  /// 不做「已死但還在場」的中間狀態。
  static const whiteCat = Role(
    id: 'whiteCat',
    nameZh: '白貓',
    camp: Camp.good,
    kind: RoleKind.god,
  );

  /// 攝夢人：每晚指定一名夢遊者。
  ///
  /// 夢遊者**免疫夜間傷害**（連女巫的毒都擋，比守衛強一截），且不知道自己在夢遊。
  /// **連續兩晚被攝的人會死**，死因是夢死，擋不住也不能開槍。
  /// 攝夢人夜裡出局時，當晚的夢遊者一併死亡。
  static const dreamWeaver = Role(
    id: 'dreamWeaver',
    nameZh: '攝夢人',
    camp: Camp.good,
    kind: RoleKind.god,
    nightPriority: 2,
  );

  /// 熊：每晚查看**左右兩位鄰座**，其中有狼就咆哮。
  ///
  /// 法官給的是**是／否**，不是告訴他哪一位 —— 所以這一步沒有目標要選，
  /// 與獵人的開槍手勢同型。鄰座死亡時**往外順延**，取的是環狀座次上
  /// 最近的兩位存活玩家。
  static const bear = Role(
    id: 'bear',
    nameZh: '熊',
    camp: Camp.good,
    kind: RoleKind.god,
    nightPriority: 6,
  );

  /// 河豚：無夜間行動。**被放逐時**可主動翻牌，帶走所有這一輪投他的人。
  ///
  /// 帶走的人**不能開槍**（擔當 2026-09-23 指定）—— 與騎士決鬥同理，
  /// 死因既不是刀也不是推。
  static const pufferfish = Role(
    id: 'pufferfish',
    nameZh: '河豚',
    camp: Camp.good,
    kind: RoleKind.god,
  );

  /// 暗戀者：首夜選一名暗戀對象，**勝負跟著對象的陣營走**，雙方都不知情。
  ///
  /// **本人永遠算好人**（擔當 2026-09-22 指定）—— 預言家查他是金水，
  /// 屠邊也算神職人頭。跟著對象走的只有「誰贏」這一件事，見 `WinChecker`。
  ///
  /// 只有首夜行動，之後不再叫起來。
  static const secretAdmirer = Role(
    id: 'secretAdmirer',
    nameZh: '暗戀者',
    camp: Camp.good,
    kind: RoleKind.god,
    nightPriority: 5,
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
    awakenedGargoyle,
    mechanicWolf,
    witch,
    seer,
    psychic,
    knight,
    hunter,
    idiot,
    whiteCat,
    dreamWeaver,
    bear,
    pufferfish,
    secretAdmirer,
    villager,
  ];

  /// 夜晚會與狼隊一起睜眼、互相識別並共同決定狼刀的角色。
  ///
  /// **機械狼不在其中** —— 牠不與小狼相認，必須單獨睜眼。
  /// 覺醒石像鬼也在其中 —— 牠們互認、一起決定狼刀，就是這個板子的狼隊。
  /// 連帶讓機械狼的帶刀條件自動變成「兩隻石像鬼都出局」。
  static const wolfTeamIds = <String>{
    'wolf',
    'wolfKing',
    'wolfBeauty',
    'awakenedGargoyle',
  };

  /// 槍牌：死亡時可以開槍帶人的身分。機械狼學到這些才拿得到槍。
  static const gunRoleIds = <String>{'hunter', 'wolfKing'};

  static final Map<String, Role> _byId = {
    for (final r in all) r.id: r,
  };

  /// 依 id 取角色；找不到回傳 null（呼叫端負責產生錯誤訊息）。
  static Role? byId(String id) => _byId[id];
}
