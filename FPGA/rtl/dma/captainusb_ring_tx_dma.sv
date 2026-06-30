`timescale 1ns / 1ps

module captainusb_ring_tx_dma #(
    parameter int unsigned SLOT_BYTES   = 5120,
    parameter int unsigned RING_DEPTH   = 512,
    parameter int unsigned BURST_DW_MAX = 128
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        ring_enable,
    input  wire [63:0] ring_base_addr,
    input  wire [15:0] ring_prod_ptr,
    input  wire [15:0] ring_cons_ptr,
    output reg         cons_update_valid = 1'b0,
    output reg  [15:0] cons_update_value = 16'h0000,

    output reg         rd_req_valid = 1'b0,
    input  wire        rd_req_ready,
    output reg  [63:0] rd_req_addr = 64'h0,
    output reg  [9:0]  rd_req_length_dw = 10'd1,
    output reg  [12:0] rd_req_bram_offset = 13'd0,
    input  wire        rd_cpl_valid,
    input  wire [31:0] rd_cpl_data,
    input  wire [12:0] rd_cpl_bram_offset,
    input  wire        rd_cpl_tag_done,
    input  wire        rd_tag_available,
    input  wire        rd_all_tags_idle,

    output wire [31:0] stream_data,
    output reg         stream_valid = 1'b0,
    input  wire        stream_ready,

    output wire        busy,
    output reg  [31:0] debug_slot_count = 32'h0,
    output reg  [31:0] debug_mrd_count  = 32'h0
);
    localparam int unsigned SLOT_DW = SLOT_BYTES / 4;
    localparam int unsigned RING_MASK = RING_DEPTH - 1;
    localparam logic [2:0]
        FILL_IDLE      = 3'd0,
        FILL_PLAN      = 3'd1,
        FILL_ISSUE     = 3'd2,
        FILL_WAIT_TAG  = 3'd3,
        FILL_WAIT_ALL  = 3'd4;
    localparam logic [2:0]
        DRAIN_IDLE     = 3'd0,
        DRAIN_PREFETCH = 3'd1,
        DRAIN_STREAM   = 3'd2,
        DRAIN_UPDATE   = 3'd3,
        DRAIN_WAIT     = 3'd4;

    reg [2:0] fill_state  = FILL_IDLE;
    reg [2:0] drain_state = DRAIN_IDLE;
    reg        wr_bank = 1'b0;
    reg        drain_bank = 1'b0;
    reg        bank_0_has_data = 1'b0;
    reg        bank_1_has_data = 1'b0;
    reg [15:0] bank_cons_0 = 16'h0;
    reg [15:0] bank_cons_1 = 16'h0;
    reg [15:0] fill_next_cons = 16'h0;
    reg [63:0] fill_slot_addr = 64'h0;
    reg [12:0] fill_offset_dw = 13'd0;
    reg [9:0]  next_burst_r = 10'd0;
    reg [12:0] stream_offset = 13'd0;
    (* ram_style = "block" *) reg [31:0] bram_0 [0:SLOT_DW-1];
    (* ram_style = "block" *) reg [31:0] bram_1 [0:SLOT_DW-1];
    reg [31:0] bram_rd_data = 32'h0;

    wire fully_idle = (fill_state == FILL_IDLE) &&
                      (drain_state == DRAIN_IDLE) &&
                      !bank_0_has_data && !bank_1_has_data;

    assign busy = !fully_idle;
    assign stream_data = bram_rd_data;

    wire        fill_bank_free = wr_bank ? !bank_1_has_data : !bank_0_has_data;
    wire [15:0] fill_use_cons  = fully_idle ? ring_cons_ptr : fill_next_cons;
    wire        fill_can_start = ring_enable && fill_bank_free &&
                                 (fill_use_cons != ring_prod_ptr);

    wire        drain_bank_ready = drain_bank ? bank_1_has_data : bank_0_has_data;
    wire [15:0] drain_cons       = drain_bank ? bank_cons_1 : bank_cons_0;

    function automatic [63:0] calc_slot_addr;
        input [63:0] base;
        input [15:0] cons;
        reg [8:0] idx;
        begin
            idx = cons[8:0];
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
        if (rd_cpl_valid) begin
            if (!wr_bank)
                bram_0[rd_cpl_bram_offset[10:0]] <= rd_cpl_data;
            else
                bram_1[rd_cpl_bram_offset[10:0]] <= rd_cpl_data;
        end
    end
    always @(posedge clk) begin
        if (!drain_bank)
            bram_rd_data <= bram_0[stream_offset[10:0]];
        else
            bram_rd_data <= bram_1[stream_offset[10:0]];
    end
    always @(posedge clk) begin
        if (rst) begin
            fill_state      <= FILL_IDLE;
            drain_state     <= DRAIN_IDLE;
            rd_req_valid    <= 1'b0;
            stream_valid    <= 1'b0;
            cons_update_valid <= 1'b0;
            wr_bank         <= 1'b0;
            drain_bank      <= 1'b0;
            bank_0_has_data <= 1'b0;
            bank_1_has_data <= 1'b0;
            fill_next_cons  <= 16'h0;
            fill_slot_addr  <= 64'h0;
            fill_offset_dw  <= 13'd0;
            stream_offset   <= 13'd0;
            next_burst_r    <= 10'd0;
            bank_cons_0     <= 16'h0;
            bank_cons_1     <= 16'h0;
        end else begin
            cons_update_valid <= 1'b0;

            if (rd_req_valid && rd_req_ready)
                rd_req_valid <= 1'b0;

            if (stream_valid && stream_ready)
                stream_valid <= 1'b0;
            case (fill_state)
                FILL_IDLE: begin
                    if (fill_can_start) begin
                        fill_slot_addr <= calc_slot_addr(ring_base_addr, fill_use_cons);
                        if (!wr_bank)
                            bank_cons_0 <= fill_use_cons;
                        else
                            bank_cons_1 <= fill_use_cons;
                        fill_next_cons <= fill_use_cons + 16'd1;
                        fill_offset_dw <= 13'd0;
                        fill_state <= FILL_PLAN;
                    end
                end

                FILL_PLAN: begin
                    if (fill_offset_dw < SLOT_DW[12:0]) begin
                        next_burst_r <= plan_burst(
                            fill_slot_addr[31:0] + {17'd0, fill_offset_dw, 2'b00},
                            SLOT_DW[12:0] - fill_offset_dw
                        );
                        fill_state <= FILL_ISSUE;
                    end else begin
                        fill_state <= FILL_WAIT_ALL;
                    end
                end

                FILL_ISSUE: begin
                    if (!rd_req_valid && rd_req_ready) begin
                        rd_req_addr <= fill_slot_addr + {49'd0, fill_offset_dw, 2'b00};
                        rd_req_length_dw <= next_burst_r;
                        rd_req_bram_offset <= fill_offset_dw;
                        rd_req_valid <= 1'b1;
                        debug_mrd_count <= debug_mrd_count + 1'b1;
                        fill_offset_dw <= fill_offset_dw + {3'd0, next_burst_r};
                        fill_state <= FILL_PLAN;
                    end else if (!rd_tag_available) begin
                        fill_state <= FILL_WAIT_TAG;
                    end
                end

                FILL_WAIT_TAG: begin
                    if (rd_tag_available)
                        fill_state <= FILL_PLAN;
                end

                FILL_WAIT_ALL: begin
                    if (rd_all_tags_idle) begin
                        if (!wr_bank)
                            bank_0_has_data <= 1'b1;
                        else
                            bank_1_has_data <= 1'b1;
                        wr_bank <= !wr_bank;
                        fill_state <= FILL_IDLE;
                    end
                end

                default: fill_state <= FILL_IDLE;
            endcase
            case (drain_state)
                DRAIN_IDLE: begin
                    if (drain_bank_ready) begin
                        stream_offset <= 13'd0;
                        drain_state <= DRAIN_PREFETCH;
                    end
                end

                DRAIN_PREFETCH: begin
                    drain_state <= DRAIN_STREAM;
                end

                DRAIN_STREAM: begin
                    if (stream_offset < SLOT_DW[12:0]) begin
                        if (!stream_valid || stream_ready) begin
                            stream_valid <= 1'b1;
                            stream_offset <= stream_offset + 13'd1;
                        end
                    end else begin
                        if (!stream_valid) begin
                            drain_state <= DRAIN_UPDATE;
                        end
                    end
                end

                DRAIN_UPDATE: begin
                    cons_update_valid <= 1'b1;
                    cons_update_value <= drain_cons + 16'd1;
                    debug_slot_count <= debug_slot_count + 1'b1;
                    if (!drain_bank)
                        bank_0_has_data <= 1'b0;
                    else
                        bank_1_has_data <= 1'b0;
                    drain_bank <= !drain_bank;
                    drain_state <= DRAIN_WAIT;
                end

                DRAIN_WAIT: begin
                    drain_state <= DRAIN_IDLE;
                end

                default: drain_state <= DRAIN_IDLE;
            endcase
        end
    end

    wire _unused = ^{rd_cpl_tag_done, 1'b0};
endmodule
