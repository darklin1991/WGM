# CLAUDE.md

本檔提供 Claude Code 在此 repo 工作時所需的專案知識。

## 專案概述

**WGM (Werewolf Game Master)** — Android 手機應用程式，狼人殺**法官（上帝）輔助工具**。

法官一人持有手機，負責開局配置、夜晚結算、白天流程控制、勝負判定與復盤。玩家仍以口頭語音進行遊戲，不使用 App。

不同的**板子**（角色配置）有不同的角色組合、夜晚行動順序與規則細節。App 不把板子寫死在程式碼裡，而是讀取**板子設定檔（JSON）**驅動整局流程。新增板子＝新增一份 JSON。

## 技術決策（已確認）

| 項目 | 決定 | 理由 |
|---|---|---|
| 框架 | Flutter (Dart) | 跨平台 UI 一致、法官操作介面客製化需求高 |
| 目標平台 | **僅 Android** | 可側載 APK，不必上架 |
| web/ 目錄 | **僅供開發預覽，不是交付目標** | `flutter run -d chrome` 熱重載幾秒就能看到 UI 改動，比等 Gradle build 五分鐘快得多。不要為 web 做任何相容處理或功能妥協 |
| 板子定義 | **設定檔驅動（JSON）** | 新增板子與規則變體不必改程式、不必重新發版 |
| 規則變體 | **寫在板子設定檔的 `rules` 旗標裡** | 不同賽制規則不同（同守同救、女巫自救…），由旗標控制 |
| 資料儲存 | **純單機本地** | 無後端、無連線、無多人同步 |
| 使用情境 | **只有法官操作 App** | 玩家不連線；不需帳號、不需即時通訊 |
| 版本控管 | **git ＋ GitHub remote（public）** | 擔當 2026-09-15 改為上傳 `https://github.com/darklin1991/WGM.git`（公開 repo）。提交前確認不含機敏資訊 

未經擔當同意不要引入：後端 API、連線多人、iOS 支援、玩家端介面。這些明確排除在現階段範圍外。

## 目前狀態

**開發環境已建置完成並實測通過**（已成功產出 debug APK）。

⚠️ **此 repo 尚未初始化 Flutter 專案** —— 下一步是：

```
flutter create --platforms=android --org tw.com.aoci --project-name wgm .
git init
```

## 開發環境（已建置，2026-08-24 驗證）

| 元件 | 版本 | 位置 |
|---|---|---|
| Flutter | 3.47.1 stable (Dart 3.13.1) | `D:\flutter` |
| Android Studio | 2026.1.3.7 | `C:\Program Files\Android\Android Studio` |
| JDK | 25.0.2（Android Studio 自帶 jbr） | `…\Android Studio\jbr` |
| Android SDK | platform-tools 37.0.1、android-36 / android-37.1、build-tools 36.0.0 / 37.0.0 | `D:\Android\Sdk` |
| NDK | 28.2.13676358 (r28c) | `D:\Android\Sdk\ndk` |
| Gradle | 9.3.1（Flutter 自動取得） | `~\.gradle` |

已持久寫入使用者層級環境變數：`JAVA_HOME`、`ANDROID_HOME`、PATH（含 `D:\flutter\bin`、`D:\Android\Sdk\platform-tools`、jbr 的 bin）。開新終端即生效。

### 環境踩坑筆記（重裝或換機必讀）

網路上多數 Flutter 環境建置教學已經過時，以下是實際狀況：

**1. `sdkmanager` 已被 Google 棄用且會崩潰**

改用新的 `android` CLI，套件命名也從分號改成斜線：

```
D:\Android\Sdk\cmdline-tools\latest\bin\android.exe --sdk D:\Android\Sdk --no-metrics sdk list --all "ndk*"
D:\Android\Sdk\cmdline-tools\latest\bin\android.exe --sdk D:\Android\Sdk --no-metrics sdk install ndk/28.2.13676358
```

舊寫法 `platforms;android-36` → 新寫法 `platforms/android-36`。

