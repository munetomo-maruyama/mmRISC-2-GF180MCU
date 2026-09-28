# CPU_TOP / CPU_CORE 面積見積もり（合成のみ、GF180MCU）

mmRISC-2 の `CPU_TOP` を GF180MCU で論理合成だけ行い、パッドリングなしのコアが
wafer.space 1x1 スロットのコア領域（`librelane/slots/slot_1x1.yaml` の CORE_AREA
3048 x 4238 um = **12.92 mm²**）に入る見込みがあるかを見積もった。P&R はしていない。
あわせて、レイアウト試行の準備として `CPU_CORE` 以下（キャッシュなし）だけも合成した（「CPU_CORE 単体」の節）。

- RTL: mmRISC-2 **2f59109**（サブモジュール、無変更）
- 合成: Yosys 0.66 + yosys-slang（Nix dev shell）。スクリプトは `core_synth/`
- 標準セル: `gf180mcu_fd_sc_mcu7t5v0`、liberty は `tt_025C_5v00`（SRAM マクロが 5V 品のため 5V を選択。面積は電圧に依存しない）
- SRAM: `gf180mcu_fd_ip_sram`（LEF の SIZE から面積を計算）

## 結論

| 構成 | ロジック [mm²] | SRAM マクロ [mm²] | 必要コア面積 [mm²]（配置率 60% / 50%） | 12.92 mm² 比 |
|---|---:|---:|---:|---:|
| A. 現在の設定（I$/D$ 64 sets x 4 ways = 16 KB ずつ、タグも SRAM） | 5.98 | 16.22 | 27.8 / 29.8 | 2.15 / 2.30 倍 |
| A'. 同上、タグは FF | 7.68 | 13.40 | 27.4 / 30.0 | 2.12 / 2.32 倍 |
| B. キャッシュ縮小（16 sets x 2 ways = 2 KB ずつ、タグは FF） | 6.04 | 3.72 | 14.2 / 16.3 | 1.10 / 1.26 倍 |
| B'. 同上、タグも SRAM | 5.81 | 5.32 | 15.7 / 17.6 | 1.21 / 1.36 倍 |
| C. B + パラメータ縮小（BTB 16, ITLB/DTLB 4, PMP 4, MSHR/WB 1, PQ 8） | 4.96 | 3.72 | **12.4 / 14.1** | 0.96 / 1.09 倍 |
| D. C − DBG_HART_STUB（概算） | 4.39 | 3.72 | 11.5 / 13.0 | 0.89 / 1.00 倍 |
| E. D − FPU（CORE_FPU + CORE_FRF、概算） | 3.19 | 3.72 | 9.5 / 10.6 | 0.73 / 0.82 倍 |

- **現在の設定（16 KB + 16 KB）は入らない。** データ SRAM だけで 64 個 x 0.209 mm² = 13.4 mm² になり、
  コア領域全体（12.92 mm²）を超える。
- キャッシュを 16 x 2（2 KB ずつ）に縮めてもまだ 1.1〜1.3 倍。そのうえ RTL のパラメータだけで
  BTB/TLB/PMP/MSHR などを縮めると（構成 C）、配置率 60% でぎりぎり収まる計算になる。
- 確実に入れるには、ロジック側でもう一段の削減（DBG_HART_STUB の置き換え、FPU を外す、MDU の乗算器を減らす）が必要。
  E まで削れば 50% でも 0.8 倍で余裕がある。
- 必要コア面積 = SRAM マクロ面積（各辺 10 um のハロー込み）+ ロジック面積 / 配置率。
  ロジック面積は合成直後の値で、タイミング用のバッファ、クロックツリー、タップ/フィルセルは含まない
  （P&R 後はふつう 10〜20% 増える）。配置率 50〜60% の仮定がこの増分と配線余裕を吸収するかどうかは P&R で確認する。
- ロジック = CPU_TOP の合成結果 + キャッシュのタグまわり（下記「タグ」）。SRAM を使うのはキャッシュのデータ（とタグ）だけで、
  レジスタファイル、BTB、TLB などは全部 FF で合成されている。

## 合成の条件

- `CPU_TOP` のパラメータ `USE_BFM=0`（シミュレーション用 BFM ではなく実際の CPU_CORE を入れる）。
- `CACHE_DATA_ARRAY` と `CACHE_TAG_ARRAY` は `read_slang --blackboxed-module` で blackbox にした（RTL は読むが中身を展開しない）。
- 階層は保持（`--keep-hierarchy`）。yosys-slang は各インスタンスを `<MODULE>$<インスタンスパス>` という別モジュールにするので、
  インスタンスごとの面積がそのまま出る。
