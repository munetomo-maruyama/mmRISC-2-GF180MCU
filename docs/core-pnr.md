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
| クロック | `clk`、**100 ns（10 MHz）** | 試行用。最初はチップ側（`librelane/config.yaml`）と同じ 40 ns（25 MHz）にしていたが、ローカルでの実行で CTS 後の WNS が約 −52 ns になり、CTS 後のタイミング修正がなかなか終わらなかったため緩めた |
| CTS 後のタイミング修正 | `RUN_POST_CTS_RESIZER_TIMING: false` | まず配置、配線、混雑の様子を見るため、`OpenROAD.ResizerTimingPostCTS`（setup/hold の修正）を飛ばす。配置後と大域配線後の design repair（slew、容量、ファンアウト）は実行する。タイミング違反は残り、フローの最後のチェッカが報告する。タイミングを詰めるときはこの行を消す |
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

## クラウドの結果をローカルで見る・続きを流す

クラウドの run ディレクトリ（`core_pnr/runs/`）は git に入らず、コンテナが消えると失われる。
また LibreLane の状態ファイル（`state_*.json`）は絶対パスを持つので、run を別のマシンにコピーしてもそのままでは再開できない。
そこで、クラウドの run から必要なものだけを束ねたバンドル（`core_pnr_trial_<日付>.tar.gz`、約 30 MB）を作って持ち帰る。

| ディレクトリ | 中身 |
|---|---|
| `synth/` | 合成後のネットリスト、JSON ヘッダ、`stat.rpt`、Yosys のログ、状態のメトリクス |
| `floorplan/` | フロアプランの ODB / DEF / SDC とログ |
| `sta_prepnr/` | 配置前 STA（バッファ挿入前なのでスラックはまだ意味がない） |
| `lint/`、`run/` | Verilator のログ、`flow.log`、`warning.log`、`resolved.json`、メトリクス |

バンドルはリポジトリの外に展開する（`core_pnr/runs/` の中に置くと `--last-run` が最新の run と取り違える）。
以下では、リポジトリを `~/RISCV/mmRISC-2-GF180MCU`、バンドルの展開先を `$BUNDLE` とする。

```sh
cd ~/RISCV
tar xzf core_pnr_trial_2026-09-26.tar.gz          # 展開後にディレクトリ名を変えてもよい
BUNDLE=$HOME/RISCV/core_pnr_trial_2026-09-26      # 展開先の絶対パス
```

**`nix develop` はリポジトリのルートで実行するか、リポジトリのパスを渡す。**
`nix develop` は今いるディレクトリから上にたどって `flake.nix` を探すので、バンドルのディレクトリで実行すると
`error: could not find a flake.nix file` になる。

見る:

```sh
# (a) リポジトリのルートで
cd ~/RISCV/mmRISC-2-GF180MCU
nix develop -c env -u PDK -u PDK_ROOT -u LD_LIBRARY_PATH openroad -gui
#     OpenROAD の Tcl コンソールで:  read_db <展開先の絶対パス>/floorplan/cpu_core_wrap.odb

# (b) どこからでも: flake の場所を渡し、起動時に読み込むスクリプトも渡す
echo "read_db $BUNDLE/floorplan/cpu_core_wrap.odb" > /tmp/open_fp.tcl
nix develop ~/RISCV/mmRISC-2-GF180MCU -c env -u PDK -u PDK_ROOT -u LD_LIBRARY_PATH \
    openroad -gui /tmp/open_fp.tcl
```

ODB は LEF 情報を含んでいるので、それだけで開ける。
Tcl コンソールでは `$BUNDLE` は展開されないので、絶対パスをそのまま書く。

続きを流す（合成を飛ばして P&R から）。Makefile を使うので、リポジトリのルートで実行する。
`SYNTH_DIR` にはバンドルの `synth` の絶対パスを渡す:

```sh
cd ~/RISCV/mmRISC-2-GF180MCU
nix develop -c env -u PDK -u PDK_ROOT -u LD_LIBRARY_PATH \
    make core-pnr-from-synth SYNTH_DIR=$BUNDLE/synth
```

`core_pnr/from_synth.py` がバンドル内のネットリストと JSON ヘッダの絶対パスで初期状態（`core_pnr/state_from_synth.json`）を作り、
`librelane ... -i <状態> --from OpenROAD.CheckSDCFiles` で合成の次から始める。
クラウドで試したところ、フロアプランまで 21 秒で進み、同じダイ（3077.68 x 3095.60 um）になった。
RTL か合成の設定（`core_pnr/config.yaml` の合成関係）を変えたら、このネットリストは使えないので `make core-pnr` で最初から流す。

## 次にやること

1. **全工程をローカルで流す**（`make core-pnr`、または合成を飛ばして `make core-pnr-from-synth`）。
   合成だけでクラウドでは 40 分かかったので、配置、CTS、配線まで含めると数時間以上かかる見込み。
   CLAUDE.md のとおり、クラウドではなくローカルで流すほうがよい。
2. 見るべき点:
   - 配置後と CTS 後の STA（`*-openroad-stamidpnr*`）で、reg-to-reg の最悪パス（40 ns では WNS 約 −52 ns、つまり最悪パスは約 92 ns だった）。
     FPU（倍精度 FMA）と MDU（32x32 乗算器）が候補。
   - 大域配線の混雑（`*-openroad-globalrouting*` の congestion レポート）。RF/FRF、BTB、TLB の FF の塊のまわり。
   - `rst_n` のバッファツリー（リカバリ/リムーバル）。
3. 結果に応じて:
   - 通れば `FP_CORE_UTIL` を 55〜60 に上げて詰める。
   - 混雑するなら `FP_CORE_UTIL` を下げるか、`PL_TARGET_DENSITY_PCT` を下げる。
   - タイミングが足りないなら、`CLOCK_PERIOD` を延ばして到達できる周波数をまず確かめる。
     面積を減らしたいときは core_trim 相当のパラメータ（BTB 16、TLB 4、PMP 4、PQ 8、合成で 3.24 mm²）にする。
     ラッパ内の `CPU_CORE` にパラメータを渡せば切り替えられる。
