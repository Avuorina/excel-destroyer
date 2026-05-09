# ExcelDestroyer — AI引き継ぎ書

> **作成日**: 2026-05-09  
> **エンジン**: Godot 4.6 (GDScript)  
> **プロジェクトパス**: `c:\Users\nhs50030\Documents\excel-destroyer\`

---

## 🎮 ゲーム概要

**タイトル**: ExcelDestroyer  
**ジャンル**: Excel風インフレ放置ゲーム  
**コンセプト**: Excelのセル・数式・エラー・UI崩壊をテーマにした放置ゲーム。  
プレイヤーはセルに数式を配置し、自動計算によって数値を増殖させる。  
後半では計算量が暴走し、Excelが破損していく。

### フェーズ進化（コアテーマ）

```
NORMAL → CORRUPTED → CRITICAL → APOCALYPSE
 普通のExcel  壊れかけ    崩壊中      完全崩壊
```

---

## 📁 ファイル構成

```
excel-destroyer/
├── project.godot              # AutoLoad: GameManager登録済み
├── Main.tscn                  # メインシーン（エントリポイント）
├── Main.gd                    # UIコントローラ
├── Cell.gd                    # セルUI 1個分のロジック
├── HANDOVER.md                # 本ファイル
├── scenes/
│   └── Cell.tscn              # セルUIプレハブ（110×60px）
└── scripts/
    ├── GameManager.gd         # AutoLoad / ゲームロジック全体
    ├── CellData.gd            # データモデル（class_name CellData）
    ├── FormulaEngine.gd       # 数式計算エンジン（static, class_name FormulaEngine）
    └── HugeNumber.gd          # 巨大数クラス（class_name HugeNumber）
```

---

## 🏗️ アーキテクチャ

### データフロー

```
CalcTimer.timeout (1秒ごと)
    ↓
GameManager.recalculate()
    ├── InputCell.display_value = raw_value
    ├── FormulaCell.display_value = FormulaEngine.calculate()
    ├── coins += current_max × prestige_multiplier
    ├── last_tick_gain = tick_gain  (DPS表示用)
    └── emit cells_updated / num_error_triggered
            ↓
        Main.gd ← シグナル受信 → UIを更新
```

### シグナル一覧（GameManager → Main.gd）

| シグナル | 発火タイミング |
|---------|--------------|
| `cells_updated` | 毎tick正常計算後 |
| `num_error_triggered` | overflow_limit超過時 |
| `prestige_done` | 転生完了後 |
| `upgrade_applied(id)` | アップグレード購入後 |
| `phase_changed(new_phase)` | prestige_countでフェーズ変化時 |

---

## 📜 スクリプト詳細

### `scripts/HugeNumber.gd`

浮動小数点の限界（1.79e308）を突破するための自作数値クラス。

```gdscript
var mantissa: float  # 1.0 <= |mantissa| < 10.0
var exponent: int    # 10の指数部
# 例: 1.23e45 → mantissa=1.23, exponent=45
```

**メソッド**:
- `add(other)` → 加算。exponent差が16以上なら大きい方を返す
- `multiply(other)` → 乗算
- `power(exp_num)` → 累乗。指数上限1000、結果上限1e+1000000
- `to_float()` → float変換（大きすぎるとinfになる点に注意）
- `to_display_string()` → exponent<6なら小数表示、以上は `1.23e45` 形式
- `is_overflow(limit)` → limitを超えているか判定
- `from_float(v)` → static。floatからHugeNumber生成

> **既知の制限**: `to_float()` と `from_float()` を経由したコイン計算は、  
> 巨大数（exponent > 308）で精度が落ちる。将来的に多倍長整数への置換が必要。

---

### `scripts/CellData.gd`

セル1つ分のデータモデル。

```gdscript
enum CellType    { INPUT, FORMULA }
enum FormulaType { SUM, PRODUCT, POWER }

var cell_id: String
var cell_type: CellType
var raw_value: HugeNumber      # InputCellのみ使用
var formula_type: FormulaType  # FormulaCellのみ使用
var inputs: Array[String]      # 参照セルIDの配列 例: ["A1", "A2"]
var display_value: HugeNumber  # 計算後の表示値（共通）
```

---

### `scripts/FormulaEngine.gd`

数式計算エンジン。全メソッドstatic。インスタンス化不要。

- `calculate(cell, all_cells)` → `FormulaType` に応じてSUM/PRODUCT/POWERを計算
- `formula_to_string(cell)` → 数式バー表示用文字列生成（例: `=SUM(A1, A2)`）

---

### `scripts/GameManager.gd` （AutoLoad）

ゲームロジックの中枢。

**フェーズ定義**:
```gdscript
enum GamePhase { NORMAL, CORRUPTED, CRITICAL, APOCALYPSE }

func get_phase() -> GamePhase:
    if prestige_count < 2:  return NORMAL
    if prestige_count < 5:  return CORRUPTED
    if prestige_count < 10: return CRITICAL
    return APOCALYPSE
