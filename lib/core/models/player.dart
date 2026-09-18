import 'role.dart';

/// 事實標記：引擎結算用，每晚重算。
enum FactTag {
  guarded('被守'),
  knifed('被刀'),
  healed('被救'),
  poisoned('被毒'),
  shot('被槍'),
  exiled('被放逐');

  const FactTag(this.labelZh);

  final String labelZh;
}

/// 資訊標記：法官備忘與復盤用，**不影響結算**。
enum InfoTag {
  verifiedGood('金水'),
  verifiedWolf('查殺'),
  silenced('禁言');

  const InfoTag(this.labelZh);

  final String labelZh;
}

/// 一位玩家。
///
/// 依「狀態直接修改」的架構決定，此類別為可變物件；撤銷功能靠
/// `undo_stack` 的深拷貝快照，因此新增欄位時務必同步更新 [copy]。
class Player {
  Player({required this.seat, this.role});

  /// 座次／編號，1 起算。座次是環狀的，計算發言順序時需繞回。
  final int seat;

  /// 法官登記的身分。null 表示尚未指定。
  Role? role;

  bool alive = true;

  /// 是否已失去投票權（白痴翻牌後）。
  bool canVote = true;

  /// 當夜事實標記，每晚結算後清空。
  final Set<FactTag> nightFacts = <FactTag>{};

  /// 持續性資訊標記。
  final Set<InfoTag> infoTags = <InfoTag>{};

  /// 從快照就地還原。**新增欄位時必須同步修改這裡與 [copy]。**
  ///
  /// 不換物件而是就地覆寫，因為 [GameState.players] 是不可變長度的清單，
  /// 到處都持有 Player 的參照。
  void restoreFrom(Player snapshot) {
    role = snapshot.role;
    alive = snapshot.alive;
    canVote = snapshot.canVote;
    nightFacts
      ..clear()
      ..addAll(snapshot.nightFacts);
    infoTags
      ..clear()
      ..addAll(snapshot.infoTags);
  }

  /// 深拷貝。**新增欄位時必須同步修改這裡** —— 漏拷貝一層會導致
  /// 修改現況時連快照一起變，撤銷功能就壞了。
  Player copy() {
    final p = Player(seat: seat, role: role)
      ..alive = alive
      ..canVote = canVote;
    p.nightFacts.addAll(nightFacts);
    p.infoTags.addAll(infoTags);
    return p;
  }

  @override
  String toString() => 'Player($seat, ${role?.id ?? "未指定"}, '
      '${alive ? "存活" : "死亡"})';
}
