/// 要計時的是哪一種發言。只影響畫面上的稱呼，不影響規則。
enum SpeechPhase {
  campaign('警上發言'),
  day('發言'),
  runoff('平票 PK 發言'),
  lastWords('遺言');

  const SpeechPhase(this.labelZh);

  final String labelZh;
}

/// 發言計時。
///
/// 純 Dart，**不自己跑碼表** —— 每秒呼叫一次 [tick] 是頁面的事。這樣規則
/// （誰在講、剩幾秒、超時多久、能不能往回退）全部可以用同步測試驗證，
/// 不必碰假 async。
///
/// 擔當指定的賽制（2026-09-19）：
///
/// - 每人額度預設 2 分鐘（板子旗標 `speechSeconds`），**法官現場可以改**。
/// - **時間到只是提示，不自動跳下一位** —— 現場常常要多寬幾秒，
///   什麼時候換人由法官決定。所以歸零之後繼續往下數，記成超時。
///
/// 計時不會動到 `GameState`，所以不需要撤銷快照；按錯了直接往回按
/// [previous] 或 [jumpTo] 就好。
class SpeechTimer {
  SpeechTimer({required List<int> order, required this.seconds})
      : order = List.unmodifiable(order),
        assert(order.isNotEmpty, '沒有人要發言就不該開計時'),
        assert(seconds > 0, '發言額度必須是正數');

  /// 發言順序，依序走。
  final List<int> order;

  /// 每人的額度（秒）。法官可以隨時改，改了只影響剩餘時間的算法，
  /// 不會把已經講掉的秒數抹掉。
  int seconds;

  /// 目前輪到 [order] 的第幾位。
  int index = 0;

  /// 目前這位已經講了幾秒。
  int elapsed = 0;

  /// 碼表是否在跑。
  bool running = false;

  int get currentSeat => order[index];

  /// 剩餘秒數。超時之後是負的。
  int get remaining => seconds - elapsed;

  /// 時間已經用完（含剛好歸零）。
  bool get overtime => remaining <= 0;

  /// 超時了幾秒；沒超時就是 0。
  int get overtimeSeconds => overtime ? -remaining : 0;

  bool get isFirst => index == 0;

  bool get isLast => index == order.length - 1;

  /// 還沒發言的人數（不含目前這位）。
  int get remainingSpeakers => order.length - index - 1;

  // ---- 碼表 ----

  /// 由頁面每秒呼叫一次。
  void tick() {
    if (running) elapsed++;
  }

  void start() => running = true;

  void pause() => running = false;

  void toggle() => running = !running;

  /// 這一位重新計時，不換人。
  void resetCurrent() {
    elapsed = 0;
    running = false;
  }

  /// 改每人額度。
  void setSeconds(int value) {
    if (value <= 0) return;
    seconds = value;
  }

  // ---- 換人 ----

  /// 換下一位，並直接開始計時 —— 法官按這顆的時機就是下一位開口的時機。
  void next() {
    if (isLast) return;
    index++;
    elapsed = 0;
    running = true;
  }

  /// 退回上一位。時間歸零重數 —— 前一位講了多久沒有留存的必要。
  void previous() {
    if (isFirst) return;
    index--;
    elapsed = 0;
    running = false;
  }

  /// 直接跳到某個座次（點發言條上的號碼）。不在 [order] 裡就不動。
  void jumpTo(int seat) {
    final i = order.indexOf(seat);
    if (i < 0) return;
    index = i;
    elapsed = 0;
    running = false;
  }

  /// `2:05`；超時顯示 `+0:12`。
  static String format(int seconds) {
    final over = seconds < 0;
    final v = over ? -seconds : seconds;
    final text = '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
    return over ? '+$text' : text;
  }

  /// 畫面上那顆大字。
  String get display => format(remaining);
}