- `synth -top CPU_TOP` → `dfflibmap` → `abc -liberty`（タイミング制約なし、ABC の既定スクリプト）。dont_use の指定はしていない。
- `initial` とか宣言時の初期値（FPGA の INIT）は ASIC の FF にはないので、`attrmap -remove init` で落としてからマッピングした。
- 所要時間: 1 構成あたり約 11 分（4 vCPU の VM、シングルスレッド）、メモリは途中で約 1.1 GB（ピークは測っていない）。2 構成を並列に走らせても 16 GB に余裕がある。

### RTL を直さずに回避したもの

| 内容 | 回避方法 |
|---|---|
| `CORE_FPU.sv:565-566` で `prod_sign` を宣言（571 行）より前に使っている。slang はエラーにする（シミュレータと Vivado は通す） | `read_slang --allow-use-before-declare` |
| `CORE_FPU.sv:237-241` の `always @(u_a, u_fmt) unpack(...)` は `@*` として合成される（slang の warning）。感度リストは入力を網羅しているので動作は同じ | なし（warning のみ） |
| `DCACHE`/`DMA`/`DBG_DM`/`MDU`/`FPU` の `always_ff` 内の一時変数に「asynchronous load value missing」の warning。リセット値のない中間変数で、動作に影響なし | なし（warning のみ） |
| `initial` ブロック（キャッシュ配列、DBG_HART_STUB の `xf`）と宣言時初期値（`DBG_CJTAG` の `esc_gray`、`DBG_CDC` のリセット同期） | キャッシュ配列は blackbox。残りは `attrmap -remove init` |

合成を通すために RTL の変更が必要になったものはない。ただし ASIC 化するときに mmRISC-2 側で直すべき点がいくつかある（最後の「mmRISC-2 側への報告事項」）。

## モジュール別の結果

### グループ別（3 構成）

面積はセル面積の合計 [mm²]。FF 数はフリップフロップの数（ラッチは 0）。キャッシュ配列は含まない。

| グループ | default 面積 | FF | small 面積 | FF | trim 面積 | FF |
|---|---:|---:|---:|---:|---:|---:|
| CORE_FPU (FPU) | 0.836 | 2018 | 0.836 | 2014 | 0.837 | 2018 |
| CORE_MMU (TLB/PMP/PTW) | 0.413 | 1862 | 0.413 | 1862 | 0.235 | 1076 |
| CPU_CORE (FPU/MMU 以外) | 2.996 | 17550 | 2.995 | 17550 | 2.182 | 11187 |
| CPU_CACHE 制御部 (I$/D$) | 0.646 | 4075 | 0.618 | 4064 | 0.529 | 3370 |
| CPU_DBG: DBG_HART_STUB | 0.565 | 5071 | 0.565 | 5071 | 0.565 | 5071 |
| CPU_DBG (HART_STUB 以外) | 0.181 | 1288 | 0.181 | 1288 | 0.181 | 1288 |
| CPU_MMIO (CLINT/PLIC) | 0.111 | 587 | 0.111 | 587 | 0.111 | 587 |
| DMA_CACHE | 0.033 | 261 | 0.033 | 261 | 0.033 | 261 |
| CPU_TOP 直下 (BUS_ARB x2, P2 ARB, glue) | 0.031 | 30 | 0.031 | 30 | 0.031 | 30 |
| **合計** | **5.811** | 32742 | **5.784** | 32727 | **4.704** | 24888 |

セル数の合計: default 202,456、small 201,193、trim 170,004。

- small は default からキャッシュ制御部が 0.03 mm² 減るだけ（キャッシュの大きさはほとんど SRAM 側に効く）。
- small から trim で減った 1.08 mm² の内訳: BTB 64→16 で 0.75、TLB 8→4 で 0.11、PMP 8→4 で 0.10（3 か所のチェッカ 0.07 + CSR の pmpcfg/pmpaddr 0.03）、
  MSHR/WB 2→1 で 0.09、PQ 16→8 で 0.03。

### インスタンス別（default 構成）

「面積 (配下含む)」は配下のインスタンスを含めた値、「自身の面積」はそのインスタンスの中のセルだけ。

