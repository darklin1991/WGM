import 'package:flutter/material.dart';

import '../../core/engine/night_flow.dart';
import '../../core/engine/night_flow_machine.dart';
import '../../core/models/game_state.dart';
import '../../core/models/log_entry.dart';
import '../../core/models/night_action.dart';
import '../../core/models/role.dart';
import '../../shared/theme.dart';
import '../day/sheriff_election_page.dart';
import 'night_result_page.dart';
import 'seat_picker.dart';

/// 夜晚流程頁。
///
/// 流程本身（哪一步接哪一步、什麼可選、目標記到哪個欄位）全在
/// [NightFlowMachine] 裡 —— 那是規則，用純 Dart 單元測試涵蓋。
/// 這一頁只負責把狀態機的狀態畫出來，並把操作轉回去。
///
/// **不要在這裡改 [GameState]** —— 進入夜晚（`dayNumber++`、`phase`）由呼叫端
/// 在 push 之前做，撤銷快照才有地方存。
class NightFlowPage extends StatefulWidget {
  const NightFlowPage({super.key, required this.state});

  final GameState state;

  /// 推進到下一夜並開啟夜晚流程頁。
  ///
  /// 狀態變更集中在這裡，頁面本身不碰 —— 法官若在夜晚中途退出，
  /// 至少 `dayNumber` 已經是正確的那一夜，而不是靠頁面的 initState 副作用。
  static Route<void> route(GameState state) {
    enterNight(state);
    return MaterialPageRoute(builder: (_) => NightFlowPage(state: state));
  }

  /// 把狀態推進到下一夜。[route] 會先呼叫它。
  ///
  /// 單獨公開是為了讓測試（與日後的撤銷堆疊）能在建立頁面之前先存快照。
  static void enterNight(GameState state) {
    final isFirstNight = state.dayNumber == 0;
    if (isFirstNight) {
      // 復盤日誌的第一筆 —— 之後每一夜每一天都接在這後面。
      state.log.add(
        round: 0,
        isNight: true,
        kind: LogKind.setup,
        text: '開局：${state.preset.name}（${state.preset.playerCount} 人）',
      );
    }
    state
      ..dayNumber = isFirstNight ? 1 : state.dayNumber + 1
      ..phase = GamePhase.night;
  }

  @override
  State<NightFlowPage> createState() => _NightFlowPageState();
}

class _NightFlowPageState extends State<NightFlowPage> {
  late final NightFlowMachine _m;

  @override
  void initState() {
    super.initState();
    _m = NightFlowMachine(
      state: widget.state,
      night: widget.state.dayNumber,
      isFirstNight: widget.state.dayNumber == 1,
    );
  }

  // 以下短別名純粹是為了讓下面的文案讀起來不那麼囉唆。
  GameState get _state => _m.state;
  NightStep get _step => _m.step;
  NightSub get _sub => _m.sub;
  NightActions get _actions => _m.actions;
  Role get _specialRole => _m.specialRole;
  String get _callName => _m.callName;
  NightSkill get _effectiveSkill => _m.effectiveSkill;
  bool get _hasExtraKnife => _m.hasExtraKnife;

  void _toggleSeat(int seat) => setState(() => _m.toggleSeat(seat));

  void _undo() => setState(_m.undo);

  void _next() {
    setState(_m.next);
    if (!_m.finished) return;

    final showResult = MaterialPageRoute<void>(
      builder: (_) => NightResultPage(
        state: _state,
        outcome: _m.outcome!,
        autoFilledVillagers: _m.autoFilledVillagers,
      ),
    );

    // 第一天的警長競選排在**公布死訊之前** —— 昨晚死的人這時還沒被公布，
    // 照樣可以上警、可以投票。
    final needsElection =
        _state.dayNumber == 1 && _state.preset.rules.sheriffElection;

    Navigator.of(context).pushReplacement(
      needsElection
          ? MaterialPageRoute<void>(
              builder: (context) => SheriffElectionPage(
                state: _state,
                onFinished: () =>
                    Navigator.of(context).pushReplacement(showResult),
              ),
            )
          : showResult,
    );
  }