```

**主要変数**:

| 変数 | 型 | 説明 |
|-----|----|------|
| `cells` | `Dictionary` | `{"A1": CellData, ...}` |
| `cell_order` | `Array[String]` | 計算順序（INPUT→FORMULA） |
| `coins` | `HugeNumber` | 所持コイン |
| `current_max` | `HugeNumber` | 最後のFormulaCellの値 |
| `overflow_limit` | `HugeNumber` | 初期値1.79e308、転生ごとに×10 |
| `last_tick_gain` | `HugeNumber` | 1tickで稼いだコイン（DPS表示用） |
| `prestige_count` | `int` | 転生回数 |
| `prestige_multiplier` | `float` | コイン倍率（転生ごと+0.5） |
| `is_num_error` | `bool` | オーバーフロー状態フラグ |

**アップグレードデータ構造**（データ駆動）:
```gdscript
{ "id": "cell_value_a1", "label": "A1 値+1", "cost_base": 10.0, "purchased": 0, "max": 99 }
```
コスト = `cost_base * 2^purchased`

**現在のアップグレード一覧**:

| id | 効果 | max |
|----|------|-----|
| `cell_value_a1` | A1のraw_value+1 | 99 |
| `cell_value_a2` | A2のraw_value+1 | 99 |
| `recalc_speed` | CalcTimer.wait_time×0.5（Main.gdが処理） | 5 |
| `add_product` | B2=PRODUCT(B1,A1)を追加 | 1 |
| `add_power` | B3=POWER(B2,A2)を追加（B2必須） | 1 |

**転生（do_prestige）の処理順**:
1. `prestige_count += 1`, `prestige_multiplier += 0.5`
2. `overflow_limit.exponent += 1`（限界値×10）
3. `coins`, `last_tick_gain` をリセット
4. `_init_cells()` でセルをリセット（A1=1, A2=1, B1=SUM に戻る）
5. 全アップグレードの`purchased`を0に
6. フェーズ変化があれば `phase_changed` シグナル発火
7. `prestige_done` 発火

---

### `Main.gd`

UIとGameManagerのブリッジ。

**UIレイアウト構造（Main.tscn）**:
```
Main (Control)
├── CalcTimer
├── BG (ColorRect) ← フェーズで背景色変化
└── UI (VBoxContainer)
    ├── TopBar → タイトル / [NORMAL] / コイン / DPS
    ├── FormulaBar → セルID | =FORMULA(...)
    └── ContentArea (HBoxContainer)
        ├── Spreadsheet (左・拡張) → GridContainer (3列)
        └── Sidebar (右・220px固定)
            ├── "UPGRADES" ラベル
            ├── UpgradeScroll > UpgradeList (VBoxContainer)
            │   └── カード × アップグレード数
            └── PrestigeCountLabel

PrestigePanel (中央オーバーレイ、初期非表示)
└── #NUM! + エラーコード + 転生ボタン
```

**重要な関数**:

| 関数 | 役割 |
|------|------|
| `_rebuild_spreadsheet()` | セルノードを全再生成 |
| `_rebuild_upgrade_buttons()` | アップグレードカードを全再生成 |
| `_update_upgrade_affordability()` | **毎tick呼ばれる軽量更新**。BuyBtnのdisabledだけ更新 |
| `_make_upgrade_card(upg)` | PanelContainer製カードを生成して返す |
| `_play_crash_sequence()` | #NUM!時の全画面演出（フラッシュ→震え→パネルスケールイン） |
| `_do_glitch_frame()` | CORRUPTED以降でランダムにセルの位置をズラす |
| `_update_phase_ui(phase)` | PhaseLabel更新+背景色Tween |

**アップグレードカード構造（コードで動的生成）**:
```
PanelContainer (name = upg["id"])
└── VBoxContainer
    ├── Label (アップグレード名)
    ├── Label ("💰 xxx")
    └── Button (name = "BuyBtn") ← find_child()で検索
```

---

### `Cell.gd` / `scenes/Cell.tscn`

セルUI 1個分。PanelContainerベース。

**主要メソッド**:
- `setup(id, is_formula)` → StyleBoxFlatを複製保持、マウス入力有効化
- `update_value(value)` → テキスト更新 + ホワイトフラッシュTween + 桁数カラー変化
- `show_error()` → "#NUM!" 赤表示 + 背景を赤く
- `reset_display()` → 値・色リセット
- `_play_select_animation()` → クリック時のスケールポップ + シアンborder

**桁数→色マッピング**:

| exponent | 色 | 意味 |
|----------|-----|------|
| 0〜5 | 緑 | 正常 |
| 6〜11 | 黄 | 過熱 |
| 12〜23 | オレンジ | 危険 |
| 24〜47 | 赤 | 崩壊寸前 |
| 48〜 | マゼンタ | APOCALYPSE |

---

## ✅ 実装済み機能

- [x] セル表示（InputCell / FormulaCell）
- [x] 自動再計算（CalcTimer）
- [x] SUM / PRODUCT / POWER 数式
- [x] アップグレードシステム（データ駆動）
- [x] 転生（Prestige）システム
- [x] `#NUM!` オーバーフロー検知
- [x] フェーズシステム（NORMAL→CORRUPTED→CRITICAL→APOCALYPSE）
- [x] 数値フラッシュ演出（update_value時）
- [x] セル選択演出（クリックでスケールポップ）
- [x] 桁数による5段階カラー変化
- [x] 右サイドバー型アップグレードUI（カード形式）
- [x] アップグレードボタン毎tick有効/無効更新
- [x] #NUM!クラッシュシーケンス（フラッシュ×3→セル震え→パネルスケールイン→点滅）
- [x] フェーズ別背景色Tween遷移
- [x] グリッチ演出（CORRUPTED以降でセル位置がランダムにズレる）
- [x] DPS表示（last_tick_gain：HugeNumber形式で正確）

