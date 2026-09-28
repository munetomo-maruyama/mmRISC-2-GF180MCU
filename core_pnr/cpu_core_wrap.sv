//---------------------------------------------------------------------------
// cpu_core_wrap.sv
//
// Layout trial of mmRISC-2 CPU_CORE alone (no caches, no pad ring).
//
// CPU_CORE with the RTL default parameters, with the verification outputs
// (trace_* 169 bit, trap_* 136 bit) left unconnected, so that the logic
// driving only them is removed by synthesis and the block has 440 signal
// pins instead of 745. Everything else is passed through unchanged.
//---------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module cpu_core_wrap
    (
    `ifdef USE_POWER_PINS
        inout  wire         VDD,
        inout  wire         VSS,
    `endif
        input  wire         clk,
        input  wire         rst_n,

        // instruction cache
        output wire         i_req_valid,
        input  wire         i_req_ready,
        output wire [39:0]  i_req_addr,
        output wire [39:0]  i_req_paddr,
        input  wire         i_resp_valid,
        input  wire [63:0]  i_resp_data,
        input  wire         i_resp_error,
        output wire         i_flush_valid,
        input  wire         i_flush_done,
        output wire         i_kill,
        output wire         i_cancel,

        // data cache
        output wire         d_req_valid,
        input  wire         d_req_ready,
        output wire [39:0]  d_req_addr,
        output wire [39:0]  d_req_paddr,
        output wire [1:0]   d_req_size,
        output wire [3:0]   d_req_cmd,
        output wire [63:0]  d_req_wdata,
        input  wire         d_resp_valid,
        input  wire [63:0]  d_resp_data,
        input  wire         d_resp_error,

        // interrupts (CLINT, PLIC)
        input  wire         irq_m_soft,
        input  wire         irq_m_timer,
        input  wire         irq_m_ext,
        input  wire         irq_s_ext,
        input  wire [63:0]  mtime
    );

    CPU_CORE u_cpu_core
        (
            .clk           (clk),
            .rst_n         (rst_n),

            .i_req_valid   (i_req_valid),
            .i_req_ready   (i_req_ready),
            .i_req_addr    (i_req_addr),
            .i_req_paddr   (i_req_paddr),
            .i_resp_valid  (i_resp_valid),
            .i_resp_data   (i_resp_data),
            .i_resp_error  (i_resp_error),
            .i_flush_valid (i_flush_valid),
            .i_flush_done  (i_flush_done),
            .i_kill        (i_kill),
            .i_cancel      (i_cancel),

            .d_req_valid   (d_req_valid),
            .d_req_ready   (d_req_ready),
            .d_req_addr    (d_req_addr),
            .d_req_paddr   (d_req_paddr),
            .d_req_size    (d_req_size),
            .d_req_cmd     (d_req_cmd),
            .d_req_wdata   (d_req_wdata),
            .d_resp_valid  (d_resp_valid),
            .d_resp_data   (d_resp_data),
            .d_resp_error  (d_resp_error),

            .irq_m_soft    (irq_m_soft),
            .irq_m_timer   (irq_m_timer),
            .irq_m_ext     (irq_m_ext),
            .irq_s_ext     (irq_s_ext),
            .mtime         (mtime),

            // verification outputs: not brought out
            .trace_valid   (),
            .trace_pc      (),
            .trace_insn    (),
            .trace_rd_we   (),
            .trace_rd      (),
            .trace_rd_data (),
            .trace_priv    (),
            .trap_valid    (),
            .trap_is_int   (),
            .trap_cause    (),
            .trap_epc      (),
            .trap_tval     (),
            .trap_to_s     ()
        );

endmodule

`default_nettype wire
