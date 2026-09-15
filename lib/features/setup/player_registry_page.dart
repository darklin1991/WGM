import 'package:flutter/material.dart';

import '../../core/models/game_state.dart';
import '../../core/models/player.dart';
import '../../core/models/role.dart';
import '../../shared/theme.dart';
import '../night/night_flow_page.dart';

/// 玩家登記：座次、身分、生死狀態、狀態標記。
///
/// 依「狀態直接修改」的架構決定，這裡直接改 [GameState] 再 setState。
class PlayerRegistryPage extends StatefulWidget {
  const PlayerRegistryPage({super.key, required this.state});

  final GameState state;

  @override
  State<PlayerRegistryPage> createState() => _PlayerRegistryPageState();
}

class _PlayerRegistryPageState extends State<PlayerRegistryPage> {
  GameState get _state => widget.state;

  /// 隨機發牌：依板子配置洗牌後依序指定給每個座次。
  void _dealRandomly() {
    final deck = _state.preset.buildRoleDeck()..shuffle();
    setState(() {
      for (var i = 0; i < _state.players.length; i++) {
        _state.players[i].role = deck[i];
      }
    });
  }

  void _clearAll() {
    setState(() {
      for (final p in _state.players) {
        p.role = null;
        p.alive = true;
        p.canVote = true;
        p.nightFacts.clear();
        p.infoTags.clear();
      }
      _state.sheriffSeat = null;
    });
  }

  Future<void> _editPlayer(Player player) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (_) => _PlayerSheet(state: _state, player: player),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final preset = _state.preset;
    final matches = _state.assignmentMatchesPreset;
    final unassigned = _state.unassignedSeats;