  /// 手勢卡的對象 —— 獵人本人，或學到槍牌的機械狼。
  ///
  /// 兩者的開槍條件不同（機械狼只有吃刀／吃推能開），所以不能共用獵人的判斷。
  bool get _gestureForMechanic => _step.byMechanicWolf;

  int? get _gestureSeat => _gestureForMechanic
      ? _state.seatOfRole(Roles.mechanicWolf.id)
      : _state.seatOfRole(Roles.hunter.id);

  bool get _gestureCanShoot => _gestureForMechanic
      ? _m.mechanicCanShootTonight
      : _m.hunterCanShootTonight;

  String get _gestureOwnerLabel => _gestureForMechanic
      ? '機械狼（已學到${_state.mechanicWolfLearnedRole?.nameZh ?? "槍牌"}）'
      : '獵人';

  String get _title => switch (_sub) {
        NightSub.registerSeats => '${_step.title}請睜眼',
        NightSub.pickSpecial => '哪一位是${_specialRole.nameZh}？',
        NightSub.witchPotion => '${_step.title}請睜眼',
        NightSub.hunterGesture => '${_step.title}請睜眼',
        NightSub.bearGrowl => '熊請睜眼',
        NightSub.gargoyleConvert =>
          '${_m.currentGargoyleSeat} 號石像鬼要轉換誰？',
        NightSub.mechanicReveal => '機械狼請睜眼',
        NightSub.mechanicKnifeGesture => '機械狼請睜眼',
        NightSub.passThrough => '$_callName請睜眼',
        // 查驗者這時還睜著眼 —— 標題直接寫要比給誰看。
        NightSub.inspectResult => '比給$_callName看',
        NightSub.mechanicKnife =>
          _hasExtraKnife ? '機械狼第一刀要砍誰？' : '機械狼要刀誰？',
        NightSub.secondKnife => '機械狼第二刀要砍誰？',
        NightSub.chooseTarget => switch (_effectiveSkill) {
            NightSkill.guardProtect => '${_step.title}要守誰？',
            NightSkill.wolfKill => '${_step.title}要刀誰？',
            NightSkill.seerInspect => '${_step.title}要查驗誰？',
            NightSkill.psychicInspect => '${_step.title}要查驗誰的身分？',
            NightSkill.charm => '${_step.title}要魅惑誰？',
            NightSkill.mechanicLearn => '機械狼要學習誰的技能？',
            NightSkill.secretAdmire => '暗戀者要暗戀誰？',
            NightSkill.dreamWeave => '攝夢人要攝誰？',
            _ => _step.title,
          },
      };

  String get _hint => switch (_sub) {
        // 獵人、白痴這類角色沒有夜間行動，只是叫起來確認號碼 ——
        // 要講明按下一步就結束，否則法官會等在這裡以為還有技能要選。
        NightSub.registerSeats => _step.skill == NightSkill.none
            ? '確認號碼即可，${_step.title}沒有夜間行動'
            : _step.skill == NightSkill.hunterGesture
                ? '請填入座次號碼，接著給開槍手勢'
                : _step.seatCount > 1
                    ? '請填入 ${_step.seatCount} 位的座次號碼'
                    : '請填入座次號碼',
        NightSub.hunterGesture => '請對獵人做出下面的手勢',
        NightSub.bearGrowl => '只告訴他咆哮或不咆哮，**不要說是哪一位**',
        NightSub.gargoyleConvert => '只能轉換自己的左右鄰座（死亡會往外順延）。'
            '整局只有首夜這一次，不轉請直接按下一步',
        NightSub.pickSpecial => _specialRole.id == Roles.wolfKing.id
            ? '狼王出局時可以開槍帶人，需要單獨記錄'
            : '狼美人出局時被魅惑者會殉情，需要單獨記錄',
        NightSub.witchPotion => '點號碼選毒藥目標；解藥用下方按鈕。都不用就直接按下一步',
        NightSub.mechanicReveal => '法官依下面的內容比給機械狼看',
        NightSub.mechanicKnifeGesture => '機械狼不知道小狼死光了沒，'
            '每晚都要由法官比手勢告知今晚有沒有刀',
        NightSub.passThrough => '照常喊完再讓他們閉眼，不要跳過',
        // 這是唯一能告知的時機 —— 按下一步他就閉眼了。
        NightSub.inspectResult => '趁$_callName還睜著眼，把結果比給他看',
        NightSub.mechanicKnife => '空刀請直接按下一步',
        NightSub.secondKnife => '機械狼已學到狼人，這晚多一刀。'
            '${_actions.wolfTarget == null ? "第一刀空刀。" : "第一刀砍了 ${_actions.wolfTarget} 號，"}'
            '砍同一人可破盾（守衛與解藥都擋不住），不砍請直接按下一步',
        NightSub.chooseTarget => switch (_effectiveSkill) {
            NightSkill.wolfKill => '空刀請直接按下一步',
            NightSkill.guardProtect => _guardHint,
            NightSkill.charm => _charmHint,
            NightSkill.psychicInspect => '通靈師看到的是真實身分，不只好人／狼人',
            NightSkill.mechanicLearn =>
              '整局只能學一次，隔夜起才生效。不學請直接按下一步',
            NightSkill.secretAdmire => '勝負跟著對象的陣營走，選定就固定 ——'
                '對象之後變狼也不改。只有首夜有這一步',
            NightSkill.dreamWeave => '夢遊者免疫今晚的一切傷害（連毒都擋），'
                '但連續兩晚攝同一人會讓他夢死。不攝請直接按下一步',
            _ => '',
          },
      };