**2. 新 CLI 安裝成功後仍回傳 crash 的 exit code**

安裝完成後工具自身會以 `-1073740791`（`0xC0000409`，STATUS_STACK_BUFFER_OVERRUN）結束。**不要用 exit code 判斷成敗，要驗證檔案是否存在**，例如 `D:\Android\Sdk\ndk\28.2.13676358\source.properties`。

**3. NDK 必須預先手動安裝**

Flutter 專案的 `ndkVersion = flutter.ndkVersion`（目前為 28.2.13676358）。若 NDK 不存在，Gradle 會去呼叫那個已壞掉的 `sdkmanager.bat`，build 直接失敗並吐出誤導訊息 `Package ndk not found`（其實遠端倉庫裡有）。**先用新 CLI 裝好 NDK**，Gradle 就不會去碰 sdkmanager。

其他套件（platform、build-tools）Gradle 走 AGP 內建下載機制，會自動補裝，不經 sdkmanager，沒有這個問題。

**4. Flutter 3.47.1 實際使用 API 36 / build-tools 36**

不是最新的 37.x。Gradle 第一次 build 時會自己補裝 android-36 與 build-tools 36.0.0。手動裝 37.x 沒有必要（裝了也無害，只是多佔空間）。

**5. `flutter doctor` 有兩條警告可以忽略**

- **Android license status unknown** —— 誤報。新 `android` CLI 在安裝套件時就自動接受授權（`D:\Android\Sdk\licenses\android-sdk-license` 確實存在），且它會明確回報「`--licenses` 選項已不再需要」；Flutter 仍用舊 sdkmanager 的方式查詢才顯示 unknown。實際 build 時 Gradle 的授權檢查是通過的（`License for package ... accepted`）。
- **Visual Studio not installed** —— 那是開發 **Windows 桌面** App 才需要的。本專案只做 Android，不必為它裝好幾 GB 的 C++ 工具鏈。

**6. JDK 25 可正常運作**

Gradle 9.3.1 搭 JDK 25 沒問題，只有無害的 `--enable-native-access` 警告。不需要另外裝 JDK 17/21。

## 常用指令（專案建立後）

```
flutter pub get                  # 安裝套件
flutter run                      # 在連線的 Android 裝置上除錯執行
flutter devices                  # 列出可用裝置
flutter analyze                  # 靜態分析（提交前必跑）
flutter test                     # 執行全部測試
flutter test test/xxx_test.dart  # 執行單一測試檔
dart format .                    # 格式化
flutter build apk --release      # 產生 release APK（側載用）
flutter clean                    # 清除建置產物
```

---

# 領域詞彙對照

程式碼用英文命名，但需求與討論用中文術語。對照如下，命名請一致：

| 中文 | 程式碼命名 | 說明 |
|---|---|---|
| 板子／配置 | `Preset` | 人數＋角色組合＋夜晚順序＋規則旗標 |
| 法官／上帝 | `moderator` | App 的唯一使用者 |
| 座次 | `seat` | 環狀，計算發言順序時需繞回 |
| 屠邊 | `sideElimination` | 神職全滅 **或** 平民全滅 → 狼勝 |
| 屠城 | `totalElimination` | 所有好人全滅 → 狼勝 |
| 刀 | `wolfKill` | 狼人擊殺 |
| 守 | `guardProtect` | 守衛守護 |
| 解藥／救 | `witchAntidote` | 女巫解藥 |
| 毒 | `witchPoison` | 女巫毒藥 |
| 查驗 | `seerInspect` | 預言家查驗 |
| 金水 | `verifiedGood` | 查驗結果為好人 |
| 查殺 | `verifiedWolf` | 查驗結果為狼人 |
| 奶穿／同守同救 | `guardHealConflict` | 同時被守與被救，依規則致死 |
| 開槍 | `hunterShot` | 獵人死亡技能 |
| 自爆 | `wolfSelfDetonate` | 狼人白天自爆，直接進夜 |
| 白痴翻牌 | `idiotReveal` | 被放逐時翻牌不死，失去投票權 |
| 警長 | `sheriff` | 票權加權 |
| 上警 | `runForSheriff` | 參選 |
| 退水 | `withdrawFromElection` | 退出競選 |
| 警上發言 | `campaignSpeech` | 競選發言 |
| 警徽流 | `badgeSuccession` | 警長死亡時警徽移交順序 |
| 警左／警右 | `fromSheriffLeft` / `fromSheriffRight` | 發言起點 |
| 死左／死右 | `fromDeceasedLeft` / `fromDeceasedRight` | 發言起點 |
| 平票 PK | `tieBreakRound` | 平票者再發言後重投 |
| 放逐 | `exile` | 投票出局 |
| 禁言 | `silenced` | 該輪不可發言 |
| 復盤 | `review` | 賽後檢討 |

