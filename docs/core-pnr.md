# CPU_CORE レイアウト試行（LibreLane）

パッドフレームへの収容はいったん目標から外し、mmRISC-2 の `CPU_CORE` 以下だけ
（キャッシュなし、SRAM マクロなし、パッドリングなし）で LibreLane の P&R を試すための設定。

- 設定: `core_pnr/config.yaml`（Classic フロー）
- ラッパ: `core_pnr/cpu_core_wrap.sv`
- RTL: mmRISC-2 **2f59109**（無変更）、パラメータは RTL の既定値（BTB 64、ITLB/DTLB 8、PMP 8、PQ 16）
- 実行結果: `core_pnr/runs/<RUN_TAG>/`（git には入れない）

## 実行方法

```sh
# ローカル（CLAUDE.md のとおり PDK / PDK_ROOT / LD_LIBRARY_PATH を外す）
nix develop -c env -u PDK -u PDK_ROOT -u LD_LIBRARY_PATH make core-pnr          # 全工程
nix develop -c env -u PDK -u PDK_ROOT -u LD_LIBRARY_PATH make core-pnr-synth    # 合成と配置前 STA まで
nix develop -c env -u PDK -u PDK_ROOT -u LD_LIBRARY_PATH make core-pnr-openroad # 最後の run を OpenROAD で開く
nix develop -c env -u PDK -u PDK_ROOT -u LD_LIBRARY_PATH make core-pnr-klayout  # 最後の run を KLayout で開く
```

途中の工程から再開するときは、LibreLane を直接呼んで `--last-run --from <Step>` を付ける（例: `--from OpenROAD.Floorplan`）。

## 設定の中身

| 項目 | 値 | 理由 |
|---|---|---|
| トップ | `cpu_core_wrap` | CPU_CORE の検証用出力（`trace_*` 169 bit、`trap_*` 136 bit）をつながず、信号ピンを 745 → **440** 本にする。フラット化で、それらを駆動するだけのロジックも消える |
| 読み込み | `USE_SLANG: true`、`SLANG_ARGUMENTS: ["--allow-use-before-declare"]` | CORE_FPU.sv が `prod_sign` を宣言前に使っている（565 行、宣言は 571 行） |
| 階層 | 既定（`SYNTH_HIERARCHY_MODE: flatten`） | |
| クロック | `clk`、40 ns（25 MHz） | チップ側（`librelane/config.yaml`）と同じ |
| SDC | LibreLane の既定 | `clk` 以外の全入力と全出力に周期の 20%（`IO_DELAY_CONSTRAINT`）の遅延 |
| フロアプラン | `FP_SIZING: relative`、`FP_CORE_UTIL: 45`、`FP_ASPECT_RATIO: 1` | 最初は余裕を持たせる。通ったら上げる |
| 配線 | `GRT_ALLOW_CONGESTION: true` | FF だけの表（RF/FRF、BTB、TLB）が混みやすいので、混雑しても大域配線を最後まで進めて混雑箇所を出す |
| アンテナ | `DRT_ANTENNA_REPAIR_ITERS: 10`、`DRT_ANTENNA_REPAIR_MARGIN: 10` | チップ側と同じ |
| 電源 | `VDD` / `VSS` | ラッパは `USE_POWER_PINS` で電源ピンを持つ（後でマクロとしてチップに入れるとき用） |

PDN、配置密度、タイミング修正などは PDK（`gf180mcu/gf180mcuD/libs.tech/librelane`）の既定値のまま。

## クラウドでの確認結果（2026-09-26、フロアプランまで）

クラウドの VM（4 vCPU / 16 GB）で、合成と配置前 STA まで（`--to OpenROAD.STAPrePNR`）流し、続けてフロアプランだけ実行した。
エラーはなし。

### 合成（Yosys.Synthesis）

| 項目 | 値 |
|---|---|
| セル数 | 164,392 |
| セル面積 | **4.225 mm²**（core_synth の 4.232 mm² とほぼ同じ。トレース出力のロジックが消えた分は小さい） |
| FF | 21,153（`dffrnq_1` 11,747、`dffq_1` 9,016、`dffsnq_1` 390） |
| 未マッピングのセル | 0 |
| 所要時間 | **40 分**（core_synth の 8 分より長い。LibreLane はフラット化した 16 万セルをまとめて ABC（`SYNTH_STRATEGY` の既定 AREA 0）にかけるため） |

### Lint（Verilator）

エラーはなく、警告が 360 件（エラー扱いにはならない）。

- `TIMESCALEMOD` 313 件: 標準セルのブラックボックスモデルに `timescale` がなく、RTL にはあるため。無害。
- `UNUSEDSIGNAL` 27 件、`UNUSEDPARAM` 7 件: RTL 側の未使用信号とパラメータ（例: `CPU_CORE.sv:160` の `ptw_req_addr[63:40]`）。
- `PINCONNECTEMPTY` 13 件: ラッパでトレース出力をつないでいないため（意図どおり）。

### フロアプラン（OpenROAD.Floorplan）

| 項目 | 値 |
|---|---|
| ダイ | **3077.68 x 3095.60 um（9.53 mm²）** |
| コア | 6.72, 15.68 − 3070.48, 3077.20 um（9.38 mm²） |
| 配置率 | 45.0% |
| 信号ピン | 440 本（周囲約 12.3 mm） |

### 配置前 STA（OpenROAD.STAPrePNR）について

tt コーナーで setup の最悪スラックが −1383 ns（reg-to-reg では −330 ns）、max slew 違反が 19 万件と出ているが、
これは **バッファを入れる前の値で、論理段数の評価にはならない**。
最悪パスは `rst_n`（ファンアウト 12,143 本、バッファなし）から非同期リセットへのリカバリチェックで、
ほかにもファンアウト 60〜80 の信号が遅延の大半を占めている。
配置後の `repair_design`（バッファ挿入とサイズ変更）とクロックツリー合成のあとで改めて評価する必要がある。
hold 違反は 0。

## 次にやること

1. **全工程をローカルで流す**（`make core-pnr`）。
   合成だけでクラウドでは 40 分かかったので、配置、CTS、配線まで含めると数時間以上かかる見込み。
   CLAUDE.md のとおり、クラウドではなくローカルで流すほうがよい。
2. 見るべき点:
   - 配置後と CTS 後の STA（`*-openroad-stamidpnr*`）で、40 ns に対する reg-to-reg の最悪パス。
     FPU（倍精度 FMA）と MDU（32x32 乗算器）が候補。
   - 大域配線の混雑（`*-openroad-globalrouting*` の congestion レポート）。RF/FRF、BTB、TLB の FF の塊のまわり。
   - `rst_n` のバッファツリー（リカバリ/リムーバル）。
3. 結果に応じて:
   - 通れば `FP_CORE_UTIL` を 55〜60 に上げて詰める。
   - 混雑するなら `FP_CORE_UTIL` を下げるか、`PL_TARGET_DENSITY_PCT` を下げる。
   - タイミングが足りないなら、`CLOCK_PERIOD` を延ばして到達できる周波数をまず確かめる。
     面積を減らしたいときは core_trim 相当のパラメータ（BTB 16、TLB 4、PMP 4、PQ 8、合成で 3.24 mm²）にする。
     ラッパ内の `CPU_CORE` にパラメータを渡せば切り替えられる。
