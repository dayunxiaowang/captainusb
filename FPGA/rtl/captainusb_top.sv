`timescale 1ns / 1ps

module captainusb_top (
    input  wire        clk,
    input  wire        ft601_clk,

    output wire        user_ld1_n,
    output wire        user_ld2_n,
    input  wire        user_sw1_n,
    input  wire        user_sw2_n,

    output wire [0:0]  pcie_tx_p,
    output wire [0:0]  pcie_tx_n,
    input  wire [0:0]  pcie_rx_p,
    input  wire [0:0]  pcie_rx_n,
    input  wire        pcie_clk_p,
    input  wire        pcie_clk_n,
    input  wire        pcie_present,
    input  wire        pcie_perst_n,
    output wire        pcie_wake_n,

    output wire        ft601_rst_n,
    inout  wire [31:0] ft601_data,
    output wire [3:0]  ft601_be,
    input  wire        ft601_rxf_n,
    input  wire        ft601_txe_n,
    output wire        ft601_wr_n,
    output wire        ft601_siwu_n,
    output wire        ft601_rd_n,
    output wire        ft601_oe_n
);
    reg [7:0] power_on_count = 8'h00;

    always @(posedge clk) begin
        if (!user_sw2_n) begin
            power_on_count <= 8'h00;
        end else if (power_on_count != 8'hff) begin
            power_on_count <= power_on_count + 1'b1;
        end
    end

    wire sys_rst = !user_sw2_n || (power_on_count != 8'hff);

    wire ft601_guard_rst = sys_rst;

    assign ft601_rst_n = !sys_rst;
    assign pcie_wake_n = 1'b1;

    wire [31:0] ft601_rx_words;
    wire [31:0] ft601_tx_words;
    wire [31:0] ft601_drop_words;
    wire [31:0] ft601_rx_fifo_status;
    wire [31:0] ft601_rx_fifo_rd_count;
    wire [31:0] ft601_rx_fifo_wr_count;
    wire [31:0] ft601_rx_fifo_wr_accept_count;
    wire [31:0] ft601_rx_fifo_rd_accept_count;
    wire [31:0] ft601_fifo_rst_count;
    wire [31:0] pcie_fifo_rst_count;
    wire        ft601_activity_toggle;
    wire [31:0] ft601_rx_dma_data;
    wire        ft601_rx_dma_valid;
    wire        ft601_rx_dma_ready;
    wire        ft601_rx_dma_capture_enable;
    wire        ft601_data_path_reset;
    wire [31:0] ft601_tx_dma_data;
    wire        ft601_tx_dma_valid;
    wire        ft601_tx_dma_ready;
    wire        pcie_user_clk;
    wire        pcie_user_reset;
    wire        pcie_local_reset;
    captainusb_ft601_loopback #(
        .FIFO_ADDR_WIDTH      (15),
        .TX_STAGE_ADDR_WIDTH  (8)
    ) i_ft601_loopback (
        .clk             (ft601_clk),
        .rst             (ft601_guard_rst),
        .pcie_clk        (pcie_user_clk),
        .pcie_rst        (pcie_user_reset),
        .pcie_data_reset (ft601_data_path_reset),
        .ft601_data      (ft601_data),
        .ft601_be        (ft601_be),
        .ft601_rxf_n     (ft601_rxf_n),
        .ft601_txe_n     (ft601_txe_n),
        .ft601_wr_n      (ft601_wr_n),
        .ft601_siwu_n    (ft601_siwu_n),
        .ft601_rd_n      (ft601_rd_n),
        .ft601_oe_n      (ft601_oe_n),
        .rx_word_count   (ft601_rx_words),
        .tx_word_count   (ft601_tx_words),
        .drop_word_count (ft601_drop_words),
        .rx_fifo_status  (ft601_rx_fifo_status),
        .rx_fifo_rd_count(ft601_rx_fifo_rd_count),
        .rx_fifo_wr_count(ft601_rx_fifo_wr_count),
        .rx_fifo_wr_accept_count(ft601_rx_fifo_wr_accept_count),
        .rx_fifo_rd_accept_count(ft601_rx_fifo_rd_accept_count),
        .ft601_fifo_rst_count(ft601_fifo_rst_count),
        .pcie_fifo_rst_count(pcie_fifo_rst_count),
        .rx_dma_data     (ft601_rx_dma_data),
        .rx_dma_valid    (ft601_rx_dma_valid),
        .rx_dma_ready    (ft601_rx_dma_ready),
        .rx_dma_capture_enable(ft601_rx_dma_capture_enable),
        .tx_dma_data     (ft601_tx_dma_data),
        .tx_dma_valid    (ft601_tx_dma_valid),
        .tx_dma_ready    (ft601_tx_dma_ready),
        .activity_toggle (ft601_activity_toggle)
    );

    wire pcie_link_up;
    wire [63:0] pcie_rx_tdata;
    wire [7:0]  pcie_rx_tkeep;
    wire        pcie_rx_tlast;
    wire        pcie_rx_tvalid;
    wire        pcie_rx_tready;
    wire [21:0] pcie_rx_tuser;
    wire [63:0] pcie_tx_tdata;
    wire [7:0]  pcie_tx_tkeep;
    wire        pcie_tx_tlast;
    wire        pcie_tx_tvalid;
    wire        pcie_tx_tready;
    wire [3:0]  pcie_tx_tuser;
    wire [15:0] cfg_completer_id;
    wire        cfg_interrupt;
    wire        cfg_interrupt_assert;
    wire [7:0]  cfg_interrupt_di;
    wire [4:0]  cfg_pciecap_interrupt_msgnum;
    wire        cfg_interrupt_stat;
    wire        cfg_interrupt_rdy;
    wire [7:0]  cfg_interrupt_do;
    wire [2:0]  cfg_interrupt_mmenable;
    wire        cfg_interrupt_msienable;
    wire        cfg_interrupt_msixenable;
    wire        cfg_interrupt_msixfm;
    wire        pcie_data_activity_toggle;
    (* ASYNC_REG = "TRUE" *) reg [1:0]  transfer_activity_active_pcie_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ft601_rx_words_pcie_sync_1 = 32'h00000000;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ft601_rx_words_pcie_sync_2 = 32'h00000000;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ft601_tx_words_pcie_sync_1 = 32'h00000000;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ft601_tx_words_pcie_sync_2 = 32'h00000000;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ft601_drop_words_pcie_sync_1 = 32'h00000000;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ft601_drop_words_pcie_sync_2 = 32'h00000000;

    captainusb_pcie_minimal_a7 i_pcie_minimal (
        .clk_sys         (clk),
        .rst             (sys_rst),
        .pcie_tx_p       (pcie_tx_p),
        .pcie_tx_n       (pcie_tx_n),
        .pcie_rx_p       (pcie_rx_p),
        .pcie_rx_n       (pcie_rx_n),
        .pcie_clk_p      (pcie_clk_p),
        .pcie_clk_n      (pcie_clk_n),
        .pcie_perst_n    (pcie_perst_n),
        .pcie_user_clk   (pcie_user_clk),
        .pcie_user_reset (pcie_user_reset),
        .pcie_link_up    (pcie_link_up),
        .m_axis_rx_tdata (pcie_rx_tdata),
        .m_axis_rx_tkeep (pcie_rx_tkeep),
        .m_axis_rx_tlast (pcie_rx_tlast),
        .m_axis_rx_tvalid(pcie_rx_tvalid),
        .m_axis_rx_tready(pcie_rx_tready),
        .m_axis_rx_tuser (pcie_rx_tuser),
        .s_axis_tx_tdata (pcie_tx_tdata),
        .s_axis_tx_tkeep (pcie_tx_tkeep),
        .s_axis_tx_tlast (pcie_tx_tlast),
        .s_axis_tx_tvalid(pcie_tx_tvalid),
        .s_axis_tx_tready(pcie_tx_tready),
        .s_axis_tx_tuser (pcie_tx_tuser),
        .cfg_completer_id(cfg_completer_id),
        .cfg_interrupt   (cfg_interrupt),
        .cfg_interrupt_assert(cfg_interrupt_assert),
        .cfg_interrupt_di(cfg_interrupt_di),
        .cfg_pciecap_interrupt_msgnum(cfg_pciecap_interrupt_msgnum),
        .cfg_interrupt_stat(cfg_interrupt_stat),
        .cfg_interrupt_rdy(cfg_interrupt_rdy),
        .cfg_interrupt_do(cfg_interrupt_do),
        .cfg_interrupt_mmenable(cfg_interrupt_mmenable),
        .cfg_interrupt_msienable(cfg_interrupt_msienable),
        .cfg_interrupt_msixenable(cfg_interrupt_msixenable),
        .cfg_interrupt_msixfm(cfg_interrupt_msixfm)
    );

    captainusb_reset_sync i_pcie_reset_sync (
        .clk  (pcie_user_clk),
        .arst (sys_rst),
        .srst (pcie_local_reset)
    );

    wire pcie_app_guard_rst = pcie_user_reset || pcie_local_reset;
    wire transfer_activity_active;

    always @(posedge pcie_user_clk) begin
        if (pcie_user_reset || pcie_local_reset) begin
            transfer_activity_active_pcie_sync <= 2'b00;
            ft601_rx_words_pcie_sync_1 <= 32'h00000000;
            ft601_rx_words_pcie_sync_2 <= 32'h00000000;
            ft601_tx_words_pcie_sync_1 <= 32'h00000000;
            ft601_tx_words_pcie_sync_2 <= 32'h00000000;
            ft601_drop_words_pcie_sync_1 <= 32'h00000000;
            ft601_drop_words_pcie_sync_2 <= 32'h00000000;
        end else begin
            transfer_activity_active_pcie_sync <= {transfer_activity_active_pcie_sync[0], transfer_activity_active};
            ft601_rx_words_pcie_sync_1 <= ft601_rx_words;
            ft601_rx_words_pcie_sync_2 <= ft601_rx_words_pcie_sync_1;
            ft601_tx_words_pcie_sync_1 <= ft601_tx_words;
            ft601_tx_words_pcie_sync_2 <= ft601_tx_words_pcie_sync_1;
            ft601_drop_words_pcie_sync_1 <= ft601_drop_words;
            ft601_drop_words_pcie_sync_2 <= ft601_drop_words_pcie_sync_1;
        end
    end

    captainusb_pcie_app i_pcie_app (
        .clk                   (pcie_user_clk),
        .rst                   (pcie_app_guard_rst),
        .pcie_link_up          (pcie_link_up),
        .cfg_completer_id      (cfg_completer_id),
        .ft601_active          (transfer_activity_active_pcie_sync[1]),
        .ft601_rx_words        (ft601_rx_words_pcie_sync_2),
        .ft601_tx_words        (ft601_tx_words_pcie_sync_2),
        .ft601_drop_words      (ft601_drop_words_pcie_sync_2),
        .ft601_rx_dma_data     (ft601_rx_dma_data),
        .ft601_rx_dma_valid    (ft601_rx_dma_valid),
        .ft601_rx_dma_ready    (ft601_rx_dma_ready),
        .ft601_rx_dma_capture_enable(ft601_rx_dma_capture_enable),
        .ft601_tx_dma_data     (ft601_tx_dma_data),
        .ft601_tx_dma_valid    (ft601_tx_dma_valid),
        .ft601_tx_dma_ready    (ft601_tx_dma_ready),
        .ft601_data_path_reset (ft601_data_path_reset),
        .m_axis_rx_tdata       (pcie_rx_tdata),
        .m_axis_rx_tkeep       (pcie_rx_tkeep),
        .m_axis_rx_tlast       (pcie_rx_tlast),
        .m_axis_rx_tvalid      (pcie_rx_tvalid),
        .m_axis_rx_tready      (pcie_rx_tready),
        .m_axis_rx_tuser       (pcie_rx_tuser),
        .s_axis_tx_tdata       (pcie_tx_tdata),
        .s_axis_tx_tkeep       (pcie_tx_tkeep),
        .s_axis_tx_tlast       (pcie_tx_tlast),
        .s_axis_tx_tvalid      (pcie_tx_tvalid),
        .s_axis_tx_tready      (pcie_tx_tready),
        .s_axis_tx_tuser       (pcie_tx_tuser),
        .cfg_interrupt         (cfg_interrupt),
        .cfg_interrupt_assert  (cfg_interrupt_assert),
        .cfg_interrupt_di      (cfg_interrupt_di),
        .cfg_pciecap_interrupt_msgnum(cfg_pciecap_interrupt_msgnum),
        .cfg_interrupt_stat    (cfg_interrupt_stat),
        .cfg_interrupt_rdy     (cfg_interrupt_rdy),
        .cfg_interrupt_mmenable(cfg_interrupt_mmenable),
        .cfg_interrupt_msienable(cfg_interrupt_msienable),
        .data_activity_toggle  (pcie_data_activity_toggle)
    );

    reg [25:0] led_counter = 26'h0000000;
    reg [23:0] led_activity_hold = 24'h000000;
    (* ASYNC_REG = "TRUE" *) reg [2:0] ft601_activity_sync = 3'b000;
    (* ASYNC_REG = "TRUE" *) reg [2:0] pcie_activity_sync = 3'b000;

    wire ft601_activity_event = ft601_activity_sync[2] ^ ft601_activity_sync[1];
    wire pcie_activity_event = pcie_activity_sync[2] ^ pcie_activity_sync[1];
    wire transfer_activity_event = ft601_activity_event || pcie_activity_event;
    assign transfer_activity_active = (led_activity_hold != 24'h000000);
    wire link_ok = pcie_present && pcie_link_up;

    always @(posedge clk) begin
        if (sys_rst) begin
            led_counter <= 26'h0000000;
            led_activity_hold <= 24'h000000;
            ft601_activity_sync <= 3'b000;
            pcie_activity_sync <= 3'b000;
        end else begin
            led_counter <= led_counter + 1'b1;
            ft601_activity_sync <= {ft601_activity_sync[1:0], ft601_activity_toggle};
            pcie_activity_sync <= {pcie_activity_sync[1:0], pcie_data_activity_toggle};

            if (transfer_activity_event) begin
                led_activity_hold <= 24'hffffff;
            end else if (transfer_activity_active) begin
                led_activity_hold <= led_activity_hold - 1'b1;
            end
        end
    end

    assign user_ld1_n = ~link_ok;
    assign user_ld2_n = link_ok ? (transfer_activity_active ? led_counter[22] : 1'b0) : 1'b1;

    wire unused_pcie_cfg = ^{cfg_interrupt_do, cfg_interrupt_msixenable, cfg_interrupt_msixfm};
    wire unused_ft601_counts = ^{ft601_rx_words, ft601_tx_words, ft601_drop_words, user_sw1_n,
        ft601_rx_fifo_status, ft601_rx_fifo_rd_count, ft601_rx_fifo_wr_count,
        ft601_rx_fifo_wr_accept_count, ft601_rx_fifo_rd_accept_count,
        ft601_fifo_rst_count, pcie_fifo_rst_count};
endmodule
