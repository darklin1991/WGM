import '../models/game_state.dart';

/// 一筆撤銷快照。
class UndoSnapshot {
  const UndoSnapshot({required this.label, required this.state, this.cursor});

  /// 這一步做了什麼，顯示在撤銷按鈕上，例如「守衛守 9 號」。
  final String label;

  /// 動作**發生之前**的完整局面深拷貝。
  final GameState state;

  /// 呼叫端自己的位置資訊（例如夜晚流程走到第幾步、收到哪些行動）。
  ///
  /// 只還原 [GameState] 不夠 —— 局面回去了但流程還停在後面一步，
  /// 法官會看到對不上的畫面。堆疊不解讀這個值，原樣存原樣還。
  final Object? cursor;
}

/// 撤銷堆疊。
///
/// 法官現場誤觸是常態 —— 點錯一個目標不該整個階段重來。
/// 因為 [GameState] 是可變狀態、引擎就地修改，撤銷只能靠還原深拷貝快照。
///
/// **顆粒度要細**：每個夜晚行動、每次投票各存一筆，不要只在階段邊界存。
///
/// 快照存的是「動作發生之前」的狀態，所以 [undo] 回傳的就是上一步的局面。
class UndoStack {
  UndoStack({this.limit = 60});

  /// 最多保留幾筆。一局十來個夜晚行動加上投票也用不到這個數，
  /// 設上限只是避免長局把記憶體撐大。
  final int limit;

  final List<UndoSnapshot> _snapshots = [];

  bool get canUndo => _snapshots.isNotEmpty;

  int get depth => _snapshots.length;

  /// 最近一筆快照的說明；空堆疊回傳 null。
  String? get topLabel => _snapshots.isEmpty ? null : _snapshots.last.label;

  /// 在動作**發生之前**呼叫，存下目前局面。
  ///
  /// [state] 會被深拷貝，之後怎麼改都不影響快照。
  void push(GameState state, String label, {Object? cursor}) {
    _snapshots.add(
      UndoSnapshot(label: label, state: state.copy(), cursor: cursor),
    );
    if (_snapshots.length > limit) _snapshots.removeAt(0);
  }

  /// 取出最近一筆快照。空堆疊回傳 null。
  ///
  /// 回傳的是快照本身（已經是深拷貝），呼叫端拿去取代目前的局面即可。
  UndoSnapshot? undo() => _snapshots.isEmpty ? null : _snapshots.removeLast();

  /// 丟棄全部快照 —— 換局或進入新階段且不允許跨階段撤銷時用。
  void clear() => _snapshots.clear();
}
