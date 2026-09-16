import 'package:flutter/material.dart';

import '../../core/models/game_state.dart';
import '../../core/models/night_action.dart';
import '../../core/models/role.dart';
import '../../shared/theme.dart';
import 'night_flow_page.dart';

/// 夜晚結算結果。
///
/// 除了死亡名單，也把裁決說明一併列出 —— 現場如果有爭議
/// （為什麼同守同救還是死了），法官要能立刻說明依據。
class NightResultPage extends StatelessWidget {
  const NightResultPage({
    super.key,
    required this.state,
    required this.outcome,
    this.autoFilledVillagers = const [],
  });

  final GameState state;
  final NightOutcome outcome;

  /// 首夜自動填為平民的座次。
  final List<int> autoFilledVillagers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('第 ${state.dayNumber} 夜　結算')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- 天亮了 ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '天亮了',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (outcome.isPeacefulNight)
                    const Text(
                      '昨晚是平安夜',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  else
                    Text(
                      '昨晚死亡：${outcome.deadSeats.join('、')} 號',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: WgmTheme.wolfColor,
                      ),
                    ),
                  if (!outcome.isPeacefulNight) ...[
                    const SizedBox(height: 10),
                    for (final d in outcome.deaths)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${d.seat} 號 · '
                          '${state.playerAt(d.seat).role?.nameZh ?? "未知"} · '
                          '${d.cause.labelZh}',
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ---- 獵人開槍 ----
          if (outcome.hunterMayShoot)
            _InfoCard(
              icon: Icons.crisis_alert_rounded,
              iconColor: WgmTheme.wolfColor,
              title: '獵人可以開槍',
              body: '獵人已出局且死因不是毒，請詢問是否開槍帶人。',
            ),

          // ---- 預言家查驗結果 ----
          if (outcome.seerTarget != null)
            _InfoCard(
              icon: Icons.visibility_rounded,
              iconColor:
                  outcome.seerSawWolf ? WgmTheme.wolfColor : WgmTheme.godColor,
              title: '預言家查驗 ${outcome.seerTarget} 號',
              body: outcome.seerSawWolf ? '結果：查殺（狼人）' : '結果：金水（好人）',
            ),

          // ---- 通靈師查驗結果 ----
          // 通靈師看到的是真實身分，不是好人／狼人，所以要把角色名寫出來。
          if (outcome.psychicResult != null)
            _InfoCard(
              icon: Icons.auto_awesome_rounded,
              iconColor:
                  outcome.psychicResult!.revealedRole?.camp == Camp.wolf
                      ? WgmTheme.wolfColor
                      : WgmTheme.godColor,
              title: '通靈師查驗 ${outcome.psychicResult!.seat} 號',
              body: '真實身分：'
                  '${outcome.psychicResult!.revealedRole?.nameZh ?? "尚未登記"}',
            ),

          // ---- 機械狼 ----
          if (outcome.mechanicLearnedRole != null)
            _InfoCard(
              icon: Icons.memory_rounded,
              iconColor: WgmTheme.wolfColor,
              title: '機械狼學習了 ${outcome.mechanicLearnedRole!.nameZh}',
              body: '技能自**下一夜**起生效，整局只能學這一次。',
            ),
          if (outcome.mechanicSeerTarget != null)
            _InfoCard(
              icon: Icons.memory_rounded,
              iconColor: outcome.mechanicSeerSawWolf
                  ? WgmTheme.wolfColor
                  : WgmTheme.godColor,
              title: '機械狼查驗 ${outcome.mechanicSeerTarget} 號',
              body: outcome.mechanicSeerSawWolf ? '結果：查殺（狼人）' : '結果：金水（好人）',
            ),
          if (outcome.mechanicPsychicResult != null)
            _InfoCard(
              icon: Icons.memory_rounded,
              iconColor: WgmTheme.godColor,
              title: '機械狼查驗 ${outcome.mechanicPsychicResult!.seat} 號',
              body: '真實身分：'
                  '${outcome.mechanicPsychicResult!.revealedRole?.nameZh ?? "尚未登記"}',
            ),

          if (outcome.shieldBrokenSeats.isNotEmpty)
            _InfoCard(
              icon: Icons.shield_outlined,
              iconColor: WgmTheme.wolfColor,
              title: '破盾：${outcome.shieldBrokenSeats.join('、')} 號',
              body: '機械狼（已學到狼人）雙刀集中，守衛的守護與女巫的解藥都被打穿。',
            ),
          if (outcome.poisonReflectedTo != null)
            _InfoCard(
              icon: Icons.u_turn_left_rounded,
              iconColor: WgmTheme.wolfColor,
              title: '毒藥反彈到 ${outcome.poisonReflectedTo} 號',
              body: '目標被機械狼（已學到守衛）守住，毒反噬下毒的人。',
            ),

          // ---- 殉情 ----
          if (outcome.charmSuicideSeat != null)
            _InfoCard(
              icon: Icons.favorite_rounded,
              iconColor: WgmTheme.wolfColor,
              title: '${outcome.charmSuicideSeat} 號殉情',
              body: '狼美人出局，被魅惑者隨之死亡。',
            ),

          // ---- 裁決說明 ----
          if (outcome.notes.isNotEmpty)
            _InfoCard(
              icon: Icons.gavel_rounded,
              iconColor: scheme.onSurfaceVariant,
              title: '裁決說明',
              bodyWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final n in outcome.notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '· $n',
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                ],
              ),
            ),

          // ---- 首夜自動填入平民 ----
          if (autoFilledVillagers.isNotEmpty)
            _InfoCard(
              icon: Icons.groups_rounded,
              iconColor: WgmTheme.villagerColor,
              title: '剩餘 ${autoFilledVillagers.length} 位自動登記為平民',
              body: '${autoFilledVillagers.join('、')} 號',
            ),

          // ---- 場上狀態 ----
          _InfoCard(
            icon: Icons.people_alt_rounded,
            iconColor: scheme.primary,
            title: '場上狀態',
            bodyWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '存活 ${state.aliveCount} / ${state.preset.playerCount}　'
                  '狼 ${state.aliveWolfCount}　'
                  '神 ${state.aliveGodCount}　'
                  '民 ${state.aliveVillagerCount}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in state.players)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (p.alive
                                    ? WgmTheme.colorOf(p.role)
                                    : WgmTheme.deadColor)
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '${p.seat} ${p.role?.nameZh ?? "?"}'
                          '${p.alive ? "" : " ✕"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: p.alive
                                ? WgmTheme.colorOf(p.role)
                                : WgmTheme.deadColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _nextNight(context),
            icon: const Icon(Icons.nightlight_round),
            label: Text('進入第 ${state.dayNumber + 1} 夜'),
          ),
          const SizedBox(height: 8),
          Text(
            '白天流程（警長競選、發言計時、投票）尚未實作，'
            '目前先直接進入下一夜以便測試夜晚結算。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _nextNight(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => NightFlowPage(state: state)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.body,
    this.bodyWidget,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? body;
  final Widget? bodyWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (body != null || bodyWidget != null) ...[
                const SizedBox(height: 8),
                bodyWidget ??
                    Text(
                      body!,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