  /// 連守／連魅惑的限制生不生效、昨晚是誰，一律問狀態機
  /// （機械狼學到守衛時紀錄與原守衛各自獨立，那也在引擎裡分好了）。
  /// 頁面不重讀規則旗標 —— 同一條規則只有一個判斷點。
  String get _guardHint {
    final last = _m.blockedSeatFor(SeatBlockReason.guardedLastNight);
    if (last != null) {
      return '不可連續兩晚守同一人（昨晚守了 $last 號）';
    }
    return '不守請直接按下一步';
  }

  String get _charmHint {
    final last = _m.blockedSeatFor(SeatBlockReason.charmedLastNight);
    if (last != null) {
      return '不可連續兩晚魅惑同一人（昨晚魅惑了 $last 號）';
    }
    return '不魅惑請直接按下一步';
  }

  /// 解藥只有女巫那一瓶 —— 機械狼學到女巫也拿不到解藥。
  bool get _antidoteAvailable => _state.witchAntidoteAvailable;

  bool get _poisonAvailable => _step.byMechanicWolf
      ? _state.mechanicPoisonAvailable
      : _state.witchPoisonAvailable;

  /// 解藥持有者的座次 —— 只有女巫，用來判斷是不是自救。
  int? get _potionOwnerSeat => _state.seatOfRole(Roles.witch.id);

  /// 解藥那一排為什麼是暗的。可用時回傳 null。
  String? get _antidoteBlockedReason {
    if (_step.byMechanicWolf) return '機械狼學到女巫只拿得到毒藥，沒有解藥';
    if (!_antidoteAvailable) return '解藥已在之前的夜晚用掉了';
    if (_m.knifedSeats.isEmpty) return '今晚沒有人被刀';
    if (_m.healableSeats.isEmpty) {
      if (_m.picked.isNotEmpty) return '已選毒藥目標，本局不可同夜雙藥';
      final self = _potionOwnerSeat;
      if (self != null && _m.knifedSeats.contains(self)) {
        return '刀口是女巫自己，本局規則不可自救';
      }
      return '解藥用不了';
    }
    return null;
  }

  /// 毒藥那一排的說明。
  String get _poisonLabel {
    if (!_poisonAvailable) return '毒藥已在之前的夜晚用掉了';
    if (!_m.poisonUsable) return '已下解藥，本局不可同夜雙藥';
    if (_m.picked.isEmpty) return '點上方號碼選毒藥目標';
    return '毒 ${_m.picked.first} 號';
  }

