`timescale 1ns / 1ps

module captainusb_pcie_requester_7x #(
    parameter int unsigned MAX_RD_TAGS = 32
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        rd_req_valid,
    output wire        rd_req_ready,
    input  wire [63:0] rd_req_addr,
    input  wire [9:0]  rd_req_length_dw,
    input  wire [12:0] rd_req_bram_offset,
    output reg         rd_cpl_valid = 1'b0,
    output reg  [31:0] rd_cpl_data  = 32'h0,
    output reg  [12:0] rd_cpl_bram_offset = 13'd0,
    output reg         rd_cpl_tag_done = 1'b0,
    output wire        rd_tag_available,
    output wire        rd_all_tags_idle,
    input  wire        wr_req_valid,
    output wire        wr_req_ready,
    input  wire [63:0] wr_req_addr,
    input  wire [31:0] wr_req_data,
    input  wire [9:0]  wr_req_length_dw,
    input  wire [3:0]  wr_req_first_be,
    input  wire [3:0]  wr_req_last_be,

    input  wire [31:0] wr_data,
    input  wire        wr_data_valid,
    output wire        wr_data_ready,
    output reg         tx_req_valid = 1'b0,
    input  wire        tx_req_ready,
    output reg  [1:0]  tx_req_type = 2'd0,
    output reg  [63:0] tx_req_addr = 64'h0,
    output reg  [31:0] tx_req_data = 32'h0,
    output reg  [7:0]  tx_req_tag = 8'h0,
    output reg  [9:0]  tx_req_length_dw = 10'd1,
    output reg  [3:0]  tx_req_first_be = 4'hf,
    output reg  [3:0]  tx_req_last_be = 4'h0,

    output wire [31:0] tx_data_word,
    output wire        tx_data_valid,
    input  wire        tx_data_ready,
    input  wire        cpl_valid,
    input  wire [7:0]  cpl_tag,
    input  wire [31:0] cpl_data,
    output wire        busy,
    output reg  [31:0] tag_mismatch_count = 32'h0
);
    localparam logic [1:0] REQ_MRD32 = 2'd1;
    localparam logic [1:0] REQ_MWR32 = 2'd2;
    localparam TAG_BITS = $clog2(MAX_RD_TAGS);
    reg [TAG_BITS:0] init_count = '0;
    reg              init_done  = 1'b0;
    reg              init_tag   = 1'b1;
    (* ram_style = "distributed" *)
    reg [TAG_BITS-1:0] tag_fifo_mem [0:MAX_RD_TAGS-1];
    reg [TAG_BITS:0]   tag_fifo_wr_ptr = '0;
    reg [TAG_BITS:0]   tag_fifo_rd_ptr = '0;
    wire               tag_fifo_empty = (tag_fifo_wr_ptr == tag_fifo_rd_ptr);

    reg                tag_fifo_we = 1'b0;
    reg [TAG_BITS-1:0] tag_fifo_wr_tag = '0;
    (* ram_style = "distributed" *)
    reg [9:0]  tag_remain      [0:MAX_RD_TAGS-1];
    (* ram_style = "distributed" *)
    reg [12:0] tag_next_offset [0:MAX_RD_TAGS-1];
    (* ram_style = "distributed" *)
    reg        tag_active_a    [0:MAX_RD_TAGS-1];
    (* ram_style = "distributed" *)
    reg        tag_active_b    [0:MAX_RD_TAGS-1];
    reg [TAG_BITS+1-1:0] tags_outstanding = '0;
    reg                  inc_active_tag;
    reg                  dec_active_tag;
    localparam logic [1:0]
        WR_IDLE  = 2'd0,
        WR_ISSUE = 2'd1,
        WR_BURST = 2'd2;
    reg [1:0] wr_state       = WR_IDLE;
    reg [9:0] wr_burst_remain = 10'd0;
    wire can_accept_rd = init_done && !tx_req_valid && !tag_fifo_empty && (wr_state == WR_IDLE);
    wire can_accept_wr = init_done && !tx_req_valid && (wr_state == WR_IDLE);

    assign rd_req_ready    = can_accept_rd;
    assign wr_req_ready    = can_accept_wr && !rd_req_valid;
    assign busy            = !init_done || (tags_outstanding != 0) || (wr_state != WR_IDLE);
    assign rd_tag_available = init_done && !tag_fifo_empty;
    assign rd_all_tags_idle = init_done && (tags_outstanding == 0);

    assign tx_data_word  = wr_data;
    assign tx_data_valid = (wr_state == WR_BURST) && wr_data_valid && !tx_req_valid;
    assign wr_data_ready = (wr_state == WR_BURST) && tx_data_ready && !tx_req_valid;
    wire [TAG_BITS-1:0] cpl_idx       = cpl_tag[TAG_BITS-1:0];
    wire                cpl_tag_active = (tag_active_b[cpl_idx] != tag_active_a[cpl_idx]);
    wire                cpl_hit        = cpl_valid && cpl_tag_active;
    wire                cpl_last       = cpl_hit && (tag_remain[cpl_idx] == 10'd1);
    always @(posedge clk) begin
        if (rst) begin
            init_done  <= 1'b0;
            init_count <= '0;
            init_tag   <= 1'b1;
        end else if (!init_done) begin
            if (init_count == MAX_RD_TAGS[TAG_BITS:0]) begin
                init_done <= 1'b1;
                init_tag  <= 1'b0;
            end else begin
                init_count <= init_count + 1;
                init_tag   <= ((init_count + 1) < MAX_RD_TAGS[TAG_BITS:0]);
            end
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            tx_req_valid       <= 1'b0;
            rd_cpl_valid       <= 1'b0;
            rd_cpl_tag_done    <= 1'b0;
            wr_state           <= WR_IDLE;
            wr_burst_remain    <= 10'd0;
            tag_mismatch_count <= 32'h0;
            tags_outstanding   <= '0;
            tag_fifo_wr_ptr    <= '0;
            tag_fifo_rd_ptr    <= '0;
        end else begin
            rd_cpl_valid    <= 1'b0;
            rd_cpl_tag_done <= 1'b0;
            inc_active_tag  = 1'b0;
            dec_active_tag  = 1'b0;
            tag_fifo_we     = 1'b0;

            if (tx_req_valid && tx_req_ready)
                tx_req_valid <= 1'b0;
            if (init_tag && !init_done) begin
                tag_active_a[init_count[TAG_BITS-1:0]] <= 1'b0;
                tag_active_b[init_count[TAG_BITS-1:0]] <= 1'b0;
                tag_fifo_we  = 1'b1;
                tag_fifo_wr_tag = init_count[TAG_BITS-1:0];
            end
            if (init_done && cpl_hit) begin
                rd_cpl_valid       <= 1'b1;
                rd_cpl_data        <= cpl_data;
                rd_cpl_bram_offset <= tag_next_offset[cpl_idx];
                tag_next_offset[cpl_idx] <= tag_next_offset[cpl_idx] + 13'd1;
                tag_remain[cpl_idx]      <= tag_remain[cpl_idx] - 10'd1;

                if (cpl_last) begin
                    tag_active_b[cpl_idx] <= tag_active_a[cpl_idx];
                    tag_fifo_we     = 1'b1;
                    tag_fifo_wr_tag = cpl_idx;
                    rd_cpl_tag_done <= 1'b1;
                    dec_active_tag  = 1'b1;
                end
            end else if (init_done && cpl_valid && !cpl_tag_active) begin
                tag_mismatch_count <= tag_mismatch_count + 1'b1;
            end
            if (rd_req_valid && rd_req_ready) begin
                begin : blk_alloc
                    reg [TAG_BITS-1:0] alloc_tag;
                    alloc_tag = tag_fifo_mem[tag_fifo_rd_ptr[TAG_BITS-1:0]];

                    tx_req_valid     <= 1'b1;
                    tx_req_type      <= REQ_MRD32;
                    tx_req_addr      <= rd_req_addr;
                    tx_req_data      <= 32'h0;
                    tx_req_tag       <= {{(8-TAG_BITS){1'b0}}, alloc_tag};
                    tx_req_length_dw <= (rd_req_length_dw == 10'd0) ? 10'd1 : rd_req_length_dw;
                    tx_req_first_be  <= 4'hf;
                    tx_req_last_be   <= (rd_req_length_dw > 10'd1) ? 4'hf : 4'h0;

                    tag_remain[alloc_tag]      <= (rd_req_length_dw == 10'd0) ? 10'd1 : rd_req_length_dw;
                    tag_next_offset[alloc_tag]  <= rd_req_bram_offset;
                    tag_active_a[alloc_tag]    <= !tag_active_b[alloc_tag];

                    tag_fifo_rd_ptr <= tag_fifo_rd_ptr + 1;
                    inc_active_tag  = 1'b1;
                end
            end
            else if (wr_req_valid && wr_req_ready) begin
                tx_req_valid     <= 1'b1;
                tx_req_type      <= REQ_MWR32;
                tx_req_addr      <= wr_req_addr;
                tx_req_data      <= wr_req_data;
                tx_req_tag       <= 8'h00;
                tx_req_length_dw <= (wr_req_length_dw == 10'd0) ? 10'd1 : wr_req_length_dw;
                tx_req_first_be  <= wr_req_first_be;
                tx_req_last_be   <= (wr_req_length_dw <= 10'd1) ? 4'h0 : wr_req_last_be;
                if (wr_req_length_dw > 10'd1) begin
                    wr_burst_remain <= wr_req_length_dw;
                    wr_state        <= WR_BURST;
                end else begin
                    wr_state <= WR_ISSUE;
                end
            end
            case (wr_state)
                WR_ISSUE: begin
                    if (!tx_req_valid) wr_state <= WR_IDLE;
                end
                WR_BURST: begin
                    if (!tx_req_valid && tx_data_valid && tx_data_ready) begin
                        if (wr_burst_remain <= 10'd1)
                            wr_state <= WR_IDLE;
                        else
                            wr_burst_remain <= wr_burst_remain - 10'd1;
                    end
                end
                default: ;
            endcase
            if (tag_fifo_we) begin
                tag_fifo_mem[tag_fifo_wr_ptr[TAG_BITS-1:0]] <= tag_fifo_wr_tag;
                tag_fifo_wr_ptr <= tag_fifo_wr_ptr + 1;
            end
            tags_outstanding <= tags_outstanding
                + {{TAG_BITS{1'b0}}, inc_active_tag}
                - {{TAG_BITS{1'b0}}, dec_active_tag};
        end
    end
endmodule