| インスタンス | モジュール | 面積 (配下含む) [mm2] | 自身の面積 [mm2] | セル数 (配下含む) | FF 数 (配下含む) |
|---|---|---:|---:|---:|---:|
| CPU_TOP | CPU_TOP | 5.8113 | 0.0001 | 202456 | 32742 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_cpu_core | CPU_CORE | 4.2444 | 0.2946 | 151041 | 21430 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_csr | CORE_CSR | 0.1771 | 0.1771 | 4867 | 1306 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_dec | CORE_DEC | 0.0057 | 0.0057 | 363 | 0 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_decomp | CORE_DECOMP | 0.0035 | 0.0035 | 219 | 0 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_exu | CORE_EXU | 0.0637 | 0.0637 | 3482 | 0 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_fpu | CORE_FPU | 0.8359 | 0.7939 | 39355 | 2018 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_round | FPU_ROUND | 0.0420 | 0.0420 | 1993 | 84 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_frf | CORE_FRF | 0.3658 | 0.3658 | 8129 | 2048 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_ifu | CORE_IFU | 1.1960 | 0.1829 | 32311 | 9288 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_btb | CORE_BTB | 1.0131 | 1.0131 | 26379 | 8000 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_lsu | CORE_LSU | 0.0063 | 0.0063 | 213 | 44 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_mdu | CORE_MDU | 0.5933 | 0.5933 | 29606 | 849 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_mmu | CORE_MMU | 0.4129 | 0.0270 | 15761 | 1862 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_dtlb | MMU_TLB | 0.1132 | 0.1132 | 3276 | 787 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_itlb | MMU_TLB | 0.1138 | 0.1138 | 3321 | 787 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_pmp_d | MMU_PMP | 0.0476 | 0.0476 | 2635 | 0 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_pmp_i | MMU_PMP | 0.0476 | 0.0476 | 2635 | 0 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_pmp_w | MMU_PMP | 0.0476 | 0.0476 | 2635 | 0 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_ptw | MMU_PTW | 0.0161 | 0.0161 | 394 | 131 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_rf | CORE_RF | 0.2897 | 0.2897 | 8051 | 1984 |
| &nbsp;&nbsp;u_bus_arb | BUS_ARB | 0.0124 | 0.0124 | 455 | 8 |
| &nbsp;&nbsp;u_bus_arb_cpu | BUS_ARB | 0.0124 | 0.0124 | 455 | 8 |
| &nbsp;&nbsp;u_cpu_cache | CPU_CACHE | 0.6456 | 0.0000 | 21262 | 4075 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_arb | BUS_ARB | 0.0124 | 0.0124 | 455 | 8 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_dcache | DCACHE | 0.5867 | 0.5867 | 19111 | 3811 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_icache | ICACHE | 0.0386 | 0.0386 | 1427 | 231 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_port_arb | CACHE_PORT_ARB | 0.0079 | 0.0079 | 269 | 25 |
| &nbsp;&nbsp;u_cpu_dbg | CPU_DBG | 0.7457 | 0.0021 | 24022 | 6359 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_dbg_cache | DBG_CACHE | 0.0231 | 0.0231 | 533 | 211 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_busmst | DBG_BUSMST | 0.0342 | 0.0342 | 1222 | 210 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_cdc | DBG_CDC | 0.0162 | 0.0159 | 328 | 157 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_sync_ack | DBG_SYNC | 0.0001 | 0.0001 | 2 | 2 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_sync_req | DBG_SYNC | 0.0001 | 0.0001 | 2 | 2 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_cjtag | DBG_CJTAG | 0.0041 | 0.0039 | 129 | 28 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;u_sync_mode | DBG_SYNC | 0.0001 | 0.0001 | 2 | 2 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_dm | DBG_DM | 0.0846 | 0.0846 | 3055 | 524 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_dtm | DBG_DTM | 0.0107 | 0.0107 | 369 | 80 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_hart | DBG_HART_STUB | 0.5648 | 0.5648 | 18227 | 5071 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_rst_bus | DBG_RST_SYNC | 0.0001 | 0.0001 | 2 | 2 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_rst_s_por | DBG_RST_SYNC | 0.0001 | 0.0001 | 2 | 2 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_rst_t_por | DBG_RST_SYNC | 0.0001 | 0.0001 | 2 | 2 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_rst_tap | DBG_RST_SYNC | 0.0001 | 0.0001 | 2 | 2 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_sync_auth_en | DBG_SYNC | 0.0002 | 0.0002 | 2 | 2 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_sync_auth_key | DBG_SYNC | 0.0048 | 0.0048 | 64 | 64 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_sync_bus_rst | DBG_SYNC | 0.0002 | 0.0002 | 2 | 2 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_sync_hart_rst | DBG_SYNC | 0.0002 | 0.0002 | 2 | 2 |
| &nbsp;&nbsp;u_dma | DMA_CACHE | 0.0332 | 0.0332 | 870 | 261 |
| &nbsp;&nbsp;u_mmio | CPU_MMIO | 0.1114 | 0.0301 | 4132 | 587 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_clint | CPU_CLINT | 0.0236 | 0.0236 | 919 | 129 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_plic | CPU_PLIC | 0.0576 | 0.0576 | 2482 | 224 |
| &nbsp;&nbsp;u_p2_arb | CACHE_PORT_ARB | 0.0061 | 0.0061 | 214 | 13 |

