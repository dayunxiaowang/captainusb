`timescale 1ns / 1ps

module captainusb_ring_rx_dma #(
    parameter int unsigned SLOT_BYTES   = 5120,
    parameter int unsigned RING_DEPTH   = 512,
    parameter int unsigned BURST_DW_MAX = 32
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        ring_enable,
    input  wire [63:0] ring_base_addr,
    input  wire [15:0] ring_prod_ptr,
    input  wire [15:0] ring_cons_ptr,
    output reg         prod_update_valid = 1'b0,
    output reg  [15:0] prod_update_value = 16'h0000,
    output reg         wr_req_valid     = 1'b0,
    input  wire        wr_req_ready,
    output reg  [63:0] wr_req_addr      = 64'h0,
    output wire [31:0] wr_req_data,
    output reg  [9:0]  wr_req_length_dw = 10'd1,
    output wire [3:0]  wr_req_first_be,
    output wire [3:0]  wr_req_last_be,
    output wire [31:0] wr_data,
    output wire        wr_data_valid,
    input  wire        wr_data_ready,
    input  wire [31:0] stream_data,
    input  wire        stream_valid,
    output wire        stream_ready,
    output wire        busy,
    output reg  [31:0] debug_slot_count = 32'h0,
    output reg  [31:0] debug_mwr_count  = 32'h0
);
    localparam int unsigned SLOT_DW = SLOT_BYTES / 4;
    localparam int unsigned RING_MASK = RING_DEPTH - 1;

    localparam logic [3:0]
        ST_IDLE       = 4'd0,
        ST_CAPTURE    = 4'd1,
        ST_PLAN_BURST = 4'd2,
        ST_ISSUE_MWR  = 4'd3,
        ST_PUSH       = 4'd4,
        ST_UPDATE     = 4'd5,
        ST_WAIT       = 4'd6;

    reg [3:0]  state = ST_IDLE;
    reg [15:0] active_prod = 16'h0;
    reg [63:0] slot_addr = 64'h0;
    reg [12:0] capture_count = 13'd0;
    reg [12:0] dma_offset_dw = 13'd0;
    reg [9:0]  burst_dw = 10'd0;
    reg [9:0]  burst_remain = 10'd0;
    reg [9:0]  burst_pop_idx = 10'd0;
    (* ram_style = "block" *) reg [31:0] slot_bram [0:SLOT_DW-1];
    reg [12:0] bram_rd_addr = 13'd0;
    reg [31:0] bram_rd_data_q = 32'h0;

    assign busy = (state != ST_IDLE);
    assign wr_req_first_be = 4'hf;
    assign wr_req_last_be  = (wr_req_length_dw > 10'd1) ? 4'hf : 4'h0;
    assign wr_req_data     = bram_rd_data_q;
    assign stream_ready = (state == ST_CAPTURE) && (capture_count < SLOT_DW[12:0]);
    wire        pop_eff     = wr_data_valid && wr_data_ready;
    wire [12:0] eff_rd_addr = bram_rd_addr + (pop_eff ? 13'd1 : 13'd0);
    assign wr_data       = slot_bram[eff_rd_addr];
    assign wr_data_valid = (state == ST_PUSH) && (burst_remain > 10'd0);
    wire ring_full = ((ring_prod_ptr - ring_cons_ptr) >= RING_DEPTH[15:0]);

    function automatic [63:0] calc_slot_addr;
        input [63:0] base;
        input [15:0] prod;
        reg [8:0] idx;
        begin
            idx = prod[8:0];
            calc_slot_addr = base + ({55'd0, idx} << 12) + ({55'd0, idx} << 10);
        end
    endfunction

    function automatic [9:0] plan_burst;
        input [31:0] byte_addr;
        input [12:0] remaining_dw;
        reg [10:0] dw_to_4k;
        reg [10:0] cap;
        begin
            dw_to_4k = 11'd1024 - {1'b0, byte_addr[11:2]};
            cap = (remaining_dw > 13'd1024) ? dw_to_4k
                : ((remaining_dw[10:0] < dw_to_4k) ? remaining_dw[10:0] : dw_to_4k);
            if (cap > 11'(BURST_DW_MAX))
                cap = 11'(BURST_DW_MAX);
            plan_burst = cap[9:0];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            wr_req_valid <= 1'b0;
            wr_req_length_dw <= 10'd1;
            prod_update_valid <= 1'b0;
            capture_count <= 13'd0;
            dma_offset_dw <= 13'd0;
            burst_dw <= 10'd0;
            burst_remain <= 10'd0;
            burst_pop_idx <= 10'd0;
            bram_rd_addr <= 13'd0;
            active_prod <= 16'h0;
        end else begin
            prod_update_valid <= 1'b0;
            if (wr_req_valid && wr_req_ready &&
                (state != ST_ISSUE_MWR) && (state != ST_PUSH)) begin
                wr_req_valid <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    if (ring_enable && !ring_full) begin
                        active_prod <= ring_prod_ptr;
                        capture_count <= 13'd0;
                        state <= ST_CAPTURE;
                    end
                end

                ST_CAPTURE: begin
                    if (stream_valid && stream_ready) begin
                        slot_bram[capture_count] <= stream_data;
                        if (capture_count + 13'd1 >= SLOT_DW[12:0]) begin
                            slot_addr <= calc_slot_addr(ring_base_addr, active_prod);
                            dma_offset_dw <= 13'd0;
                            capture_count <= capture_count + 13'd1;
                            state <= ST_PLAN_BURST;
                        end else begin
                            capture_count <= capture_count + 13'd1;
                        end
                    end
                end

                ST_PLAN_BURST: begin
                    if (dma_offset_dw < SLOT_DW[12:0]) begin
                        burst_dw <= plan_burst(
                            slot_addr[31:0] + {17'd0, dma_offset_dw, 2'b00},
                            SLOT_DW[12:0] - dma_offset_dw
                        );
                        burst_pop_idx <= 10'd0;
                        bram_rd_addr <= dma_offset_dw;
                        state <= ST_ISSUE_MWR;
                    end else begin
                        state <= ST_UPDATE;
                    end
                end

                ST_ISSUE_MWR: begin
                    if (!wr_req_valid) begin
                        wr_req_addr <= slot_addr + {49'd0, dma_offset_dw, 2'b00};
                        wr_req_length_dw <= burst_dw;
                        bram_rd_data_q <= slot_bram[dma_offset_dw];
                        wr_req_valid <= 1'b1;
                        debug_mwr_count <= debug_mwr_count + 1'b1;
                        if (burst_dw > 10'd1) begin
                            burst_remain <= burst_dw;
                            state <= ST_PUSH;
                        end else begin
                            dma_offset_dw <= dma_offset_dw + {3'd0, burst_dw};
                            state <= ST_PLAN_BURST;
                        end
                    end
                end

                ST_PUSH: begin
                    if (wr_data_ready && wr_data_valid) begin
                        if (burst_remain <= 10'd1) begin
                            wr_req_valid <= 1'b0;
                            dma_offset_dw <= dma_offset_dw + {3'd0, burst_dw};
                            burst_remain <= 10'd0;
                            state <= ST_PLAN_BURST;
                        end else begin
                            burst_remain <= burst_remain - 10'd1;
                            bram_rd_addr <= bram_rd_addr + 13'd1;
                        end
                    end
                end

                ST_UPDATE: begin
                    prod_update_valid <= 1'b1;
                    prod_update_value <= active_prod + 16'd1;
                    debug_slot_count <= debug_slot_count + 1'b1;
                    state <= ST_WAIT;
                end

                ST_WAIT: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