  /// 禁選原因的顯示文字。原因本身由狀態機判定，這裡只負責措辭。
  Map<int, String>? get _disabledReasons {
    final blocked = _m.blockedSeats;
    if (blocked == null) return null;
    return {
      for (final e in blocked.entries)
        e.key: switch (e.value) {
          SeatBlockReason.guardedLastNight => '昨晚已守',
          SeatBlockReason.charmedLastNight => '昨晚已魅惑',
          SeatBlockReason.wolfBeautySelfKill => '狼美人不能自刀',
          SeatBlockReason.secretAdmirerSelf => '不能暗戀自己',
          SeatBlockReason.whiteCatPending => '白貓已翻牌，離場前不能被指定',
          SeatBlockReason.mechanicSelfLearn => '不能學自己',
          SeatBlockReason.witchDualUse => '本局不可同夜雙藥',
        },
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepLabel = '${_m.stepIndex + 1}/${_m.steps.length}';

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${_actions.night} 夜　$stepLabel'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 10, right: 16),
            child: Row(
              children: [
                for (var i = 0; i < _m.steps.length; i++) ...[
                  if (i > 0)
                    Text(
                      ' → ',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  Text(
                    _m.steps[i].title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          i == _m.stepIndex ? FontWeight.w800 : FontWeight.w400,
                      color: i == _m.stepIndex
                          ? scheme.primary
                          : i < _m.stepIndex
                              ? scheme.onSurfaceVariant
                              : scheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_hint.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _hint,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: _sub == NightSub.passThrough
                  ? _PassThroughCard(name: _callName)
                  : _sub == NightSub.mechanicKnifeGesture
                  ? _MechanicKnifeGestureCard(
                      seat: _state.seatOfRole(Roles.mechanicWolf.id),
                      hasKnife: _m.state.mechanicWolfCarriesKnife,
                      extraKnife: _hasExtraKnife,
                    )
                  : _sub == NightSub.mechanicReveal
                  ? _MechanicRevealCard(
                      seat: _state.seatOfRole(Roles.mechanicWolf.id),
                      learnedRole: _m.mechanicLearnedRoleNow,
                      learnedTonight: _state.mechanicWolfLearnedRole == null &&
                          _actions.mechanicWolfLearnTarget != null,
                      canShoot:
                          _m.mechanicCanShootTonight,
                    )
                  : _sub == NightSub.bearGrowl
                  ? _BearGrowlCard(
                      neighbours: _m.bearNeighbors,
                      growls: _m.bearGrowls,
                    )
                  : _sub == NightSub.inspectResult
                  ? _InspectResultCard(
                      reveal: _m.inspectReveal!,
                      ownerLabel: _callName,
                    )
                  : _sub == NightSub.hunterGesture
                  ? _HunterGestureCard(
                      ownerLabel: _gestureOwnerLabel,
                      seat: _gestureSeat,
                      canShoot: _gestureCanShoot,
                      poisonedTonight: _gestureSeat != null &&
                          (_actions.witchPoisonTarget == _gestureSeat ||
                              _actions.mechanicPoisonTarget == _gestureSeat),
                    )
                  : _sub == NightSub.witchPotion
                  ? _WitchPanel(
                      knifedSeats: _m.knifedSeats,
                      healableSeats: _m.healableSeats,
                      healTarget: _m.healTarget,
                      onToggleHeal: (seat) =>
                          setState(() => _m.toggleHeal(seat)),
                      antidoteBlockedReason: _antidoteBlockedReason,
                      poisonLabel: _poisonLabel,
                      poisonTarget:
                          _m.picked.isEmpty ? null : _m.picked.first,
                      poisonUsable: _m.poisonUsable,
                      seatPicker: SeatPicker(
                        state: _state,
                        selected: _m.picked,
                        onTap: _toggleSeat,
                        selectableSeats: _m.selectableSeats,
                        disabledReason: _disabledReasons,
                        showRoleName: true,
                      ),
                    )
                  : SeatPicker(
                      state: _state,
                      selected: _m.picked,
                      onTap: _toggleSeat,
                      selectableSeats: _m.selectableSeats,
                      disabledReason: _disabledReasons,
                      showRoleName: _sub != NightSub.registerSeats,
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  if (_m.requiredPickCount > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '已選 ${_m.picked.length}/${_m.requiredPickCount}：'
                        '${(_m.picked.toList()..sort()).join('、')}',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  // 法官現場誤觸是常態，撤銷要隨手按得到；
                  // 但排在「下一步」上方、樣式較低調，避免反射性點錯。
                  if (_m.canUndo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: _undo,
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: Text('撤銷上一步（${_m.undoLabel}）'),
                      ),
                    ),
                  FilledButton(
                    onPressed: _m.canProceed ? _next : null,
                    child: Text(_m.canProceed ? '下一步' : _blockedLabel),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _blockedLabel => switch (_sub) {
        NightSub.registerSeats =>
          '請選滿 ${_step.seatCount} 位（已選 ${_m.picked.length}）',
        NightSub.pickSpecial => '請指定${_specialRole.nameZh}',
        _ => '下一步',
      };
}

/// 女巫那一頁：刀口寫在中間，解藥與毒藥並列在下方。
///
/// 兩瓶藥收在同一畫面，法官一眼看完再決定 —— 原本拆成兩步要按兩次
/// 「下一步」，現場摸黑往前走很容易搞不清楚自己在哪一格。
class _WitchPanel extends StatelessWidget {
  const _WitchPanel({
    required this.knifedSeats,
    required this.healableSeats,
    required this.healTarget,
    required this.onToggleHeal,
    required this.antidoteBlockedReason,
    required this.poisonLabel,
    required this.poisonTarget,
    required this.poisonUsable,
    required this.seatPicker,
  });

  final List<int> knifedSeats;
  final List<int> healableSeats;
  final int? healTarget;
  final ValueChanged<int> onToggleHeal;

  /// 解藥不能用的原因；null 表示可用。
  final String? antidoteBlockedReason;

  final String poisonLabel;
  final int? poisonTarget;
  final bool poisonUsable;

  final Widget seatPicker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final antidoteOn = healTarget != null;
    final poisonOn = poisonTarget != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- 中間：今晚誰被刀 ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: WgmTheme.wolfColor.withValues(alpha: 0.10),
                border: Border.all(
                  color: WgmTheme.wolfColor.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '今晚的刀口',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    knifedSeats.isEmpty
                        ? '沒有人被刀'
                        : '${knifedSeats.join('、')} 號',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: knifedSeats.isEmpty
                          ? scheme.onSurfaceVariant
                          : WgmTheme.wolfColor,
                    ),
                  ),
                  if (knifedSeats.length > 1) ...[
                    const SizedBox(height: 6),
                    Text(
                      '雙刀 —— 解藥只有一瓶，最多救一位',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        seatPicker,

        // ---- 下方：解藥與毒藥 ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PotionRow(
                label: '解藥',
                active: antidoteOn,
                activeColor: WgmTheme.godColor,
                // 能用的時候才變亮。
                blockedReason: antidoteBlockedReason,
                child: antidoteBlockedReason != null
                    ? null
                    : Wrap(
                        spacing: 8,
                        children: [
                          for (final seat in healableSeats)
                            ChoiceChip(
                              label: Text('救 $seat 號'),
                              selected: healTarget == seat,
                              onSelected: (_) => onToggleHeal(seat),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              _PotionRow(
                label: '毒藥',
                // 點了號碼才變亮。
                active: poisonOn,
                activeColor: WgmTheme.wolfColor,
                blockedReason: poisonUsable ? null : poisonLabel,
                child: poisonUsable
                    ? Text(
                        poisonLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              poisonOn ? FontWeight.w800 : FontWeight.w400,
                          color: poisonOn
                              ? WgmTheme.wolfColor
                              : scheme.onSurfaceVariant,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 解藥／毒藥各自一排。亮起來表示這一瓶今晚會用掉。
class _PotionRow extends StatelessWidget {
  const _PotionRow({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.blockedReason,
    required this.child,
  });

  final String label;
  final bool active;
  final Color activeColor;

  /// 不能用的原因；null 表示可用。
  final String? blockedReason;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocked = blockedReason != null;
    final color = blocked
        ? scheme.onSurfaceVariant
        : (active ? activeColor : scheme.onSurface);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: active ? activeColor.withValues(alpha: 0.14) : null,
        border: Border.all(
          color: active
              ? activeColor
              : scheme.outlineVariant.withValues(alpha: blocked ? 0.4 : 0.8),
          width: active ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: blocked
                ? Text(
                    blockedReason!,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : (child ?? const SizedBox.shrink()),
          ),
        ],
      ),
    );
  }
}

/// 走過場卡：角色已全滅，但這一步照喊不誤。
///
/// 法官如果因為狼死光就不喊「狼人請睜眼」，玩家馬上從流程長度聽出來 ——
/// 所以這張卡的重點是提醒法官**照常喊、照常停頓**，不要露餡。
class _PassThroughCard extends StatelessWidget {
  const _PassThroughCard({required this.name});

  /// 要喊的身分名稱（不含「（守衛）」這類後綴）。
  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.volume_up_rounded,
                size: 56,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                '照常喊「$name請睜眼」',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '$name已全數出局，沒有人會睜眼 —— 但還是要照常喊、照常停頓幾秒'
                '再喊閉眼。跳過的話，玩家從流程長度就聽得出來。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 機械狼的開刀手勢卡。
///
/// 機械狼不與小狼相認，自己不知道小狼是不是死光了 —— 有沒有刀只有法官知道，
/// 所以每晚都要比這個手勢。做成一眼可辨的大卡片，現場光線差、動作要快。
class _MechanicKnifeGestureCard extends StatelessWidget {
  const _MechanicKnifeGestureCard({
    required this.seat,
    required this.hasKnife,
    required this.extraKnife,
  });

  final int? seat;

  /// 今晚有沒有刀（其餘小狼是否已全數出局）。
  final bool hasKnife;

  /// 有刀且學到狼人時，這晚可以砍兩刀。
  final bool extraKnife;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = hasKnife ? WgmTheme.wolfColor : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Column(
                children: [
                  Icon(
                    hasKnife
                        ? Icons.thumb_up_rounded
                        : Icons.thumb_down_rounded,
                    size: 72,
                    color: color,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    hasKnife ? '拇指向上' : '拇指向下',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasKnife
                        ? (extraKnife ? '今晚有刀，可以砍兩刀' : '今晚有刀')
                        : '今晚沒有刀',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            switch (true) {
              _ when seat == null => '此局沒有機械狼',
              _ when !hasKnife => '還有小狼存活，機械狼（$seat 號）今晚沒有刀。'
                  '要等其餘小狼全數出局才開得了刀。',
              _ when extraKnife => '小狼已全數出局，機械狼（$seat 號）獨自帶刀；'
                  '牠學到狼人，這晚可以砍兩刀 —— 第二刀留到「狼人請睜眼」那一步再問。',
              _ => '小狼已全數出局，機械狼（$seat 號）獨自帶刀。',
            },
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 機械狼的夜晚結尾告知卡。
///
/// 機械狼是第一個睜眼的，那時候身分都還沒登記完、女巫的毒也還沒收 ——
/// 所以「學到什麼」和「能不能開槍」都得等到夜晚結尾才告知得了。
class _MechanicRevealCard extends StatelessWidget {
  const _MechanicRevealCard({
    required this.seat,
    required this.learnedRole,
    required this.learnedTonight,
    required this.canShoot,
  });

  final int? seat;

  /// 機械狼目前的身分；null 表示還沒學過。
  final Role? learnedRole;

  /// 是不是本夜剛學到的（本夜才要告知身分；之前學的只是每晚給手勢）。
  final bool learnedTonight;

  /// 學到槍牌時，今晚出局能不能開槍。
  final bool canShoot;

  bool get _hasGun =>
      learnedRole != null && Roles.gunRoleIds.contains(learnedRole!.id);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    learnedTonight ? '今晚學到的身分' : '目前持有的身分',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    learnedRole?.nameZh ?? '今晚沒有學習',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    switch (true) {
                      _ when learnedRole == null =>
                        '機械狼沒有指定學習對象，之後的夜晚仍可再學。',
                      _ when learnedTonight =>
                        '請比給 $seat 號機械狼看。技能自**下一夜**起生效，整局只能學這一次。',
                      _ => '之前的夜晚已經學到，這裡只是再確認一次。',
                    },
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_hasGun) ...[
            const SizedBox(height: 12),
            _HunterGestureCard(
              ownerLabel: '機械狼（已學到${learnedRole!.nameZh}）',
              seat: seat,
              canShoot: canShoot,
              poisonedTonight: !canShoot,
            ),
          ],
        ],
      ),
    );
  }
}

/// 獵人開槍手勢卡。
///
/// 法官每晚都要叫獵人起來，用手勢告知技能是否可用。做成一眼可辨的大卡片，
/// 因為現場光線差、動作要快，法官不該還要自己推「被毒了所以不能開槍」。
class _HunterGestureCard extends StatelessWidget {
  const _HunterGestureCard({
    required this.ownerLabel,
    required this.seat,
    required this.canShoot,
    required this.poisonedTonight,
  });

  /// 這張手勢卡是給誰的：「獵人」或「機械狼（已學到獵人）」。
  final String ownerLabel;

  final int? seat;
  final bool canShoot;
  final bool poisonedTonight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = canShoot ? WgmTheme.godColor : WgmTheme.wolfColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Column(
                children: [
                  Icon(
                    canShoot
                        ? Icons.thumb_up_rounded
                        : Icons.thumb_down_rounded,
                    size: 72,
                    color: color,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    canShoot ? '拇指向上' : '拇指向下',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    canShoot ? '可以開槍' : '不可開槍',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            switch (true) {
              _ when seat == null => '此局沒有$ownerLabel',
              _ when poisonedTonight => '$ownerLabel（$seat 號）今晚被毒，'
                  '依規則不可開槍',
              _ when canShoot => '$ownerLabel為 $seat 號，技能正常',
              _ => '$ownerLabel（$seat 號）目前無法開槍',
            },
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 查驗結果卡：法官趁查驗者睜著眼時比給他看。
///
/// 預言家只分金水／查殺；通靈師看到的是真實身分，所以把角色名寫出來。
class _InspectResultCard extends StatelessWidget {
  const _InspectResultCard({required this.reveal, required this.ownerLabel});

  final InspectReveal reveal;

  /// 這張卡是給誰的：「預言家」「通靈師」，或機械狼學來的那一種。
  final String ownerLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWolf = reveal.sawWolf;
    final color = isWolf ? WgmTheme.wolfColor : WgmTheme.godColor;
    final unknown = reveal.role == null;

    // 通靈師報的是身分名；預言家報金水／查殺。
    final headline = reveal.isPsychic
        ? (reveal.role?.nameZh ?? '尚未登記')
        : (isWolf ? '查殺' : '金水');
    final sub = reveal.isPsychic
        ? '${reveal.seat} 號的真實身分'
        : (isWolf ? '${reveal.seat} 號是狼人' : '${reveal.seat} 號是好人');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Column(
                children: [
                  Icon(
                    reveal.isPsychic
                        ? Icons.auto_awesome_rounded
                        : (isWolf
                            ? Icons.thumb_down_rounded
                            : Icons.thumb_up_rounded),
                    size: 72,
                    color: color,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    headline,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            unknown
                // 首夜邊問邊登記時，排在查驗者後面的角色還沒登記。
                // 結算會把剩下的座次補成平民，所以這時照金水給就是對的。
                ? '${reveal.seat} 號的身分還沒登記，結算後會是平民 —— 比金水給$ownerLabel'
                : '按下一步之後$ownerLabel就閉眼了，確認已經比給他看',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 熊的咆哮卡。
///
/// **只給是／否**，鄰座號碼寫在下面是給法官核對用的 ——
/// 那兩個號碼不能講出來，講了熊就直接知道狼在哪一側。
class _BearGrowlCard extends StatelessWidget {
  const _BearGrowlCard({required this.neighbours, required this.growls});

  /// 今晚兩側的鄰座（死亡會往外順延，所以每晚可能不同）。
  final List<int> neighbours;

  final bool growls;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = growls ? WgmTheme.wolfColor : WgmTheme.godColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Column(
                children: [
                  Icon(
                    growls
                        ? Icons.campaign_rounded
                        : Icons.volume_off_rounded,
                    size: 72,
                    color: color,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    growls ? '咆哮' : '不咆哮',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    growls ? '兩側有狼' : '兩側都沒有狼',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            neighbours.isEmpty
                ? '場上沒有其他存活玩家，沒有鄰座可看'
                // 號碼只給法官核對，**不能講給熊聽**。
                : '今晚的鄰座是 ${neighbours.join("、")} 號'
                    '（法官核對用，不要念出來）。鄰座出局會往外順延，每晚重算',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