### 面積の大きい順（インスタンス自身のセル、default 構成）

| 順位 | インスタンス | 面積 [mm²] | 割合 | FF 数 | 中身 |
|---:|---|---:|---:|---:|---|
| 1 | u_ifu.u_btb (CORE_BTB) | 1.013 | 17.4% | 8000 | 64 エントリ x 125 bit の表を全部 FF で保持（FPGA の分散 RAM 向けの形） |
| 2 | u_fpu (CORE_FPU) | 0.794 | 13.7% | 1934 | 倍精度 FMA/除算/平方根/変換など（FPU_ROUND 0.042 は別） |
| 3 | u_mdu (CORE_MDU) | 0.593 | 10.2% | 849 | 32x32 乗算器を 4 個並列（3 サイクル乗算）+ 1 bit/サイクルの除算 |
| 4 | u_cpu_cache.u_dcache (DCACHE) | 0.587 | 10.1% | 3811 | MSHR 2 + ライトバックバッファ 2（各 64 B のライン）、ROB など |
| 5 | u_cpu_dbg.u_hart (DBG_HART_STUB) | 0.565 | 9.7% | 5071 | デバッグ用の疑似ハートが持つ GPR/FPR のコピー 64 x 64 bit（`xf`）ほか |
| 6 | u_frf (CORE_FRF) | 0.366 | 6.3% | 2048 | 浮動小数点レジスタファイル 32 x 64 bit（FF） |
| 7 | u_cpu_core（自身） | 0.295 | 5.1% | 2031 | パイプラインレジスタ、フォワーディング、ハザード検出 |
| 8 | u_rf (CORE_RF) | 0.290 | 5.0% | 1984 | 整数レジスタファイル 31 x 64 bit（FF） |
| 9 | u_ifu（自身） | 0.183 | 3.1% | 1288 | プリフェッチキュー 16 パーセル ほか |
| 10 | u_csr (CORE_CSR) | 0.177 | 3.0% | 1306 | CSR（pmpcfg/pmpaddr 8 エントリを含む） |
| 11 | u_mmu.u_itlb (MMU_TLB) | 0.114 | 2.0% | 787 | 8 エントリ |
| 12 | u_mmu.u_dtlb (MMU_TLB) | 0.113 | 1.9% | 787 | 8 エントリ |
| 13 | u_cpu_dbg.u_dm (DBG_DM) | 0.085 | 1.5% | 524 | デバッグモジュール |
| 14 | u_exu (CORE_EXU) | 0.064 | 1.1% | 0 | ALU（組み合わせ回路のみ） |
| 15 | u_mmio.u_plic (CPU_PLIC) | 0.058 | 1.0% | 224 | 32 ソース |

FF は 1 個あたり 64〜75 um²（`dffq_1` 63.7、`dffrnq_1` 74.6）で、enable 付き FF がないのでその前に mux が付く。
FF 数 32,742 だけで約 2.3 mm²（ロジック全体の 39%）を占める。表を FF で持っているもの（BTB、レジスタファイル、
DBG_HART_STUB、TLB、DCACHE のバッファ）が面積の大きな部分になっている。

## キャッシュの SRAM

`gf180mcu_fd_ip_sram` のマクロは 4 種類で、どれも **1 ポート**、8 bit 幅（ビット単位の書き込みマスク付き）、幅は 431.86 um。

| マクロ | サイズ [um] | 面積 [mm2] |
|---|---|---:|
| gf180mcu_fd_ip_sram__sram64x8m8wm1 | 431.86 x 232.88 | 0.1006 |
| gf180mcu_fd_ip_sram__sram128x8m8wm1 | 431.86 x 268.88 | 0.1161 |
| gf180mcu_fd_ip_sram__sram256x8m8wm1 | 431.86 x 340.88 | 0.1472 |
| gf180mcu_fd_ip_sram__sram512x8m8wm1 | 431.86 x 484.88 | 0.2094 |


