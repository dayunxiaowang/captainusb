`timescale 1ns / 1ps

module captainusb_ft601_loopback #(
    parameter int FIFO_ADDR_WIDTH = 15,
    parameter int TX_STAGE_ADDR_WIDTH = 8
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        pcie_clk,
    input  wire        pcie_rst,
    input  wire        pcie_data_reset,
    inout  wire [31:0] ft601_data,
    output wire [3:0]  ft601_be,
    input  wire        ft601_rxf_n,
    input  wire        ft601_txe_n,
    output wire        ft601_wr_n,
    output wire        ft601_siwu_n,
    output wire        ft601_rd_n,
    output wire        ft601_oe_n,
    output reg  [31:0] rx_word_count             = 32'h0,
    output reg  [31:0] tx_word_count             = 32'h0,
    output reg  [31:0] drop_word_count           = 32'h0,
    output wire [31:0] rx_fifo_status,
    output wire [31:0] rx_fifo_rd_count,
    output wire [31:0] rx_fifo_wr_count,
    output reg  [31:0] rx_fifo_wr_accept_count   = 32'h0,
    output reg  [31:0] rx_fifo_rd_accept_count   = 32'h0,
    output reg  [31:0] ft601_fifo_rst_count      = 32'h0,
    output reg  [31:0] pcie_fifo_rst_count       = 32'h0,
    output wire [31:0] rx_dma_data,
    output wire        rx_dma_valid,
    input  wire        rx_dma_ready,
    input  wire        rx_dma_capture_enable,
    input  wire [31:0] tx_dma_data,
    input  wire        tx_dma_valid,
    output wire        tx_dma_ready,

    output reg         activity_toggle = 1'b0
);
    wire [31:0] phy_rx_data;
    wire        phy_rx_valid;
    wire [31:0] phy_tx_data;
    wire        phy_tx_valid;
    wire        phy_tx_ready;
    wire        phy_tx_word_written;
    (* ASYNC_REG = "TRUE" *) reg [2:0] pcie_data_reset_sync = 3'b000;
    wire ft601_fifo_rst = rst || pcie_data_reset_sync[2];
    wire pcie_fifo_rst  = pcie_rst || pcie_data_reset;

    reg [2:0] rx_dma_capture_sync = 3'b000;
    wire      rx_dma_capture_active = rx_dma_capture_sync[2];
    wire        dma_fifo_wr_ready;
    wire        rx_fifo_full;
    wire        rx_fifo_empty;
    wire [FIFO_ADDR_WIDTH:0] rx_fifo_rd_data_count;
    wire [FIFO_ADDR_WIDTH:0] rx_fifo_wr_data_count;

    wire [31:0] dma_tx_ft_data;
    wire        dma_tx_ft_valid;
    wire        tx_stage_wr_ready;
    wire [31:0] tx_stage_data;
    wire        tx_stage_valid;

    wire rx_fifo_wr_accept = phy_rx_valid && rx_dma_capture_active && dma_fifo_wr_ready;
    wire rx_fifo_rd_accept = rx_dma_valid && rx_dma_ready;
    wire rx_word_dropped   = phy_rx_valid &&
                             (!rx_dma_capture_active || !dma_fifo_wr_ready);
    wire word_activity     = phy_rx_valid || phy_tx_word_written;
    assign rx_fifo_status = {22'h000000,
                             phy_rx_valid,
                             pcie_fifo_rst,
                             ft601_fifo_rst,
                             rx_fifo_full,
                             rx_fifo_empty,
                             dma_fifo_wr_ready,
                             rx_dma_capture_active,
                             rx_dma_capture_enable,
                             rx_dma_ready,
                             rx_dma_valid};
    assign rx_fifo_rd_count = {{(31 - FIFO_ADDR_WIDTH){1'b0}}, rx_fifo_rd_data_count};
    assign rx_fifo_wr_count = {{(31 - FIFO_ADDR_WIDTH){1'b0}}, rx_fifo_wr_data_count};
    localparam [31:0] PING_MAGIC_SWAPPED = 32'h42535543;
    localparam [12:0] PING_SLOT_DW = 13'd1280;

    localparam [2:0]
        PH_IDLE       = 3'd0,
        PH_CHECK_CMD  = 3'd1,
        PH_CAPTURE_SEQ = 3'd2,
        PH_DRAIN_RX   = 3'd3,
        PH_RESPOND    = 3'd4;

    reg [2:0]  ph_state   = PH_IDLE;
    reg [12:0] ph_rx_cnt  = 13'd0;
    reg [12:0] ph_tx_cnt  = 13'd0;
    reg [31:0] ph_seq_dw  = 32'h0;
    reg        ph_is_ping = 1'b0;
    wire       ph_active  = (ph_state == PH_RESPOND);

    always @(posedge clk) begin
        if (rst || ft601_fifo_rst) begin
            ph_state   <= PH_IDLE;
            ph_rx_cnt  <= 13'd0;
            ph_tx_cnt  <= 13'd0;
            ph_is_ping <= 1'b0;
        end else begin
            case (ph_state)
                PH_IDLE: begin
                    if (!rx_dma_capture_active && phy_rx_valid) begin
                        if (phy_rx_data == PING_MAGIC_SWAPPED) begin
                            ph_rx_cnt <= 13'd1;
                            ph_state  <= PH_CHECK_CMD;
                        end
                    end
                end

                PH_CHECK_CMD: begin
                    if (phy_rx_valid) begin
                        ph_rx_cnt <= ph_rx_cnt + 13'd1;
                        if (phy_rx_data[31:24] == 8'h01 &&
                            phy_rx_data[23:16] == 8'h00) begin
                            ph_is_ping <= 1'b1;
                            ph_state   <= PH_CAPTURE_SEQ;
                        end else begin
                            ph_is_ping <= 1'b0;
                            ph_state   <= PH_DRAIN_RX;
                        end
                    end
                end

                PH_CAPTURE_SEQ: begin
                    if (phy_rx_valid) begin
                        ph_seq_dw <= phy_rx_data;
                        ph_rx_cnt <= ph_rx_cnt + 13'd1;
                        ph_state  <= PH_DRAIN_RX;
                    end
                end

                PH_DRAIN_RX: begin
                    if (phy_rx_valid)
                        ph_rx_cnt <= ph_rx_cnt + 13'd1;
                    if (ph_rx_cnt >= PING_SLOT_DW) begin
                        if (ph_is_ping) begin
                            ph_tx_cnt <= 13'd0;
                            ph_state  <= PH_RESPOND;
                        end else begin
                            ph_state  <= PH_IDLE;
                        end
                    end
                end

                PH_RESPOND: begin
                    if (phy_tx_ready) begin
                        ph_tx_cnt <= ph_tx_cnt + 13'd1;
                        if (ph_tx_cnt + 13'd1 >= PING_SLOT_DW)
                            ph_state <= PH_IDLE;
                    end
                end

                default: ph_state <= PH_IDLE;
            endcase
        end
    end

    reg [31:0] ph_tx_data_r;
    always @(*) begin
        case (ph_tx_cnt)
            13'd0:   ph_tx_data_r = PING_MAGIC_SWAPPED;
            13'd1:   ph_tx_data_r = 32'h01000000;
            13'd2:   ph_tx_data_r = ph_seq_dw;
            default: ph_tx_data_r = 32'h00000000;
        endcase
    end
    assign phy_tx_data  = ph_active ? ph_tx_data_r : tx_stage_data;
    assign phy_tx_valid = ph_active ? 1'b1         : tx_stage_valid;

    captainusb_ft601_phy i_ft601_phy (
        .clk              (clk),
        .rst              (ft601_fifo_rst),
        .ft601_data       (ft601_data),
        .ft601_be         (ft601_be),
        .ft601_rxf_n      (ft601_rxf_n),
        .ft601_txe_n      (ft601_txe_n),
        .ft601_wr_n       (ft601_wr_n),
        .ft601_siwu_n     (ft601_siwu_n),
        .ft601_rd_n       (ft601_rd_n),
        .ft601_oe_n       (ft601_oe_n),
        .rx_data          (phy_rx_data),
        .rx_valid         (phy_rx_valid),
        .tx_data          (phy_tx_data),
        .tx_valid         (phy_tx_valid),
        .tx_ready         (phy_tx_ready),
        .tx_word_written  (phy_tx_word_written)
    );
    captainusb_async_fifo #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) i_rx_dma_fifo (
        .wr_clk    (clk),
        .wr_rst    (ft601_fifo_rst),
        .wr_data   (phy_rx_data),
        .wr_valid  (phy_rx_valid && rx_dma_capture_active),
        .wr_ready  (dma_fifo_wr_ready),
        .rd_clk    (pcie_clk),
        .rd_rst    (pcie_fifo_rst),
        .rd_data   (rx_dma_data),
        .rd_valid  (rx_dma_valid),
        .rd_ready  (rx_dma_ready),
        .full      (rx_fifo_full),
        .empty     (rx_fifo_empty),
        .rd_data_count (rx_fifo_rd_data_count),
        .wr_data_count (rx_fifo_wr_data_count)
    );
    captainusb_async_fifo #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) i_tx_dma_fifo (
        .wr_clk    (pcie_clk),
        .wr_rst    (pcie_fifo_rst),
        .wr_data   (tx_dma_data),
        .wr_valid  (tx_dma_valid),
        .wr_ready  (tx_dma_ready),
        .rd_clk    (clk),
        .rd_rst    (ft601_fifo_rst),
        .rd_data   (dma_tx_ft_data),
        .rd_valid  (dma_tx_ft_valid),
        .rd_ready  (tx_stage_wr_ready),
        .full      (),
        .empty     (),
        .rd_data_count (),
        .wr_data_count ()
    );
    captainusb_sync_fifo #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (TX_STAGE_ADDR_WIDTH)
    ) i_tx_stage_fifo (
        .clk      (clk),
        .rst      (ft601_fifo_rst),
        .wr_data  (dma_tx_ft_data),
        .wr_valid (dma_tx_ft_valid),
        .wr_ready (tx_stage_wr_ready),
        .rd_data  (tx_stage_data),
        .rd_valid (tx_stage_valid),
        .rd_ready (!ph_active && phy_tx_ready),
        .full     (),
        .empty    ()
    );
    reg ft601_fifo_rst_q = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            rx_word_count            <= 32'h0;
            tx_word_count            <= 32'h0;
            drop_word_count          <= 32'h0;
            activity_toggle          <= 1'b0;
            pcie_data_reset_sync     <= 3'b000;
            rx_dma_capture_sync      <= 3'b000;
            rx_fifo_wr_accept_count  <= 32'h0;
            ft601_fifo_rst_count     <= 32'h0;
            ft601_fifo_rst_q         <= 1'b0;
        end else begin
            pcie_data_reset_sync <= {pcie_data_reset_sync[1:0], pcie_data_reset};
            ft601_fifo_rst_q     <= ft601_fifo_rst;

            if (ft601_fifo_rst && !ft601_fifo_rst_q)
                ft601_fifo_rst_count <= ft601_fifo_rst_count + 1'b1;

            if (ft601_fifo_rst) begin
                rx_dma_capture_sync <= 3'b000;
            end else begin
                rx_dma_capture_sync <= {rx_dma_capture_sync[1:0], rx_dma_capture_enable};

                if (word_activity)
                    activity_toggle <= !activity_toggle;

                if (phy_rx_valid) begin
                    rx_word_count <= rx_word_count + 1'b1;
                    if (rx_word_dropped)
                        drop_word_count <= drop_word_count + 1'b1;
                end

                if (rx_fifo_wr_accept)
                    rx_fifo_wr_accept_count <= rx_fifo_wr_accept_count + 1'b1;

                if (phy_tx_word_written)
                    tx_word_count <= tx_word_count + 1'b1;
            end
        end
    end
    reg pcie_data_reset_q = 1'b0;

    always @(posedge pcie_clk) begin
        if (pcie_rst) begin
            rx_fifo_rd_accept_count <= 32'h0;
            pcie_fifo_rst_count     <= 32'h0;
            pcie_data_reset_q       <= 1'b0;
        end else begin
            pcie_data_reset_q <= pcie_data_reset;

            if (pcie_data_reset && !pcie_data_reset_q)
                pcie_fifo_rst_count <= pcie_fifo_rst_count + 1'b1;

            if (rx_fifo_rd_accept)
                rx_fifo_rd_accept_count <= rx_fifo_rd_accept_count + 1'b1;
        end
    end

endmodule