---

# 功能模組

## 1. Game Setup & Registry（房間與配置管理）

- **板子配置 (Preset Builder)**：自訂人數與身分組合（如預女獵白、狼王守衛局）。可從內建範本建立、修改後另存。
- **玩家管理 (Player Registry)**：編號、座次、生死狀態、狀態標記。

狀態標記分兩類，**不要混在一起**：

- **事實標記**（引擎結算用）：`guarded`、`knifed`、`healed`、`poisoned`、`shot`、`exiled`
- **資訊標記**（法官備忘與復盤用，不影響結算）：`verifiedGood`（金水）、`verifiedWolf`（查殺）、`silenced`（禁言）

## 2. Night Phase Arbitrator（夜晚結算器）

- **行動佇列 (Action Queue)**：依角色優先級排序技能釋放順序。順序來自板子設定檔的 `nightOrder`。
- **衝突裁決 (Conflict Resolution)**：同守同救（奶穿）、自爆與鎖定判定。

**關鍵：收集與結算必須分開兩階段。**

1. **收集階段**：法官依 `nightOrder` 逐一輸入各角色行動，只記錄意圖，不做判定。
2. **結算階段**：全部收集完後一次性套用衝突規則，產出當夜死亡名單。

**女巫的資訊時序是特例**（也是奶穿的成因）：女巫看到的是「**狼刀目標**」，**不套用守衛結果**。因此女巫可能對一個已被守衛守住的人用解藥，最終才在結算階段判定為同守同救。實作時不要為了方便就先把守衛結果算進去給女巫看 —— 那會讓奶穿永遠不可能發生。

## 3. Day Phase Controller（白天流程控制）

- **警長競選 (Sheriff Election)**：上警 → 警上發言 → 退水 → 投票 → 警徽流設定。
- **發言與計時 (Turn & Timer)**：發言順序（警左／警右／死左／死右）、計時器。
- **投票管理 (Voting System)**：投票紀錄、平票 PK、放逐結算。

## 4. Settlement & Win Check（勝負與結算引擎）

- 屠邊（好人神職全滅 **或** 平民全滅）或屠城（好人全滅）規則判定，由 `winCondition` 旗標決定採用哪種。
- 每次死亡事件後都要重新檢查勝負，不只在白天結束時檢查。
- **遊戲歷史回放 (Game Log)** 與復盤資料產出。

---

# 架構

```
lib/
  main.dart
  core/
    models/
      role.dart            # 角色定義（陣營、夜晚行動、優先級）
      preset.dart          # 板子配置＋規則旗標
      player.dart          # 玩家（編號、座次、生死、狀態標記）
      game_state.dart      # 完整局面狀態（可變，就地修改）
      night_action.dart    # 夜間行動意圖
      log_entry.dart       # 復盤日誌項目（只寫入，不用於推導狀態）
    engine/
      night_arbitrator.dart  # 夜晚結算：行動佇列＋衝突裁決
      day_controller.dart    # 白天流程狀態機
      vote_resolver.dart     # 投票／平票 PK／放逐
      win_checker.dart       # 屠邊／屠城判定
      speech_order.dart      # 發言順序計算
      seat_ring.dart         # 環狀座次走訪（跳過死亡玩家）
      undo_stack.dart        # 階段快照堆疊（撤銷用）
    rules/
      rule_flags.dart        # 規則旗標解析與預設值
    log/
      game_log.dart          # 操作日誌、回放、復盤資料匯出
    storage/
      game_repository.dart   # 本地持久化
  features/
    setup/     # 板子配置＋玩家登記
    night/     # 夜晚結算介面
    day/       # 白天流程（競選、發言計時、投票）
    review/    # 復盤／回放
  shared/      # 共用 widget、主題、工具
assets/
  presets/     # 內建板子 JSON
  roles/       # 角色定義 JSON
test/
```