RTL の配列とマクロの対応:

- データ（CACHE_DATA_ARRAY）: 1 サイクルに各ウェイから 64 bit を並列に読むので、1 ウェイあたり 8 bit 幅のマクロが 8 個並ぶ。
  深さは SETS x 64 B / 8 = SETS x 8 ワード（64 sets なら 512 → 512x8、16 sets なら 128 → 128x8）。
- タグ（CACHE_TAG_ARRAY のタグ部）: TAG_BITS = 40 − 6 − log2(SETS)（64 sets で 28 bit、16 sets で 30 bit）。
  全ウェイのタグを 1 回で読むので、1 行に WAYS x TAG_BITS bit を並べ（書き込みはビットマスクでウェイを選ぶ）、
  ceil(WAYS x TAG_BITS / 8) 個のマクロを使う。深さは最小の 64 で足りる（16 sets では 3/4 が空く）。
- タグの valid/dirty ビットは FF のまま（1 サイクルで全無効化、flush 用の組み合わせ読み出しがあるので SRAM にできない）。

I$ と D$ が同じ構成のときの 2 キャッシュ合計:


| 構成 (sets x ways) | 容量/キャッシュ | データ SRAM | タグ SRAM | SRAM 合計 [mm2] (データ+タグ) | タグを FF にした場合のタグ [mm2] | データ SRAM + タグ FF [mm2] |
|---|---:|---|---|---:|---:|---:|
| 64 x 4 | 16 KB | 64 x 512x8 = 13.40 mm2 | 28 x 64x8 = 2.82 mm2 | 16.22 | 1.87 | 15.27 |
| 64 x 2 | 8 KB | 32 x 512x8 = 6.70 mm2 | 14 x 64x8 = 1.41 mm2 | 8.11 | 0.92 (概算) | 7.62 |
| 32 x 4 | 8 KB | 64 x 256x8 = 9.42 mm2 | 30 x 64x8 = 3.02 mm2 | 12.44 | 0.95 (概算) | 10.37 |
| 32 x 2 | 4 KB | 32 x 256x8 = 4.71 mm2 | 16 x 64x8 = 1.61 mm2 | 6.32 | 0.48 (概算) | 5.19 |
| 16 x 4 | 4 KB | 64 x 128x8 = 7.43 mm2 | 30 x 64x8 = 3.02 mm2 | 10.45 | 0.49 (概算) | 7.92 |
| 16 x 2 | 2 KB | 32 x 128x8 = 3.72 mm2 | 16 x 64x8 = 1.61 mm2 | 5.32 | 0.25 | 3.97 |
| 64 x 1 | 4 KB | 16 x 512x8 = 3.35 mm2 | 8 x 64x8 = 0.80 mm2 | 4.15 | 0.46 (概算) | 3.81 |
| 16 x 1 | 1 KB | 16 x 128x8 = 1.86 mm2 | 8 x 64x8 = 0.80 mm2 | 2.66 | 0.12 (概算) | 1.98 |

- 「(概算)」は、タグ全体を FF にした場合の値を 1 bit あたり約 120 um² として見積もったもの。
  それ以外の FF 値は `core_synth/run_est.sh` で実際の `CACHE_TAG_ARRAY` を単体で合成した値（下表）。
- 容量が同じなら **ウェイを減らしてセットを増やすほうが得**（マクロの数はウェイ数 x 8 で決まり、深さを増やしても面積はあまり増えない）。
  例: 4 KB なら 32 x 2 は 4.71 mm²、64 x 1 は 3.35 mm²、16 x 4 は 7.43 mm²。ただし `SETS x BLOCK_BYTES ≤ 4096`（VIPT の制約）なので、
  64 B ブロックでは 64 sets が上限。
- タグは SRAM にすると 64x8 マクロが 1 個 0.10 mm² と大きいので、小さいキャッシュでは FF のほうが小さい
  （64 x 4 でも FF 1.87 mm² に対して SRAM 2.82 mm²）。

タグまわりの単体合成（1 キャッシュ分、`core_synth/out/est/est.md`）:

| 対象 | 面積 [mm²] | セル数 | FF 数 |
|---|---:|---:|---:|
| valid/dirty だけ（タグを SRAM にしたときにロジック側に残る分）、64 x 4 | 0.0868 | 2781 | 520 |
| 同、16 x 2 | 0.0112 | 353 | 68 |
| CACHE_TAG_ARRAY 全体を FF（64 x 4、TAG_BITS 28） | 0.9334 | 23060 | 7800 |
| 同（16 x 2、TAG_BITS 30） | 0.1270 | 2894 | 1088 |

