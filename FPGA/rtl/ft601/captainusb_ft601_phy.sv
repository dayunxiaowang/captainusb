`timescale 1ns / 1ps

module captainusb_ft601_phy (
    input  wire        clk,
    input  wire        rst,
    inout  wire [31:0] ft601_data,
    output wire [3:0]  ft601_be,
    input  wire        ft601_rxf_n,
    input  wire        ft601_txe_n,
    output reg         ft601_wr_n   = 1'b1,
    output wire        ft601_siwu_n,
    output reg         ft601_rd_n   = 1'b1,
    output reg         ft601_oe_n   = 1'b1,
    output reg  [31:0] rx_data  = 32'h0,
    output reg         rx_valid = 1'b0,
    input  wire [31:0] tx_data,
    input  wire        tx_valid,
    output wire        tx_ready,
    output wire        tx_word_written
);
    assign ft601_siwu_n = 1'b1;
    localparam [3:0] S_IDLE           = 4'h0;
    localparam [3:0] S_RX_WAIT1      = 4'h2;
    localparam [3:0] S_RX_WAIT2      = 4'h3;
    localparam [3:0] S_RX_WAIT3      = 4'h4;
    localparam [3:0] S_RX_ACTIVE     = 4'h5;
    localparam [3:0] S_RX_COOLDOWN1  = 4'h6;
    localparam [3:0] S_RX_COOLDOWN2  = 4'h7;
    localparam [3:0] S_TX_WAIT1      = 4'h8;
    localparam [3:0] S_TX_WAIT2      = 4'h9;
    localparam [3:0] S_TX_ACTIVE     = 4'ha;
    localparam [3:0] S_TX_COOLDOWN1  = 4'hb;
    localparam [3:0] S_TX_COOLDOWN2  = 4'hc;
    reg [31:0]      data_out [0:4];
    reg             oe                  = 1'b1;
    reg [3:0]       data_cooldown_count = 4'h0;
    reg [2:0]       data_queue_count    = 3'd0;
    reg [3:0]       state               = S_IDLE;
    wire fwd = !rst && !ft601_txe_n && (data_queue_count != 0) && (state == S_TX_ACTIVE);
    assign tx_ready = !rst && ((data_queue_count == 3'd2) || (data_queue_count == 3'd3));
    wire push = tx_valid && tx_ready;

    assign tx_word_written = fwd;
    always @(posedge clk) begin
        rx_valid    <= !rst && !ft601_rxf_n && (state == S_RX_ACTIVE);
        rx_data[7:0]    <= ft601_data[31:24];
        rx_data[15:8]   <= ft601_data[23:16];
        rx_data[23:16]  <= ft601_data[15:8];
        rx_data[31:24]  <= ft601_data[7:0];
    end
    assign ft601_be   = oe ? 4'b1111 : 4'bzzzz;
    assign ft601_data = oe ? {data_out[0][7:0], data_out[0][15:8],
                              data_out[0][23:16], data_out[0][31:24]}
                           : 32'hzzzzzzzz;
    always @(posedge clk) begin
        if (rst || (data_cooldown_count == 4'hf)) begin
            data_cooldown_count <= 4'h0;
            data_queue_count    <= 3'd5;
            data_out[0]         <= 32'h66665555;
            data_out[1]         <= 32'h66665555;
            data_out[2]         <= 32'h66665555;
            data_out[3]         <= 32'h66665555;
            data_out[4]         <= 32'h66665555;
        end else begin
            data_cooldown_count <= (data_queue_count == 0) ?
                                   (data_cooldown_count + 4'h1) : 4'h0;
            data_queue_count    <= data_queue_count
                                   + (push ? 3'b001 : 3'b000)
                                   - (fwd  ? 3'b001 : 3'b000);
            if (fwd) begin
                if (data_queue_count > 1) data_out[0] <= data_out[1];
                if (data_queue_count > 2) data_out[1] <= data_out[2];
                if (data_queue_count > 3) data_out[2] <= data_out[3];
                if (data_queue_count > 4) data_out[3] <= data_out[4];
            end
            if (push) begin
                data_out[data_queue_count - (fwd ? 3'b001 : 3'b000)] <= tx_data;
            end
        end
    end
    always @(posedge clk) begin
        oe         <= rst || ft601_rxf_n ||
                      ((state != S_RX_ACTIVE)    &&
                       (state != S_RX_WAIT3)     &&
                       (state != S_RX_WAIT2)     &&
                       (state != S_RX_COOLDOWN1) &&
                       (state != S_RX_COOLDOWN2));
        ft601_oe_n <= rst || ft601_rxf_n ||
                      ((state != S_RX_ACTIVE) &&
                       (state != S_RX_WAIT3)  &&
                       (state != S_RX_WAIT2));
        ft601_rd_n <= rst || ft601_rxf_n ||
                      ((state != S_RX_ACTIVE) &&
                       (state != S_RX_WAIT3));
        ft601_wr_n <= !(!rst && !ft601_txe_n &&
                        ((state == S_TX_WAIT2) ||
                         ((state == S_TX_ACTIVE) &&
                          (push || (data_queue_count > 1)))));
    end
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            case (state)
                S_IDLE:
                    if (!ft601_rxf_n)
                        state <= S_RX_WAIT1;
                    else if (!ft601_txe_n && (data_queue_count > 0))
                        state <= S_TX_WAIT1;

                S_RX_WAIT1:
                    state <= ft601_rxf_n ? S_RX_COOLDOWN1 : S_RX_WAIT2;
                S_RX_WAIT2:
                    state <= ft601_rxf_n ? S_RX_COOLDOWN1 : S_RX_WAIT3;
                S_RX_WAIT3:
                    state <= ft601_rxf_n ? S_RX_COOLDOWN1 : S_RX_ACTIVE;
                S_RX_ACTIVE:
                    state <= ft601_rxf_n ? S_RX_COOLDOWN1 : S_RX_ACTIVE;
                S_RX_COOLDOWN1:
                    state <= S_RX_COOLDOWN2;
                S_RX_COOLDOWN2:
                    state <= S_IDLE;

                S_TX_WAIT1:
                    state <= ft601_txe_n ? S_TX_COOLDOWN1 : S_TX_WAIT2;
                S_TX_WAIT2:
                    state <= ft601_txe_n ? S_TX_COOLDOWN1 : S_TX_ACTIVE;
                S_TX_ACTIVE:
                    state <= (ft601_txe_n ||
                              (!push && (data_queue_count <= 1)))
                             ? S_TX_COOLDOWN1 : S_TX_ACTIVE;
                S_TX_COOLDOWN1:
                    state <= S_TX_COOLDOWN2;
                S_TX_COOLDOWN2:
                    state <= S_IDLE;

                default:
                    state <= S_IDLE;
            endcase
        end
    end

endmodule