    return Scaffold(
      appBar: AppBar(
        title: Text(preset.name),
        actions: [
          IconButton(
            onPressed: _dealRandomly,
            icon: const Icon(Icons.shuffle),
            tooltip: '隨機發牌',
          ),
          IconButton(
            onPressed: _clearAll,
            icon: const Icon(Icons.refresh),
            tooltip: '全部清除',
          ),
        ],
      ),
      body: Column(
        children: [
          _SummaryBar(state: _state),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 116,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemCount: _state.players.length,
              itemBuilder: (context, i) {
                final player = _state.players[i];
                return _SeatTile(
                  player: player,
                  isSheriff: _state.sheriffSeat == player.seat,
                  onTap: () => _editPlayer(player),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                children: [
                  if (unassigned.isNotEmpty)
                    _Hint(
                      text: '尚有 ${unassigned.length} 位未指定身分：'
                          '${unassigned.join('、')} 號',
                    )
                  else if (!matches)
                    _Hint(
                      text: '已登記的身分與板子配置不符'
                          '（應為 ${preset.composition}）',
                      isError: true,
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: matches ? _startGame : null,
                    icon: const Icon(Icons.nightlight_round),
                    label: Text(matches ? '進入第一夜' : '請先完成身分登記'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 身分已手動登記完成，直接進夜晚流程收集技能目標
  /// （不必再走首夜的逐一登記）。
  void _startGame() {
    _state.dayNumber = 0;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => NightFlowPage(state: _state)),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    final counts = state.assignedRoleCounts;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${state.preset.playerCount} 人　${state.preset.composition}　'
            '存活 ${state.aliveCount}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final slot in state.preset.roles)
                _QuotaChip(
                  label: slot.role.nameZh,
                  assigned: counts[slot.role.id] ?? 0,
                  quota: slot.count,
                  color: WgmTheme.colorOf(slot.role),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuotaChip extends StatelessWidget {
  const _QuotaChip({
    required this.label,
    required this.assigned,
    required this.quota,
    required this.color,
  });

  final String label;
  final int assigned;
  final int quota;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final done = assigned == quota;
    final over = assigned > quota;
    final tint = over ? Theme.of(context).colorScheme.error : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: done ? 0.22 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tint.withValues(alpha: done ? 0.7 : 0.3)),
      ),
      child: Text(
        '$label $assigned/$quota',
        style: TextStyle(
          fontSize: 12,
          color: tint,
          fontWeight: done ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.player,
    required this.isSheriff,
    required this.onTap,
  });

  final Player player;
  final bool isSheriff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dead = !player.alive;
    final color = dead ? WgmTheme.deadColor : WgmTheme.colorOf(player.role);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: dead ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${player.seat}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    if (isSheriff)
                      const Icon(Icons.star_rounded,
                          size: 18, color: Color(0xFFE8C062)),
                    if (dead)
                      const Icon(Icons.close_rounded,
                          size: 18, color: WgmTheme.deadColor),
                  ],
                ),
                const Spacer(),
                Text(
                  player.role?.nameZh ?? '未指定',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: player.role == null
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : color,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 18,
                  child: Wrap(
                    spacing: 3,
                    children: [
                      for (final t in player.infoTags)
                        _TagDot(label: t.labelZh),
                      for (final t in player.nightFacts)
                        _TagDot(label: t.labelZh),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagDot extends StatelessWidget {
  const _TagDot({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}

/// 單一玩家的編輯面板：指定身分、切換生死、加減標記、設為警長。
class _PlayerSheet extends StatefulWidget {
  const _PlayerSheet({required this.state, required this.player});

  final GameState state;
  final Player player;

  @override
  State<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<_PlayerSheet> {
  Player get _player => widget.player;
  GameState get _state => widget.state;

  @override
  Widget build(BuildContext context) {
    final rolesInPreset = _state.preset.roles.map((s) => s.role).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${_player.seat} 號',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _SectionLabel('身分'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final role in rolesInPreset)
                    _RoleChoice(
                      role: role,
                      selected: _player.role?.id == role.id,
                      remaining: _state.remainingQuotaFor(role),
                      onTap: () => setState(() {
                        _player.role =
                            _player.role?.id == role.id ? null : role;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionLabel('狀態'),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _player.alive = !_player.alive;
                      }),
                      icon: Icon(
                        _player.alive
                            ? Icons.favorite_rounded
                            : Icons.heart_broken_rounded,
                      ),
                      label: Text(_player.alive ? '存活' : '死亡'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _state.sheriffSeat =
                            _state.sheriffSeat == _player.seat
                                ? null
                                : _player.seat;
                      }),
                      icon: const Icon(Icons.star_rounded),
                      label: Text(
                        _state.sheriffSeat == _player.seat ? '取消警長' : '設為警長',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionLabel('資訊標記（不影響結算）'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in InfoTag.values)
                    FilterChip(
                      label: Text(tag.labelZh),
                      selected: _player.infoTags.contains(tag),
                      onSelected: (on) => setState(() {
                        on
                            ? _player.infoTags.add(tag)
                            : _player.infoTags.remove(tag);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionLabel('事實標記（由夜晚結算產生，此處僅供手動修正）'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in FactTag.values)
                    FilterChip(
                      label: Text(tag.labelZh),
                      selected: _player.nightFacts.contains(tag),
                      onSelected: (on) => setState(() {
                        on
                            ? _player.nightFacts.add(tag)
                            : _player.nightFacts.remove(tag);
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    required this.role,
    required this.selected,
    required this.remaining,
    required this.onTap,
  });

  final Role role;
  final bool selected;

  /// 此角色還可登記幾位（未含本座次目前的選擇）。
  final int remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = WgmTheme.colorOf(role);
    final exhausted = !selected && remaining <= 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? color
                : color.withValues(alpha: exhausted ? 0.15 : 0.4),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(
              role.nameZh,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: exhausted ? color.withValues(alpha: 0.4) : color,
              ),
            ),
            if (!selected) ...[
              const SizedBox(width: 6),
              Text(
                '剩 $remaining',
                style: TextStyle(
                  fontSize: 11,
                  color: exhausted
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