valid/dirty 部は `core_synth/est/TAG_VALID_DIRTY.sv`（CACHE_TAG_ARRAY の valid/dirty 部分だけを写したもの。見積もり専用）で合成した。

### 配置の見通し

コア領域は 3048 um 幅なので、431.86 um 幅のマクロはハローなしで横に 7 個、ハローを取ると 6 個まで。

- 現在の設定: 512x8 が 64 個（データのみ）。6 個 x 11 段 = 5.5 mm の高さが必要で、4.24 mm のコアには入らない。
- 16 x 2: 128x8 が 32 個。ハロー 10 um 込みで 6 個 x 6 段、高さ約 1.73 mm（コア高さの 41%）。残り 3048 x 約 2500 um = 7.6 mm² にロジックを置く。
  構成 C のロジック 4.96 mm² なら配置率 65%、D（4.39 mm²）なら 58%、E（3.19 mm²）なら 42%。
  上の「必要コア面積」の表より少し厳しいのは、マクロの帯の端数（6 個で 2.7 mm、残り 0.35 mm 幅）が使いにくいため。

## 削る候補

効果の大きい順。「パラメータ」は CPU_TOP のパラメータだけで済むもの、「RTL」は mmRISC-2 側の変更が必要なもの。

| 候補 | 減る面積 [mm²] | 種類 | 備考 |
|---|---:|---|---|
| キャッシュを 64 x 4 → 16 x 2（両方） | 12.4（SRAM + ロジックの合計 22.2 → 9.8） | パラメータ | 必須。容量が同じならウェイを減らす方が得（上の表） |
| BTB 64 → 16 エントリ | 0.75 | パラメータ | 分岐予測の性能が下がる。BTB を SRAM にするのはマクロが大きすぎて割に合わない |
| FPU を外す（RV64IMAC にする） | 1.2 以上（CORE_FPU 0.84 + CORE_FRF 0.37 + CPU_CORE 内の FP まわり） | RTL | 今は FPU を外すパラメータがない。MISA、デコード、CSR（fcsr、mstatus.FS）の変更が必要 |
| DBG_HART_STUB を実ハートのデバッグ対応に置き換える | 0.57 | RTL | 今の DBG_DM は疑似ハートにつながっていて、GPR/FPR のコピー（`xf` 64 x 64 bit）を持っている。本物のハートにつなげば不要になる（ただしコア側に halt/resume/抽象コマンドの回路が加わる） |
| MDU の乗算器 4 個 → 1 個（4 サイクル）またはシフト加算 | 0.3〜0.4（概算） | RTL | 32x32 乗算器 4 個が MDU 0.59 mm² の大半。乗算のレイテンシが延びる |
| TLB 8 → 4 エントリ（I/D） | 0.11 | パラメータ | |
| PMP 8 → 4 エントリ（0 で PMP なし） | 0.10（0 なら 0.2 前後） | パラメータ | 3 か所（I/D/PTW）でチェックしている |
| DCACHE の MSHR/WB 2 → 1 | 0.09 | パラメータ | ミス中の後続アクセスの重なりが減る |
| レジスタファイル（RF 0.29 + FRF 0.37）をラッチにする | 0.2 前後（概算） | RTL | ラッチベースの RF。STA とテストの手間が増える |

## mmRISC-2 側への報告事項

合成を通すために RTL を直す必要はなかったが、ASIC にするなら次の点を mmRISC-2 で直す必要がある。

1. **キャッシュの SRAM が 1 ポート**: `gf180mcu_fd_ip_sram` は 1 ポート（A、CEN、GWEN、WEN）しかない。
   今の DCACHE は、s0 の読み出し（次のアクセス）と s1 の書き込み（ストアヒット）を同じサイクルに出し、同じアドレスは `fwd_*` でフォワードしている。
   1 ポートのマクロでは同時にできないので、書き込みと読み出しを調停する（ストアバッファ、または書き込みサイクルの読み出しを止める）変更がいる。
   マクロを 2 組持つ手もあるが、SRAM 面積が 2 倍になるので現実的でない。ICACHE もフィル中の書き込みと読み出しが重ならないか確認が必要。
   あわせて、配列を SRAM マクロに置き換える口（`ifdef` で FPGA 用の推論配列とマクロのインスタンスを切り替えるなど）もいる。
