import 'package:flutter/material.dart';

import '../../core/models/game_state.dart';
import 'review_log_page.dart';

/// AppBar 上的「翻日誌」鍵。
///
/// 遊戲進行中隨時可按 —— 現場有人爭「第二天誰投了誰」時，法官翻一下就有答案。
/// 打開的是唯讀頁，不影響任何流程，關掉就回到原本那一步。
class ReviewLogButton extends StatelessWidget {
  const ReviewLogButton({super.key, required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '復盤日誌',
      icon: const Icon(Icons.history_rounded),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReviewLogPage(state: state),
        ),
      ),
    );
  }
}
