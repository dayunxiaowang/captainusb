`timescale 1ns / 1ps

module captainusb_tlp_rx64 (
    input  wire        clk,
    input  wire        rst,

    input  wire [63:0] rx_tdata,
    input  wire [7:0]  rx_tkeep,
    input  wire        rx_tlast,
    input  wire        rx_tvalid,
    output wire        rx_tready,
    input  wire [21:0] rx_tuser,

    output reg         bar_rd_valid = 1'b0,
    output reg         bar_wr_valid = 1'b0,
    output reg  [15:0] bar_addr = 16'h0000,
    output reg  [31:0] bar_wr_data = 32'h00000000,
    output reg  [3:0]  bar_be = 4'h0,
    output reg  [15:0] bar_req_id = 16'h0000,
    output reg  [7:0]  bar_tag = 8'h00,
    output reg  [6:0]  bar_lower_addr = 7'h00,

    output reg         cpl_valid = 1'b0,
    output reg  [7:0]  cpl_tag = 8'h00,
    output reg  [31:0] cpl_data = 32'h00000000,

    output reg  [31:0] unsupported_count = 32'h00000000
);
    localparam logic [2:0]
        ST_IDLE       = 3'd0,
        ST_BAR_SECOND = 3'd1,
        ST_DROP       = 3'd2,
        ST_CPL_STREAM = 3'd3,
        ST_CPL_BUFFER = 3'd4;

    reg [2:0]  state = ST_IDLE;
    reg [31:0] h0 = 32'h00000000;
    reg [31:0] h1 = 32'h00000000;
    reg [6:0]  saved_fmt_type = 7'h00;
    reg        saved_bar0 = 1'b0;
    reg        saved_is_mrd32 = 1'b0;
    reg        saved_is_mwr32 = 1'b0;
    reg        saved_is_cpld = 1'b0;

    reg [9:0]  cpl_remaining = 10'd0;
    reg [31:0] cpl_buffered = 32'h00000000;
    reg        cpl_buf_pending = 1'b0;
    reg        cpl_tlast_seen = 1'b0;
    assign rx_tready = !cpl_buf_pending;

    wire [6:0] fmt_type = rx_tdata[31:25];
    wire       is_mrd32 = (fmt_type == 7'b0000000);
    wire       is_mwr32 = (fmt_type == 7'b0100000);
    wire       is_cpld  = (fmt_type == 7'b0100101);
    wire [6:0] bar_hit  = rx_tuser[8:2];
    wire       is_bar0  = bar_hit[0];
    wire [9:0] length_dw = rx_tdata[9:0];

    function automatic [31:0] bswap32;
        input [31:0] value;
        begin
            bswap32 = {value[7:0], value[15:8], value[23:16], value[31:24]};
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            bar_rd_valid <= 1'b0;
            bar_wr_valid <= 1'b0;
            cpl_valid <= 1'b0;
            cpl_remaining <= 10'd0;
            cpl_buf_pending <= 1'b0;
            cpl_tlast_seen <= 1'b0;
            unsupported_count <= 32'h00000000;
        end else begin
            bar_rd_valid <= 1'b0;
            bar_wr_valid <= 1'b0;
            cpl_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (rx_tvalid && rx_tready) begin
                        h0 <= rx_tdata[31:0];
                        h1 <= rx_tdata[63:32];
                        saved_fmt_type <= fmt_type;
                        saved_bar0 <= is_bar0;
                        saved_is_mrd32 <= is_mrd32;
                        saved_is_mwr32 <= is_mwr32;
                        saved_is_cpld <= is_cpld;

                        if ((is_mrd32 || is_mwr32 || is_cpld) && !rx_tlast) begin
                            state <= ST_BAR_SECOND;
                        end else begin
                            unsupported_count <= unsupported_count + 1'b1;
                            state <= rx_tlast ? ST_IDLE : ST_DROP;
                        end
                    end
                end

                ST_BAR_SECOND: begin
                    if (rx_tvalid && rx_tready) begin
                        if (saved_bar0 && saved_is_mrd32 && (h0[9:0] == 10'd1)) begin
                            bar_rd_valid <= 1'b1;
                            bar_addr <= {rx_tdata[15:2], 2'b00};
                            bar_be <= h1[3:0];
                            bar_req_id <= h1[31:16];
                            bar_tag <= h1[15:8];
                            bar_lower_addr <= {rx_tdata[6:2], 2'b00};
                            state <= rx_tlast ? ST_IDLE : ST_DROP;
                        end else if (saved_bar0 && saved_is_mwr32 && (h0[9:0] == 10'd1)) begin
                            bar_wr_valid <= 1'b1;
                            bar_addr <= {rx_tdata[15:2], 2'b00};
                            bar_wr_data <= bswap32(rx_tdata[63:32]);
                            bar_be <= h1[3:0];
                            bar_req_id <= h1[31:16];
                            bar_tag <= h1[15:8];
                            bar_lower_addr <= {rx_tdata[6:2], 2'b00};
                            state <= rx_tlast ? ST_IDLE : ST_DROP;
                        end else if (saved_is_cpld) begin
                            cpl_valid <= 1'b1;
                            cpl_tag <= rx_tdata[15:8];
                            cpl_data <= bswap32(rx_tdata[63:32]);

                            if (h0[9:0] > 10'd1 && !rx_tlast) begin
                                cpl_remaining <= h0[9:0] - 10'd1;
                                cpl_tlast_seen <= 1'b0;
                                state <= ST_CPL_STREAM;
                            end else begin
                                state <= rx_tlast ? ST_IDLE : ST_DROP;
                            end
                        end else begin
                            unsupported_count <= unsupported_count + 1'b1;
                            state <= rx_tlast ? ST_IDLE : ST_DROP;
                        end
                    end
                end

                ST_CPL_STREAM: begin
                    if (rx_tvalid && rx_tready) begin
                        cpl_valid <= 1'b1;
                        cpl_data <= bswap32(rx_tdata[31:0]);
                        cpl_remaining <= cpl_remaining - 10'd1;

                        if ((rx_tkeep[7:4] == 4'hf) && (cpl_remaining > 10'd1)) begin
                            cpl_buffered <= bswap32(rx_tdata[63:32]);
                            cpl_buf_pending <= 1'b1;
                            cpl_tlast_seen <= rx_tlast;
                            state <= ST_CPL_BUFFER;
                        end else begin
                            if (cpl_remaining <= 10'd1) begin
                                state <= rx_tlast ? ST_IDLE : ST_DROP;
                            end
                        end
                    end
                end

                ST_CPL_BUFFER: begin
                    cpl_valid <= 1'b1;
                    cpl_data <= cpl_buffered;
                    cpl_buf_pending <= 1'b0;
                    cpl_remaining <= cpl_remaining - 10'd1;

                    if (cpl_remaining <= 10'd1) begin
                        state <= cpl_tlast_seen ? ST_IDLE : ST_DROP;
                    end else begin
                        state <= cpl_tlast_seen ? ST_IDLE : ST_CPL_STREAM;
                    end
                end

                ST_DROP: begin
                    if (rx_tvalid && rx_tready && rx_tlast) begin
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    wire unused_inputs = ^{rx_tkeep, saved_fmt_type, length_dw, bar_hit[6:1]};
endmodule