2. **`CORE_FPU.sv:565-566` の宣言前使用**: `prod_sign` の宣言（571 行）を前に移せば、slang の `--allow-use-before-declare` がいらなくなる。
3. **電源投入時の初期値に頼っている箇所**: `DBG_CDC` のリセット同期（初期値 0 = リセット状態から始まる）と `DBG_CJTAG` の `esc_gray` は FPGA の INIT に頼っている。
   ASIC の FF には初期値がないので、これらがリセットなしで正しく始まるか見直す必要がある。
4. FPU を外すパラメータ、DBG_HART_STUB の置き換え（削る候補の表を参照）。

## CPU_CORE 単体（キャッシュなし）

パッドフレームに入れることはいったん目標から外し、`CPU_CORE` 以下だけでレイアウトまで試すための事前確認として、
`CPU_CORE` をトップにして合成した（`run_synth.sh core` / `core_trim`、ファイルは `core_synth/files_core.f`）。
キャッシュ、CPU_DBG、CLINT/PLIC、バス調停は含まない。SRAM マクロは使わない（全部標準セル）。
合成条件は CPU_TOP と同じ（tt_025C_5v00、階層保持、タイミング制約なし）。

| 構成 | 面積 [mm²] | セル数 | FF 数 | うち FF の面積 [mm²] |
|---|---:|---:|---:|---:|
| core（RTL の既定値: BTB 64, ITLB/DTLB 8, PMP 8, PQ 16） | **4.232** | 150,149 | 21,429 | 1.50 |
| core_trim（BTB 16, ITLB/DTLB 4, PMP 4, PQ 8） | **3.244** | 120,826 | 14,280 | 1.04 |

CPU_TOP の中で合成したときの CPU_CORE（4.244 mm²）とほぼ同じ。所要時間は 1 構成あたり約 8 分、ピークメモリ約 1.5 GB。

### グループ別

| グループ | core 面積 | FF | core_trim 面積 | FF |
|---|---:|---:|---:|---:|
| CORE_FPU (FPU) | 0.833 | 2017 | 0.832 | 2017 |
| CORE_MMU (TLB/PMP/PTW) | 0.415 | 1862 | 0.233 | 1076 |
| CORE_IFU (BTB を含む) | 1.189 | 9288 | 0.413 | 3165 |
| CORE_MDU (乗除算) | 0.593 | 849 | 0.593 | 849 |
| CORE_FRF (FP レジスタ) | 0.366 | 2048 | 0.366 | 2048 |
| CORE_RF (整数レジスタ) | 0.288 | 1984 | 0.288 | 1984 |
| CORE_CSR | 0.176 | 1306 | 0.147 | 1066 |
| CPU_CORE 直下 + DEC/DECOMP/EXU/LSU | 0.373 | 2075 | 0.373 | 2075 |
| **合計** | **4.232** | 21429 | **3.244** | 14280 |

### インスタンス別（core）

| インスタンス | モジュール | 面積 (配下含む) [mm2] | 自身の面積 [mm2] | セル数 (配下含む) | FF 数 (配下含む) |
|---|---|---:|---:|---:|---:|
| CPU_CORE | CPU_CORE | 4.2321 | 0.2947 | 150149 | 21429 |
| &nbsp;&nbsp;u_csr | CORE_CSR | 0.1759 | 0.1759 | 4805 | 1306 |
| &nbsp;&nbsp;u_dec | CORE_DEC | 0.0054 | 0.0054 | 353 | 0 |
| &nbsp;&nbsp;u_decomp | CORE_DECOMP | 0.0035 | 0.0035 | 219 | 0 |
| &nbsp;&nbsp;u_exu | CORE_EXU | 0.0628 | 0.0628 | 3470 | 0 |
| &nbsp;&nbsp;u_fpu | CORE_FPU | 0.8328 | 0.7909 | 39226 | 2017 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_round | FPU_ROUND | 0.0419 | 0.0419 | 1913 | 84 |
| &nbsp;&nbsp;u_frf | CORE_FRF | 0.3655 | 0.3655 | 7950 | 2048 |
| &nbsp;&nbsp;u_ifu | CORE_IFU | 1.1887 | 0.1825 | 31638 | 9288 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_btb | CORE_BTB | 1.0061 | 1.0061 | 25738 | 8000 |
| &nbsp;&nbsp;u_lsu | CORE_LSU | 0.0063 | 0.0063 | 213 | 44 |
| &nbsp;&nbsp;u_mdu | CORE_MDU | 0.5933 | 0.5933 | 29607 | 849 |
| &nbsp;&nbsp;u_mmu | CORE_MMU | 0.4153 | 0.0270 | 15932 | 1862 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_dtlb | MMU_TLB | 0.1171 | 0.1171 | 3560 | 787 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_itlb | MMU_TLB | 0.1132 | 0.1132 | 3264 | 787 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_pmp_d | MMU_PMP | 0.0473 | 0.0473 | 2614 | 0 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_pmp_i | MMU_PMP | 0.0473 | 0.0473 | 2614 | 0 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_pmp_w | MMU_PMP | 0.0473 | 0.0473 | 2614 | 0 |
| &nbsp;&nbsp;&nbsp;&nbsp;u_ptw | MMU_PTW | 0.0163 | 0.0163 | 400 | 131 |
| &nbsp;&nbsp;u_rf | CORE_RF | 0.2876 | 0.2876 | 8055 | 1984 |

