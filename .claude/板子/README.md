# 板子資訊

每個板子一份，檔名對應 `assets/presets/` 裡的 `presetId`，一對一。

| 文件 | 板子 | 人數 | 組成 | 特殊角色 |
|---|---|---|---|---|
| [12p_yu_nu_lie_bai.md](12p_yu_nu_lie_bai.md) | 12人 預女獵白 | 12 | 4狼 4神 4民 | 白痴 |
| [12p_yu_nu_lie_shou.md](12p_yu_nu_lie_shou.md) | 12人 預女獵守 | 12 | 4狼 4神 4民 | 守衛 |
| [12p_langwang_shouwei.md](12p_langwang_shouwei.md) | 12人 狼王守衛局 | 12 | 4狼 4神 4民 | 狼王、守衛 |
| [12p_jixielang_tonglingshi.md](12p_jixielang_tonglingshi.md) | 12人 機械狼通靈師 | 12 | 4狼 4神 4民 | 機械狼、通靈師 |
| [12p_langmei_qishi.md](12p_langmei_qishi.md) | 12人 狼美騎士 | 12 | 4狼 4神 4民 | 狼美人、騎士 |
| [12p_fengsheng_dieying.md](12p_fengsheng_dieying.md) | 12人 風聲諜影 | 12 | 3狼 9神 0民 | 覺醒石像鬼、覺醒隱狼、魔鏡少女、熊、攝夢人、河豚、白貓、暗戀者 |

風聲諜影是目前唯一**沒有平民**的板子（12 人全是特殊身分），也是唯一會
讓陣營在局中改變的板子（轉換）。新增類似機制前先讀它的文件。

**實際生效的永遠是 JSON。** 這些文件是給人看的對照與沿革 —— 改規則請改 `assets/presets/*.json`，然後回來更新對應的那一份。

角色與衝突裁決的**通則**寫在 `CLAUDE.md`（衝突裁決表、規則旗標表）；這裡只寫各板子自己的組成與差異。

> 專案裡統一用「板子」這個詞（`Preset`），不用「版子」。

## 六個板子的共通旗標

```
guardHealKills            true            同守同救致死（奶穿）
witchDualUseSameNight     false           同夜不可解毒雙開
guardCannotRepeatTarget   true            守衛不可連守同一人
poisonedHunterCannotShoot true            獵人被毒不可開槍
sheriffVoteWeight         1.5             警長票權
tieBreak                  pk_then_none    平票 PK，再平則無人出局
winCondition              sideElimination 屠邊
wolfSelfDetonateEndsDay   true            自爆立即進夜
```

`witchSelfHealNight` **六個板子都刻意沒填** —— 由 `RuleFlags.defaultWitchSelfHealNight(playerCount)` 依人數推導。9 人以上一律不可自救，所以這六個 12 人板子的女巫都不能自救。新增板子時不必記得填。

推導的另一邊（8 人以下的小局僅首夜可自救）目前**沒有任何內建板子會走到** —— 六個板子都是 12 人。那條分支仍由 `test/core/preset_test.dart` 的單元測試涵蓋，不會因為沒有板子用到就失效；日後若要加小局板子，直接加即可，規則自動生效。

## 六個板子共通的夜晚行為（擔當 2026-09-19 指定）

這三條是**全域**的，不是哪個板子特有的。各板子的 MD 只記自己被影響到的地方。

| 行為 | 說明 |
|---|---|
| **身分在開局前配完** | 「進入第一夜」要配滿全部身分才會亮。夜裡不再問「你是幾號」，角色照樣喊、技能照樣收 |
| **沒有夜間技能的角色夜裡不叫** | 白痴、騎士那一步本來只是為了問座次，座次已知就整步跳過。第二夜起本來就不叫他們，流程長度反而一致 |
| **查驗結果當場給** | 預言家／通靈師選完目標後停在結果頁，法官比完金水／查殺（通靈師是真實身分）他才閉眼。只留在夜晚結算頁來不及 —— 那時查驗者早就閉眼了 |

前兩條的由來是一個會讓**所有板子首夜卡死**的 bug：登記頁要求先配滿身分，
夜晚流程卻還在問座次，可選座次＝空集合，下一步鍵永遠是灰的。

## 新增板子要注意的

1. **丟一份 JSON 到 `assets/presets/` 就好**，不必改程式 —— 前提是用到的角色都已經在 `Roles` 裡。要用新角色就得先加角色定義與行動處理。
2. **載入時會驗證**，不合格直接擋下並指出是哪個板子哪個欄位：
   - `roles` 的 count 總和要等於 `playerCount`
   - 一般狼、平民與覺醒石像鬼**以外**的身分每個板子只能 1 位（引擎的 `seatOfRole` 只回傳第一個）
   - 同一角色不可重複列出
   - **有夜間行動的角色都必須排進 `nightOrder`** —— 漏了會被默默接在最後，法官照著跑就會出錯
3. **`test/core/preset_assets_test.dart` 會直接讀這個目錄的實際檔案跑驗證**，新板子自動納入，違規在測試階段就會被抓到。
4. 順序有資訊時序考量的角色（查真實身分的、需要手勢的）**不要隨手往前搬**，理由見各板子文件與 CLAUDE.md。
5. 新增板子時，**在這裡也加一份對應的 MD** 並更新上面的表。
