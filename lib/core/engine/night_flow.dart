import '../models/preset.dart';
import '../models/role.dart';

/// 一個夜間步驟要收集什麼技能目標。
enum NightSkill {
  /// 守衛守護。
  guardProtect,

  /// 狼刀。
  wolfKill,

  /// 女巫用藥（解藥／毒藥）。
  witchPotion,

  /// 預言家查驗。
  seerInspect,

  /// 獵人：**每晚**都要叫起來，由法官給「可否開槍」的手勢。
  ///
  /// 獵人本身沒有夜間行動，但需要知道自己的技能狀態（被毒就不能開槍），
  /// 所以每晚都得睜眼看法官手勢。
  hunterGesture,

  /// 無夜間行動，只在首夜登記座次（白痴等）。
  none,
}

/// 首夜的一個步驟。
///
/// 首夜的流程是「先登記是誰，再發動技能」——法官不預先登記全部身分，
/// 而是依夜晚順序邊問邊登記：「守衛請睜眼，你是幾號」→「你要守誰」。
class NightStep {
  const NightStep({
    required this.title,
    required this.roles,
    required this.seatCount,
    required this.skill,
    this.primaryRole,
  });

  /// 步驟標題，例如「守衛」、「狼人」。
  final String title;

  /// 本步驟要登記的角色。狼隊是 [Roles.wolf] 與 [Roles.wolfKing] 合併成
  /// 一步 —— 現場「狼人請睜眼」是一次性動作，四匹狼同時互相識別。
  final List<Role> roles;

  /// 本步驟要登記幾個座次。
  final int seatCount;

  final NightSkill skill;

  /// 技能歸屬的角色；狼隊步驟為 [Roles.wolf]。
  final Role? primaryRole;

  /// 本步驟是否需要在登記後額外指定一位特殊成員（狼王）。
  bool get needsWolfKingPick =>
      roles.any((r) => r.id == Roles.wolfKing.id) && roles.length > 1;

  /// 狼隊步驟中，狼王要指定幾位。
  int get wolfKingCount => needsWolfKingPick ? 1 : 0;
}

/// 依板子產生首夜的步驟序列。
///
/// 規則：
/// 1. 先走板子的 `nightOrder`（有主動夜間行動的角色）
/// 2. 狼人與狼王合併為一個「狼隊」步驟
/// 3. 再補上尚未登記、且有夜間技能以外身分的非平民角色（獵人、白痴）
/// 4. 平民不列入步驟 —— 完成所有特殊身分後，剩下的座次自動是平民
abstract final class NightFlow {
  static List<NightStep> firstNightSteps(Preset preset) {
    final steps = <NightStep>[];
    final covered = <String>{};

    int countOf(String roleId) => preset.roles
        .where((s) => s.role.id == roleId)
        .fold<int>(0, (sum, s) => sum + s.count);

    for (final role in preset.nightOrder) {
      if (covered.contains(role.id)) continue;

      if (role.id == Roles.wolf.id || role.id == Roles.wolfKing.id) {
        // 狼隊合併：一般狼 + 狼王一次填完，再指定哪位是狼王。
        final teamRoles = <Role>[];
        var seatCount = 0;
        for (final id in [Roles.wolf.id, Roles.wolfKing.id]) {
          final c = countOf(id);
          if (c > 0) {
            teamRoles.add(Roles.byId(id)!);
            seatCount += c;
            covered.add(id);
          }
        }
        steps.add(
          NightStep(
            title: '狼人',
            roles: teamRoles,
            seatCount: seatCount,
            skill: NightSkill.wolfKill,
            primaryRole: Roles.wolf,
          ),
        );
        continue;
      }

      covered.add(role.id);
      steps.add(
        NightStep(
          title: role.nameZh,
          roles: [role],
          seatCount: countOf(role.id),
          skill: _skillOf(role),
          primaryRole: role,
        ),
      );
    }

    // 補上不在 nightOrder、但仍需叫起來的角色（獵人、白痴等）。
    // 獵人排在最後有其必要：法官必須先收完女巫的毒藥，才知道該給
    // 「可開槍」還是「不可開槍」的手勢。
    for (final slot in preset.roles) {
      final role = slot.role;
      if (covered.contains(role.id)) continue;
      if (role.kind == RoleKind.villager) continue; // 平民最後自動填入
      covered.add(role.id);
      steps.add(
        NightStep(
          title: role.nameZh,
          roles: [role],
          seatCount: countOf(role.id),
          skill: _skillOf(role),
          primaryRole: role,
        ),
      );
    }

    return steps;
  }

  /// 第二夜起的步驟：身分已登記，只收集技能目標，不再填座次。
  ///
  /// 獵人雖然沒有夜間行動，但每晚都要叫起來確認開槍手勢，所以保留；
  /// 白痴這類純登記的角色首夜登記完就不再出現。
  static List<NightStep> laterNightSteps(Preset preset) => [
        for (final step in firstNightSteps(preset))
          if (step.skill != NightSkill.none)
            NightStep(
              title: step.title,
              roles: step.roles,
              seatCount: 0,
              skill: step.skill,
              primaryRole: step.primaryRole,
            ),
      ];

  static NightSkill _skillOf(Role role) => switch (role.id) {
        'guard' => NightSkill.guardProtect,
        'wolf' || 'wolfKing' => NightSkill.wolfKill,
        'witch' => NightSkill.witchPotion,
        'seer' => NightSkill.seerInspect,
        'hunter' => NightSkill.hunterGesture,
        _ => NightSkill.none,
      };
}