---

## ⚠️ 既知の問題・制限

### 1. HugeNumber の精度問題
`apply_upgrade()` および `_update_upgrade_affordability()` 内でコイン比較に `to_float()` を使っており、exponent > 308 になるとfloatがinfになる。転生後半でコスト比較が機能しなくなる。

**修正方針**: `HugeNumber.compare(other) -> int` メソッドを追加し、exponent/mantissaを直接比較する。

### 2. `_shake_node` がControl対応していない
`_shake_node()` 内で `node is Node2D` でチェックしているが、セルは `PanelContainer`（Control継承）なのでpositionが常にVector2.ZEROになる。震えアニメが機能しない。

**修正方針**: `(node as Control).position` で直接操作する。

### 3. グリッチ演出のawait競合
`_do_glitch_frame()` 内で `await` しているため、短いGLITCH_INTERVALの場合に競合する可能性がある。

---

## 🔜 次に実装すべき機能（優先順）

### 高優先（MVP強化）

1. **HugeNumber.compare() メソッド追加**
   `apply_upgrade()` と `_update_upgrade_affordability()` の比較を exponent/mantissa 直比較に切り替える

2. **_shake_node のControl対応修正**
   セルは Control なので `(node as Control).position` を使う

3. **数値ポップアップ（+delta表示）**
   セルから差分値が上に飛び出すUI演出。`Cell.gd` に実装

4. **FormulaBarタイピングアニメ**
   数式が更新されるたびに1文字ずつ表示（Tweenのtween_callback利用）

5. **マイルストーン通知**
   exponentが上がった瞬間にトーストを表示

### 後半フェーズ向け

6. **OS侵食UI**（CRITICAL以降）
   タスクバー風UI・Windowsエラーダイアログ風オーバーレイ・「送信しています...」等

7. **セル生き物化**（APOCALYPSE）
   セルが脈打つ・数字が勝手に変わる・数式バーが自動入力される

8. **シェーダーによるCRT/グリッチ**
   `CanvasItem.material` にShaderMaterialを設定してスキャンライン描画

9. **オフライン収益**
   終了時刻を保存し、次回起動時に差分tickを計算してまとめて加算

10. **セーブ/ロード**
    `FileAccess` を使った JSON セーブ（GameManager の主要変数を保存）

---

## 🎨 カラーパレット（現在使用中）

| 用途 | カラー |
|------|--------|
| 背景(NORMAL) | `#141A2B` |
| 背景(CORRUPTED) | `#1A140A` |
| 背景(CRITICAL) | `#1F0A14` |
| 背景(APOCALYPSE) | `#0A0210` |
| アクセント（シアン） | `#14C8C8` |
| 数値テキスト（緑） | `#21FA90` |
| エラー（赤） | `#FF3B30` |
| TopBar | `#0D2140` |
| Sidebar | `#0D1A33` |

---

## 🛠️ 開発環境

- **Godot**: 4.6
- **言語**: GDScript
- **レンダラー**: Forward Plus（D3D12 on Windows）
- **AutoLoad**: GameManager のみ

---

## 📝 コーディング規約

- **命名**: snake_case（GDScript標準）
- **プライベート関数**: `_` プレフィックス
- **ノード参照**: `@onready` で宣言、パス文字列はMain.gd冒頭に集約
- **シグナル接続**: `_ready()` 内でコード接続（.tscnのconnectionは最小限）
- **HugeNumber生成**: 小さい数は `HugeNumber.new(m, e)`、floatからは `HugeNumber.from_float(v)`
- **アップグレード追加方法**: `GameManager.upgrades` 配列にDictionaryを追加し、`_apply_upgrade_effect()` にmatchケースを追加するだけ

## ❌ 禁止・注意事項
floatベース巨大数計算を増やさない
Main.gd にゲームロジックを増やしすぎない
Cell.gd にGameManager依存を書かない
await多用による競合に注意
毎tickノード再生成しない
GridContainerを毎frame rebuildしない

## 🧠 設計思想

ExcelDestroyerは：

“Excelシミュレータ”
ではなく、
“計算暴走インフレゲーム”

である。

そのため：

UI崩壊
演出
数値インフレ
放置ゲーム快感

を優先し、
現実のExcel再現性は優先しない。
