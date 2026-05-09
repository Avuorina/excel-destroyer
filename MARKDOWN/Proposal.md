# ExcelDestroyer 改修・拡張提案書

## 概要

『ExcelDestroyer』は、

「Excelをハックし、無限インフレによって世界そのものを崩壊させる」

という、極めて独自性の高いテーマを持つインクリメンタルゲームである。

本提案書では、現在構築済みの巨大数システム・セルシステム・右クリック型関数挿入システムを基盤として、

* UI/UX
* Spreadsheet体験
* 世界崩壊演出
* パフォーマンス
* プレイヤー没入感

をさらに高水準へ引き上げるための追加提案をまとめる。

---

# 現在の強み

## 1. 「Excel」という強力なテーマ性

本作最大の魅力は、

「誰もが知っているExcel」

を、

「宇宙的インフレ装置」

へ変貌させる点にある。

通常の放置ゲームと異なり、

* セル
* 関数
* スプレッドシート
* #NUM!
* Overflow

など、現実のPCソフトウェア文化を直接ゲーム体験へ昇華できている。

---

## 2. Spreadsheet中心のゲーム設計

本作では、

「Upgradeボタンを押す」

のではなく、

「セルに関数を挿入する」

ことでゲームが進行する。

これは単なるUI差別化ではなく、

「プレイヤー自身がExcelを改造している感覚」

を生み出している。

---

## 3. 数学的成長とゲーム進行の一致

関数進化：

SUM
↓
PRODUCT
↓
FACT
↓
POWER
↓
TOWER

が、

* 線形成長
* 指数成長
* 数学崩壊
* 現実崩壊

というゲーム進行そのものになっている。

この一致性は非常に強力。

---

# 提案1：Spreadsheet Renderer化

## 問題

今後：

* グリッチ
* 大量セル
* popup
* animation
* corruption

などを追加すると、
セルをNode単位で大量管理する方式は負荷問題を起こす可能性が高い。

---

## 提案

セルを：

「UIノード」

ではなく、

「データ + 描画」

として扱う。

---

## 推奨構造

SpreadsheetView
├ draw_grid()
├ draw_cell()
├ draw_headers()
├ draw_glitch()
└ draw_selection()

CellData[]
├ type
├ cached_value
├ source_refs
├ state
└ modifiers

---

## メリット

* 大量セル対応
* 高速描画
* グリッチ制御
* virtualization
* future scalability

を大幅に改善可能。

---

# 提案2：計算キューシステム

## 目的

後半関数：

* FACT
* POWER
* TOWER

に、

「危険な計算を実行している感」

を与える。

---

## 提案仕様

関数実行時：

[CALCULATING...]

↓

短い待機

↓

結果表示。

---

## 効果

プレイヤーに：

* PC限界感
* CPU暴走感
* Excelが悲鳴を上げている感覚

を与えられる。

---

# 提案3：セル参照破損システム（#REF!）

## 概要

後半フェーズで：

#REF!
#VALUE!
#NUM!

などを発生させる。

---

## 発生条件例

* Overflow
* recursive formula
* corruption
* 高Prestige
* 行削除

---

## 効果

「Excel世界が壊れている」

という没入感を大幅に向上。

---

# 提案4：右クリックメニューの段階的崩壊

## 初期

正常なExcel風メニュー。

---

## CORRUPTED以降

* ノイズ
* 文字化け
* UI歪み
* 項目ズレ
* 赤点滅

を段階的に追加。

---

## 目的

「ゲームそのものが壊れている」

感覚を演出する。

---

# 提案5：Prestige演出の強化

## 現状

Prestige = 数値リセット

---

## 提案

Prestigeを：

「Excel再起動」

として完全演出化する。

---

## 推奨フロー

ブラックアウト
↓
静寂
↓
PC起動音
↓
Blank Workbook
↓
真っ白シート復帰
↓
Multiplier継承

---

## 効果

Prestigeが：

「作業のやり直し」

ではなく、

「危険な実験を再起動する儀式」

になる。

---

# 提案6：ログコンソール強化

## 推奨ログ例

[INFO] Cell recalculated
[WARN] Exponential instability detected
[ERROR] Floating point precision compromised
[FATAL] Reality overflow imminent

---

## 効果

ゲームの世界観を、
UI全体へ浸透させる。

---

# 提案7：未来要素の可視化

## LOCKED表示

POWER
[LOCKED]
Requires Prestige 1

---

## 目的

未来のインフレを見せ、
プレイヤーのモチベーションを維持する。

---

# 最重要思想

本作は：

「数字が増えるゲーム」

ではない。

「人類がExcelを限界を超えて酷使し、
数学・PC・現実世界そのものを崩壊させるゲーム」

である。

そのため：

* UI
* 関数
* セル
* ログ
* グリッチ
* Overflow
* Prestige

すべてを、
このテーマへ統一することが重要である。

---

# 総評

『ExcelDestroyer』は、

* Spreadsheet体験
* Incrementalゲーム
* 数学インフレ
* PC崩壊演出

を高次元で融合できる、
非常に独自性の高いタイトルである。

特に：

「右クリックで関数を挿入する」

という操作体系は、
本作独自の強力なアイデンティティとなっている。

今後、
UI・演出・崩壊フェーズをさらに磨くことで、

「Excelが宇宙を破壊するゲーム」

として、
非常に印象的な作品へ到達できる可能性が高い。
