import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/speech_timer.dart';

SpeechTimer _timer({List<int>? order, int seconds = 120}) =>
    SpeechTimer(order: order ?? const [5, 6, 7], seconds: seconds);

/// 跑 [n] 秒。
void _run(SpeechTimer t, int n) {
  for (var i = 0; i < n; i++) {
    t.tick();
  }
}

void main() {
  group('碼表', () {
    test('開始之前不會動', () {
      final t = _timer();
      _run(t, 10);

      expect(t.elapsed, 0);
      expect(t.remaining, 120);
      expect(t.running, isFalse);
    });

    test('跑起來之後一秒一秒扣', () {
      final t = _timer()..start();
      _run(t, 45);

      expect(t.elapsed, 45);
      expect(t.remaining, 75);
    });

    test('暫停就停住，再開繼續數', () {
      final t = _timer()..start();
      _run(t, 30);
      t.pause();
      _run(t, 100);

      expect(t.remaining, 90, reason: '暫停期間不該扣');

      t.start();
      _run(t, 10);
      expect(t.remaining, 80);
    });

    test('toggle 來回切', () {
      final t = _timer();
      expect(t.running, isFalse);

      t.toggle();
      expect(t.running, isTrue);

      t.toggle();
      expect(t.running, isFalse);
    });

    test('重新計時只歸零這一位，不換人', () {
      final t = _timer()..start();
      _run(t, 60);
      t.resetCurrent();

      expect(t.elapsed, 0);
      expect(t.currentSeat, 5);
      expect(t.running, isFalse, reason: '重來之後等法官重新按開始');
    });
  });

  group('時間到只提示，不自動跳', () {
    test('歸零之後繼續往下數成超時', () {
      final t = _timer(seconds: 10)..start();
      _run(t, 10);

      expect(t.overtime, isTrue);
      expect(t.remaining, 0);
      expect(t.overtimeSeconds, 0);

      _run(t, 12);
      expect(t.remaining, -12);
      expect(t.overtimeSeconds, 12);
    });

    test('超時不會自己換人', () {
      final t = _timer(seconds: 5)..start();
      _run(t, 60);

      expect(t.currentSeat, 5, reason: '換人一律由法官按');
      expect(t.index, 0);
      expect(t.running, isTrue);
    });
  });

  group('換人', () {
    test('下一位會歸零並直接開始', () {
      final t = _timer()..start();
      _run(t, 50);
      t.next();

      expect(t.currentSeat, 6);
      expect(t.elapsed, 0);
      expect(t.running, isTrue, reason: '按下一位的時機就是下一位開口的時機');
    });

    test('最後一位再按下一位不會越界', () {
      final t = _timer()
        ..next()
        ..next();
      expect(t.currentSeat, 7);
      expect(t.isLast, isTrue);

      t.next();
      expect(t.currentSeat, 7);
      expect(t.index, 2);
    });

    test('退回上一位，時間重數且不自動跑', () {
      final t = _timer()..next();
      t.start();
      _run(t, 30);

      t.previous();
      expect(t.currentSeat, 5);
      expect(t.elapsed, 0);
      expect(t.running, isFalse);
    });

    test('第一位再往回退不會越界', () {
      final t = _timer()..previous();

      expect(t.index, 0);
      expect(t.isFirst, isTrue);
    });

    test('點發言條可以直接跳過去', () {
      final t = _timer()..start();
      _run(t, 20);

      t.jumpTo(7);
      expect(t.currentSeat, 7);
      expect(t.elapsed, 0);
      expect(t.running, isFalse);

      t.jumpTo(99);
      expect(t.currentSeat, 7, reason: '不在名單裡就不該跳');
    });

    test('還剩幾位', () {
      final t = _timer();
      expect(t.remainingSpeakers, 2);

      t.next();
      expect(t.remainingSpeakers, 1);

      t.next();
      expect(t.remainingSpeakers, 0);
      expect(t.isLast, isTrue);
    });
  });

  group('法官現場改額度', () {
    test('改長之後剩餘時間跟著變，已講的秒數留著', () {
      final t = _timer(seconds: 60)..start();
      _run(t, 50);
      expect(t.remaining, 10);

      t.setSeconds(180);
      expect(t.elapsed, 50, reason: '已經講掉的不該被抹掉');
      expect(t.remaining, 130);
    });

    test('改短到比已講的還少 → 直接算超時', () {
      final t = _timer(seconds: 180)..start();
      _run(t, 100);

      t.setSeconds(60);
      expect(t.overtime, isTrue);
      expect(t.overtimeSeconds, 40);
    });

    test('0 或負數不接受', () {
      final t = _timer(seconds: 120)
        ..setSeconds(0)
        ..setSeconds(-5);

      expect(t.seconds, 120);
    });
  });

  group('顯示格式', () {
    test('分秒', () {
      expect(SpeechTimer.format(120), '2:00');
      expect(SpeechTimer.format(125), '2:05');
      expect(SpeechTimer.format(59), '0:59');
      expect(SpeechTimer.format(0), '0:00');
    });

    test('超時前面加正號', () {
      expect(SpeechTimer.format(-12), '+0:12');
      expect(SpeechTimer.format(-75), '+1:15');
    });

    test('display 直接吃剩餘秒數', () {
      final t = _timer(seconds: 90)..start();
      expect(t.display, '1:30');

      _run(t, 100);
      expect(t.display, '+0:10');
    });
  });

  group('發言種類的稱呼', () {
    test('四種都有中文名', () {
      expect(SpeechPhase.campaign.labelZh, '警上發言');
      expect(SpeechPhase.day.labelZh, '發言');
      expect(SpeechPhase.runoff.labelZh, '平票 PK 發言');
      expect(SpeechPhase.lastWords.labelZh, '遺言');
    });
  });
}
