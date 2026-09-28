//---------------------------------------------------------------------------
// TAG_VALID_DIRTY.sv  (area estimate only, not part of the design)
//
// The valid / dirty part of CACHE_TAG_ARRAY (mmRISC-2 2f59109,
// RTL/CPU/CPU_CACHE/CACHE_TAG_ARRAY/CACHE_TAG_ARRAY.sv), copied without the
// tag memory. CACHE_TAG_ARRAY is blackboxed in the CPU_TOP synthesis because
// its tags go into SRAM macros, but the valid / dirty bits stay flip-flops
// (single-cycle invalidate-all, combinational sc_* port), so their area is
// added to the logic separately. Synthesised by core_synth/run_est.sh.
//---------------------------------------------------------------------------

module TAG_VALID_DIRTY
    #(
        parameter int SETS     = 64,
        parameter int WAYS     = 4,
        parameter int WAY_BITS = (WAYS > 1) ? $clog2(WAYS) : 1
    )
    (
        input  logic                        clk,
        input  logic                        rst_n,
        input  logic                        rd_en,
        input  logic [$clog2(SETS)-1:0]     rd_index,
        output logic [WAYS-1:0]             rd_valid,
        output logic [WAYS-1:0]             rd_dirty,
        input  logic                        wr_en,
        input  logic [$clog2(SETS)-1:0]     wr_index,
        input  logic [WAY_BITS-1:0]         wr_way,
        input  logic                        wr_valid,
        input  logic                        wr_dirty,
        input  logic [$clog2(SETS)-1:0]     sc_index,
        output logic [WAYS-1:0]             sc_valid,
        output logic [WAYS-1:0]             sc_dirty,
        input  logic                        inv_all
    );

    logic [SETS*WAYS-1:0] valid_bit;
    logic [SETS*WAYS-1:0] dirty_bit;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_bit <= '0;
            dirty_bit <= '0;
        end else if (inv_all) begin
            valid_bit <= '0;
            dirty_bit <= '0;
        end else if (wr_en) begin
            valid_bit[int'(wr_index) * WAYS + int'(wr_way)] <= wr_valid;
            dirty_bit[int'(wr_index) * WAYS + int'(wr_way)] <= wr_dirty;
        end
    end

    always_ff @(posedge clk) begin
        if (rd_en) begin
            rd_valid <= valid_bit[int'(rd_index) * WAYS +: WAYS];
            rd_dirty <= dirty_bit[int'(rd_index) * WAYS +: WAYS];
        end
    end

    assign sc_valid = valid_bit[int'(sc_index) * WAYS +: WAYS];
    assign sc_dirty = dirty_bit[int'(sc_index) * WAYS +: WAYS];

endmodule : TAG_VALID_DIRTY
