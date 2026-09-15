import 'package:flutter/material.dart';

import '../../core/models/game_state.dart';
import '../../core/models/preset.dart';
import '../../core/storage/preset_loader.dart';
import '../../shared/theme.dart';
import '../night/night_flow_page.dart';
import 'player_registry_page.dart';

/// 板子選擇（首頁）。
///
/// 板子清單來自 `assets/presets/*.json`，新增板子只需新增檔案。
class PresetListPage extends StatefulWidget {
  const PresetListPage({super.key, this.loader = const PresetLoader()});

  final PresetLoader loader;

  @override
  State<PresetListPage> createState() => _PresetListPageState();
}

class _PresetListPageState extends State<PresetListPage> {
  late Future<PresetLoadResult> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader.loadAll();
  }

  /// 主流程：直接進第一夜。身分在夜晚流程中依序登記，
  /// 不需要事先把 12 個身分都填完。
  void _startFirstNight(Preset preset) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NightFlowPage(state: GameState(preset: preset)),
      ),
    );
  }

  /// 次要入口：事先手動配置身分（發完牌就想先登記、或事後要修正時用）。
  void _openManualSetup(Preset preset) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerRegistryPage(state: GameState(preset: preset)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WGM 法官助手'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(24),
          child: Padding(
            padding: EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('選擇板子', style: TextStyle(fontSize: 13)),
            ),
          ),
        ),
      ),
      body: FutureBuilder<PresetLoadResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(message: snapshot.error.toString());
          }
          final result = snapshot.data!;
          if (result.presets.isEmpty) {
            return _ErrorView(
              message: result.hasErrors
                  ? result.errors.entries
                      .map((e) => '${e.key}\n${e.value}')
                      .join('\n\n')
                  : 'assets/presets/ 底下沒有任何板子設定檔',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: result.presets.length + (result.hasErrors ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == result.presets.length) {
                return _LoadErrorBanner(errors: result.errors);
              }
              final preset = result.presets[index];
              return _PresetCard(
                preset: preset,
                onStart: () => _startFirstNight(preset),
                onManualSetup: () => _openManualSetup(preset),
              );
            },
          );
        },
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.onStart,
    required this.onManualSetup,
  });

  final Preset preset;
  final VoidCallback onStart;
  final VoidCallback onManualSetup;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onStart,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      preset.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _Pill(
                    text: '${preset.playerCount} 人',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Pill(text: '${preset.wolfCount}狼', color: WgmTheme.wolfColor),
                  const SizedBox(width: 6),
                  _Pill(text: '${preset.godCount}神', color: WgmTheme.godColor),
                  const SizedBox(width: 6),
                  _Pill(
                    text: '${preset.villagerCount}民',
                    color: WgmTheme.villagerColor,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '神職：${preset.godNames.join('、')}',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                '夜晚順序：${preset.nightOrder.map((r) => r.nameZh).join(' → ')}',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '同守同救${preset.rules.guardHealKills ? '致死' : '不致死'}'
                '　${preset.rules.winCondition.labelZh}'
                '　警長票 ${preset.rules.sheriffVoteWeight}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.nightlight_round, size: 18),
                      label: const Text('開始第一夜'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: onManualSetup,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(46, 46),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Icon(Icons.edit_note_rounded, size: 20),
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

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _LoadErrorBanner extends StatelessWidget {
  const _LoadErrorBanner({required this.errors});

  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text('${errors.length} 份板子載入失敗'),
              ],
            ),
            const SizedBox(height: 8),
            for (final e in errors.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${e.key}\n${e.value}',
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
