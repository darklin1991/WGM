# 板子資訊

每個板子一份，檔名對應 `assets/presets/` 裡的 `presetId`，一對一。

| 文件 | 板子 | 人數 | 組成 | 特殊角色 |
|---|---|---|---|---|
| [9p_beginner.md](9p_beginner.md) | 9人 新手局 | 9 | 3狼 3神 3民 | — |
| [12p_yu_nu_lie_bai.md](12p_yu_nu_lie_bai.md) | 12人 預女獵白 | 12 | 4狼 4神 4民 | 白痴 |
| [12p_yu_nu_lie_shou.md](12p_yu_nu_lie_shou.md) | 12人 預女獵守 | 12 | 4狼 4神 4民 | 守衛 |
| [12p_langwang_shouwei.md](12p_langwang_shouwei.md) | 12人 狼王守衛局 | 12 | 4狼 4神 4民 | 狼王、守衛 |
| [12p_jixielang_tonglingshi.md](12p_jixielang_tonglingshi.md) | 12人 機械狼通靈師 | 12 | 4狼 4神 4民 | 機械狼、通靈師 |
| [12p_langmei_qishi.md](12p_langmei_qishi.md) | 12人 狼美騎士 | 12 | 4狼 4神 4民 | 狼美人、騎士 |

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

`witchSelfHealNight` **六個板子都刻意沒填** —— 由 `RuleFlags.defaultWitchSelfHealNight(playerCount)` 依人數推導。9 人以上一律不可自救，所以這六個板子的女巫都不能自救。新增板子時不必記得填。

## 新增板子要注意的

1. **丟一份 JSON 到 `assets/presets/` 就好**，不必改程式 —— 前提是用到的角色都已經在 `Roles` 裡。要用新角色就得先加角色定義與行動處理。
2. **載入時會驗證**，不合格直接擋下並指出是哪個板子哪個欄位：
   - `roles` 的 count 總和要等於 `playerCount`
   - 一般狼與平民**以外**的身分每個板子只能 1 位（引擎的 `seatOfRole` 只回傳第一個）
   - 同一角色不可重複列出
   - **有夜間行動的角色都必須排進 `nightOrder`** —— 漏了會被默默接在最後，法官照著跑就會出錯
3. **`test/core/preset_assets_test.dart` 會直接讀這個目錄的實際檔案跑驗證**，新板子自動納入，違規在測試階段就會被抓到。
4. 順序有資訊時序考量的角色（查真實身分的、需要手勢的）**不要隨手往前搬**，理由見各板子文件與 CLAUDE.md。
5. 新增板子時，**在這裡也加一份對應的 MD** 並更新上面的表。