## 關鍵設計原則

**1. 狀態直接修改（擔當已決定）**

`GameState` 為可變狀態，引擎直接就地修改，不採事件溯源。這條路實作直觀、上手快，但**復盤與撤銷必須另外處理**，不會自動附帶：

- **復盤／回放**：每次狀態變更時，另外寫一筆 `LogEntry` 到 `game_log.dart`。這份日誌是**單向的**——只寫入、供事後查看與匯出，**不用來推導狀態**。務必在修改狀態的同一處就寫日誌，否則很容易漏記，事後對不上。
- **撤銷（undo）**：法官現場誤觸是常態。用 `undo_stack.dart` 在**進入每個階段前存一份 `GameState` 深拷貝**，撤銷就是還原快照。因此 `GameState` 及其所有巢狀物件都**必須提供可靠的深拷貝**（`copyWith` 或 `clone`），漏拷貝一層就會出現改了快照也一起變的 bug。
- 快照顆粒度建議至少到「每個夜晚行動」與「每次投票」，不要只在階段邊界存，否則法官點錯一個目標就得整個階段重來。

**2. 引擎必須是純 Dart，不依賴 Flutter**

`core/engine` 與 `core/rules` 不得 import 任何 widget。夜晚結算與勝負判定的規則組合極多（衝突規則 × 規則旗標），必須能用純單元測試涵蓋。**衝突裁決表的每一列都應該有對應測試。**

**3. 規則旗標集中在一處**

不要讓「同守同救是否致死」這類判斷散落在各處。所有規則變體集中由 `rule_flags.dart` 提供，引擎讀旗標決策。

**4. 角色可擴充**

新增角色（狼王、狼美人、守衛、騎士…）應只需新增角色定義與其行動處理，不改動結算主流程。

---

# 板子設定檔格式

`assets/presets/<preset_id>.json`：

```json
{
  "presetId": "12p_yu_nu_lie_bai",
  "name": "12人 預女獵白",
  "playerCount": 12,
  "roles": [
    { "role": "wolf",     "count": 4 },
    { "role": "seer",     "count": 1 },
    { "role": "witch",    "count": 1 },
    { "role": "hunter",   "count": 1 },
    { "role": "idiot",    "count": 1 },
    { "role": "villager", "count": 4 }
  ],
  "nightOrder": ["wolf", "witch", "seer"],
  "rules": {
    "guardHealKills": true,
    "witchSelfHealNight": 1,
    "witchDualUseSameNight": false,
    "guardCannotRepeatTarget": true,
    "poisonedHunterCannotShoot": true,
    "sheriffVoteWeight": 1.5,
    "tieBreak": "pk_then_none",
    "winCondition": "sideElimination",
    "wolfSelfDetonateEndsDay": true
  }
}
```

載入時**必須驗證**：`roles` 的 count 總和等於 `playerCount`；`nightOrder` 內的角色都存在於 `roles`；旗標值在合法範圍。驗證失敗要指出是哪個板子、哪個欄位錯，不要讓錯誤的設定檔在結算到一半才炸掉。

## 規則旗標