### レイアウト試行に向けて

- **ダイ（コア）サイズの目安**（マクロなし、正方形の場合）:

  | 構成 | 配置率 60% | 配置率 50% | 配置率 40% |
  |---|---:|---:|---:|
  | core（4.23 mm²） | 7.05 mm²（2.66 mm 角） | 8.46 mm²（2.91 mm 角） | 10.6 mm²（3.25 mm 角） |
  | core_trim（3.24 mm²） | 5.41 mm²（2.33 mm 角） | 6.49 mm²（2.55 mm 角） | 8.11 mm²（2.85 mm 角） |

  合成直後の面積なので、P&R でのバッファ挿入、サイズ変更、クロックツリー、タップ/フィルセルの分が増える。
  最初は配置率 40〜50% で始めて、通ってから詰めるのが無難。
- **ピン数**: CPU_CORE のポートは 41 本、745 bit。そのうち検証用のトレース出力（`trace_*` 169 bit、`trap_*` 136 bit）が 305 bit ある。
  レイアウト試行でこれを外すなら、トレースポートを出さないラッパを置けば、それを駆動するだけのロジックは（フラット化して合成すれば）消える。
  外さない場合でも、2.6 mm 角の周囲（約 10 mm）に 745 本は十分に並ぶ。
- **マクロなし・FF のみ**: レジスタファイル（RF/FRF）、BTB、TLB はすべて FF になっている（FF 21,429 個、面積の 35%）。
  レイアウトではこれらの配線混雑が出やすい。
- **P&R の規模**: 約 15 万セル（core）、12 万セル（core_trim）。CLAUDE.md のとおり、クラウドの VM（4 vCPU / 16 GB）ではなくローカルで回すのがよい規模。
  まず core_trim で流れを確認するのも手。
- **LibreLane での合成**: LibreLane のデフォルトの Yosys 合成（`USE_SLANG: True`）で読むときも、`SLANG_ARGUMENTS` に `--allow-use-before-declare` が要る（CORE_FPU の件）。

## 再現方法

```sh
# ロジック（1 構成あたり約 11 分。10 分を超えるのでバックグラウンドで）
nix develop -c core_synth/run_synth.sh default   # 64 sets x 4 ways
nix develop -c core_synth/run_synth.sh small     # 16 sets x 2 ways
nix develop -c core_synth/run_synth.sh trim      # small + BTB 16, TLB 4, PMP 4, MSHR/WB 1, PQ 8
# CPU_CORE 単体（キャッシュなし、1 構成あたり約 8 分）
nix develop -c core_synth/run_synth.sh core      # RTL の既定値
nix develop -c core_synth/run_synth.sh core_trim # BTB 16, TLB 4, PMP 4, PQ 8
# タグまわりの単体合成（数十秒）
nix develop -c core_synth/run_est.sh
# SRAM マクロの面積表
python3 core_synth/sram_area.py
```

結果は `core_synth/out/<構成>/`（`stat.txt`、`stat.json`、`report.md`、ネットリスト）に出る（git には入れていない）。
ローカルでは CLAUDE.md のとおり `nix develop -c env -u PDK -u PDK_ROOT -u LD_LIBRARY_PATH ...` で実行する。

`report.py` の注意: Yosys 0.66 の `stat -json -top` の各モジュールの `area` は配下のモジュールを含む値なので、
インスタンス自身の面積は、そこから直下のサブモジュールの `area` を引いて求めている（`stat.txt` の各モジュールの Chip area の合計 5.811 mm² と一致することを確認した）。
