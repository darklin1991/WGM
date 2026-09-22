import 'package:flutter/material.dart';

import '../../core/engine/win_checker.dart';
import '../../core/models/game_state.dart';
import '../../core/models/log_entry.dart';
import '../../core/models/role.dart';
import '../../shared/theme.dart';
import '../setup/preset_list_page.dart';
import 'review_log_page.dart';

/// 遊戲結束頁：宣布結果並揭曉全部身分。
///
/// 復盤的第一步 —— 法官要能當場把整桌身分攤開來對。
class GameOverPage extends StatefulWidget {
  const GameOverPage({
    super.key,
    required this.state,
    required this.check,
  });

  final GameState state;
  final WinCheck check;

  @override
  State<GameOverPage> createState() => _GameOverPageState();
}

class _GameOverPageState extends State<GameOverPage> {
  GameState get state => widget.state;
  WinCheck get check => widget.check;

  @override
  void initState() {
    super.initState();
    // 勝負也要進復盤日誌。寫在 initState 而不是 build —— 重繪不該重複記。
    state.log.add(
      round: state.dayNumber,
      isNight: false,
      kind: LogKind.gameOver,
      text: '${check.result.labelZh} —— ${check.reason}',
    );
  }

  Color get _winnerColor => check.result == GameResult.wolvesWin
      ? WgmTheme.wolfColor
      : WgmTheme.godColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${state.dayNumber} 天　遊戲結束'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _winnerColor.withValues(alpha: 0.12),
                border: Border.all(color: _winnerColor.withValues(alpha: 0.6)),
              ),
              child: Column(
                children: [
                  Icon(
                    check.result == GameResult.wolvesWin
                        ? Icons.dark_mode_rounded
                        : Icons.wb_sunny_rounded,
                    size: 64,
                    color: _winnerColor,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    check.result.labelZh,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: _winnerColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    check.reason,
                    style: TextStyle(
                      fontSize: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 暗戀者是**個人勝負**，與陣營勝負各算各的 —— 可能出現
          // 「好人勝，但暗戀者輸」。不另外寫一行的話現場根本看不出來。
          if (check.secretAdmirerWon != null) ...[
            const SizedBox(height: 10),
            _SecretAdmirerCard(
              won: check.secretAdmirerWon!,
              admirerSeat: state.seatOfRole(Roles.secretAdmirer.id),
              targetSeat: state.secretAdmirerTarget,
            ),
          ],

          const SizedBox(height: 16),

          Text(
            '身分揭曉',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final camp in [Camp.wolf, Camp.good]) _campCard(scheme, camp),

          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReviewLogPage(state: state),
              ),
            ),
            icon: const Icon(Icons.history_rounded),
            label: const Text('查看復盤日誌'),
          ),
          const SizedBox(height: 8),
          // 回板子列表會把整個堆疊清掉 —— 這一局的日誌就沒了，所以排在下面。
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const PresetListPage()),
              (route) => false,
            ),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('回到板子列表'),
          ),
          const SizedBox(height: 8),
          Text(
            '離開之後這一局的日誌就不見了，要留的話先複製起來。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _campCard(ColorScheme scheme, Camp camp) {
    final members = state.players.where((p) => p.role?.camp == camp).toList();
    if (members.isEmpty) return const SizedBox.shrink();

    final aliveCount = members.where((p) => p.alive).length;
    final color = camp == Camp.wolf ? WgmTheme.wolfColor : WgmTheme.godColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${camp == Camp.wolf ? "狼人陣營" : "好人陣營"}'
                '（存活 $aliveCount／${members.length}）',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              for (final p in members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${p.seat} 號',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: p.alive
                                ? scheme.onSurface
                                : WgmTheme.deadColor,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          p.role?.nameZh ?? '未知',
                          style: TextStyle(
                            fontSize: 14,
                            color: p.alive
                                ? WgmTheme.colorOf(p.role)
                                : WgmTheme.deadColor,
                          ),
                        ),
                      ),
                      Text(
                        p.alive ? '存活' : '出局',
                        style: TextStyle(
                          fontSize: 12,
                          color: p.alive
                              ? scheme.onSurfaceVariant
                              : WgmTheme.deadColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 暗戀者的個人勝負。
///
/// 陣營勝負在上面那張大卡，這張只講暗戀者自己 —— 兩者可能相反，
/// 所以措辭要明確寫出「跟誰一起贏／輸」，不能只寫贏或輸。
class _SecretAdmirerCard extends StatelessWidget {
  const _SecretAdmirerCard({
    required this.won,
    required this.admirerSeat,
    required this.targetSeat,
  });

  final bool won;

  /// 暗戀者本人的座次；本局沒有暗戀者時為 null。
  final int? admirerSeat;

  /// 首夜選的暗戀對象座次。
  final int? targetSeat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = won ? WgmTheme.godColor : scheme.onSurfaceVariant;
    final who = admirerSeat == null ? '暗戀者' : '暗戀者（$admirerSeat 號）';
    final target = targetSeat == null ? '沒有指定對象' : '暗戀 $targetSeat 號';

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(
              won ? Icons.favorite_rounded : Icons.heart_broken_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    won ? '$who也獲勝' : '$who沒有獲勝',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$target，勝負跟著對象首夜的陣營走',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