| 旗標 | 含義 |
|---|---|
| `guardHealKills` | 同守同救是否致死（奶穿）。`true` 為多數賽制 |
| `witchSelfHealNight` | 女巫可自救的夜次：`0` 不可、`1` 僅首夜、`-1` 不限。**未指定時依人數推導**，見下方說明 |
| `witchDualUseSameNight` | 同一夜是否可同時用解藥與毒藥 |
| `guardCannotRepeatTarget` | 守衛不可連續兩晚守同一人（應在輸入階段就擋住） |
| `poisonedHunterCannotShoot` | 獵人被毒死是否不可開槍 |
| `sheriffVoteWeight` | 警長票權重（通常 1.5） |
| `tieBreak` | 平票處理：`pk_then_none`／`pk_then_revote`／`none` |
| `winCondition` | `sideElimination`（屠邊）／`totalElimination`（屠城） |
| `wolfSelfDetonateEndsDay` | 自爆是否立即結束白天、跳過投票進入夜晚 |

### 依人數決定的規則

**9 人以上，女巫不可自救**（8 人以下的小局僅首夜可自救）。

這是依人數決定的通則，所以做成 `RuleFlags.defaultWitchSelfHealNight(playerCount)` 推導，**不寫死在每份設定檔裡** —— 新增板子時不必記得填 `witchSelfHealNight`，規則自動生效。個別板子若採用不同賽制，仍可在 `rules.witchSelfHealNight` 明確覆寫。

`test/core/preset_assets_test.dart` 會直接讀 `assets/presets/` 的實際檔案驗證這條規則，內建板子若違反會在測試階段就被抓到，而不是等法官開場才發現。

---

# 衝突裁決表

夜晚結算的核心規則。**每一列都要有對應的單元測試。**

| 情況 | 結果 | 控制旗標 |
|---|---|---|
| 狼刀 ＋ 守衛守（同一目標） | 存活 | — |
| 狼刀 ＋ 解藥（同一目標） | 存活 | — |
| 狼刀 ＋ 守衛守 ＋ 解藥（同守同救／奶穿） | **死亡** | `guardHealKills` |
| 毒 ＋ 守衛守（同一目標） | **死亡**（守衛防不了毒） | — |
| 狼刀 ＋ 毒（同一目標） | 死亡 | — |
| 守衛連續兩晚守同一人 | 輸入階段擋住 | `guardCannotRepeatTarget` |
| 獵人被毒死 | **不可**開槍 | `poisonedHunterCannotShoot` |
| 獵人被狼刀死 | 可開槍 | — |
| 獵人被放逐 | 可開槍 | — |
| 白痴被放逐 | 翻牌不死，失去投票權，留在場上 | — |
| 白痴被狼刀／被毒 | 正常死亡 | — |

## 發言順序

座次是**環狀**的，走訪時要跳過死亡玩家並繞回。

- **警左／警右**：由警長決定，從警長左／右手邊第一位存活玩家開始
- **死左／死右**：從昨夜死者的左／右手邊開始（通常用於首日尚無警長時）
- 警長死亡後依**警徽流**移交，或警長選擇撕毀警徽（此後無警長票權）

## 投票結算

1. 逐一記錄每位存活玩家的投票對象（可棄票）
2. 警長票依 `sheriffVoteWeight` 加權
3. 最高票單一 → 放逐
4. 最高票平票 → 依 `tieBreak`：
   - `pk_then_none`：平票者發言後重投，仍平票則無人出局
   - `pk_then_revote`：平票者發言後重投（平票者不投）
   - `none`：直接無人出局
5. 若被放逐者為白痴 → 翻牌，不死，失去投票權
6. 若被放逐者為獵人／黑狼王 → 觸發開槍
7. 每次死亡後重新檢查勝負

---

# 組織規則（亞洲光學 TIPS）

擔當已決定**此專案不建立 `研發紀錄.md`**。以下格式僅供日後需要時參考。

Commit 訊息格式：

```
<簡述本次變更>

內容：<本次做了什麼>
AI 協助：Claude Code（範圍：例如 產生初版函式、重構）
審閱：<擔當姓名>（已審閱並修改）
```

由 AI 產生且保留於成果中的關鍵段落，於該段開頭加一行：

```
// [AI協助 Claude] 由 <擔當姓名> 於 <YYYY-MM-DD> 審閱修改
```
