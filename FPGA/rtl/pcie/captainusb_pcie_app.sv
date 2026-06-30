`timescale 1ns / 1ps

module captainusb_pcie_app (
    input  wire        clk,
    input  wire        rst,
    input  wire        pcie_link_up,
    input  wire [15:0] cfg_completer_id,
    input  wire        ft601_active,
    input  wire [31:0] ft601_rx_words,
    input  wire [31:0] ft601_tx_words,
    input  wire [31:0] ft601_drop_words,
    input  wire [31:0] ft601_rx_dma_data,
    input  wire        ft601_rx_dma_valid,
    output wire        ft601_rx_dma_ready,
    output wire        ft601_rx_dma_capture_enable,
    output wire [31:0] ft601_tx_dma_data,
    output wire        ft601_tx_dma_valid,
    input  wire        ft601_tx_dma_ready,

    output wire        ft601_data_path_reset,
    input  wire [63:0] m_axis_rx_tdata,
    input  wire [7:0]  m_axis_rx_tkeep,
    input  wire        m_axis_rx_tlast,
    input  wire        m_axis_rx_tvalid,
    output wire        m_axis_rx_tready,
    input  wire [21:0] m_axis_rx_tuser,
    output wire [63:0] s_axis_tx_tdata,
    output wire [7:0]  s_axis_tx_tkeep,
    output wire        s_axis_tx_tlast,
    output wire        s_axis_tx_tvalid,
    input  wire        s_axis_tx_tready,
    output wire [3:0]  s_axis_tx_tuser,
    output reg         cfg_interrupt = 1'b0,
    output reg         cfg_interrupt_assert = 1'b0,
    output wire [7:0]  cfg_interrupt_di,
    output wire [4:0]  cfg_pciecap_interrupt_msgnum,
    output wire        cfg_interrupt_stat,
    input  wire        cfg_interrupt_rdy,
    input  wire [2:0]  cfg_interrupt_mmenable,
    input  wire        cfg_interrupt_msienable,

    output reg         data_activity_toggle = 1'b0
);
    localparam logic [1:0] REQ_CPLD = 2'd0;
    wire        bar_rd_valid, bar_wr_valid;
    wire [15:0] bar_addr;
    wire [31:0] bar_wr_data;
    wire [3:0]  bar_be;
    wire [15:0] bar_req_id;
    wire [7:0]  bar_tag;
    wire [6:0]  bar_lower_addr;
    wire        cpl_valid;
    wire [7:0]  cpl_tag;
    wire [31:0] cpl_data;
    wire [31:0] unsupported_count;

    captainusb_tlp_rx64 i_tlp_rx (
        .clk(clk), .rst(rst),
        .rx_tdata(m_axis_rx_tdata), .rx_tkeep(m_axis_rx_tkeep),
        .rx_tlast(m_axis_rx_tlast), .rx_tvalid(m_axis_rx_tvalid),
        .rx_tready(m_axis_rx_tready), .rx_tuser(m_axis_rx_tuser),
        .bar_rd_valid(bar_rd_valid), .bar_wr_valid(bar_wr_valid),
        .bar_addr(bar_addr), .bar_wr_data(bar_wr_data), .bar_be(bar_be),
        .bar_req_id(bar_req_id), .bar_tag(bar_tag), .bar_lower_addr(bar_lower_addr),
        .cpl_valid(cpl_valid), .cpl_tag(cpl_tag), .cpl_data(cpl_data),
        .unsupported_count(unsupported_count)
    );
    wire        data_path_reset_req;
    wire        irq_enable_w;
    wire        irq_pending;
    wire [31:0] bar_rd_data;
    reg  [15:0] bar_rd_addr_q = 16'h0;

    wire        txq_enable;
    wire [63:0] txq_base_addr;
    wire [15:0] txq_prod_ptr, txq_cons_ptr;
    wire        txq_cons_update_valid;
    wire [15:0] txq_cons_update_value;

    wire        rxq_enable;
    wire [63:0] rxq_base_addr;
    wire [15:0] rxq_prod_ptr, rxq_cons_ptr;
    wire        rxq_prod_update_valid;
    wire [15:0] rxq_prod_update_value;

    wire [31:0] tx_dma_slot_count, tx_dma_mrd_count;
    wire [31:0] rx_dma_slot_count, rx_dma_mwr_count;
    wire [31:0] requester_tag_mismatch_count;

    captainusb_bar0_regs i_bar0_regs (
        .clk(clk), .rst(rst),
        .pcie_link_up(pcie_link_up),
        .unsupported_tlp_count(unsupported_count),
        .ft601_active(ft601_active),
        .ft601_rx_words(ft601_rx_words),
        .ft601_tx_words(ft601_tx_words),
        .ft601_drop_words(ft601_drop_words),
        .wr_valid(bar_wr_valid), .wr_addr(bar_addr),
        .wr_data(bar_wr_data), .wr_be(bar_be),
        .rd_addr(bar_rd_addr_q), .rd_data(bar_rd_data),
        .txq_enable(txq_enable), .txq_base_addr(txq_base_addr),
        .txq_prod_ptr(txq_prod_ptr), .txq_cons_ptr(txq_cons_ptr),
        .txq_cons_update_valid(txq_cons_update_valid),
        .txq_cons_update_value(txq_cons_update_value),
        .rxq_enable(rxq_enable), .rxq_base_addr(rxq_base_addr),
        .rxq_prod_ptr(rxq_prod_ptr), .rxq_cons_ptr(rxq_cons_ptr),
        .rxq_prod_update_valid(rxq_prod_update_valid),
        .rxq_prod_update_value(rxq_prod_update_value),
        .tx_dma_slot_count(tx_dma_slot_count),
        .tx_dma_mrd_count(tx_dma_mrd_count),
        .rx_dma_slot_count(rx_dma_slot_count),
        .rx_dma_mwr_count(rx_dma_mwr_count),
        .requester_tag_mismatch_count(requester_tag_mismatch_count),
        .data_path_reset_req(data_path_reset_req),
        .irq_enable(irq_enable_w),
        .irq_pending(irq_pending)
    );
    reg [4:0] data_path_reset_shift = 5'h00;
    wire      data_path_reset_active = |data_path_reset_shift;
    wire      data_path_rst = rst || data_path_reset_active;
    assign    ft601_data_path_reset = data_path_reset_active;

    always @(posedge clk) begin
        if (rst) data_path_reset_shift <= 5'h00;
        else if (data_path_reset_req) data_path_reset_shift <= 5'h1f;
        else data_path_reset_shift <= {1'b0, data_path_reset_shift[4:1]};
    end
    wire        tx_dma_rd_req_valid, tx_dma_rd_req_ready;
    wire [63:0] tx_dma_rd_req_addr;
    wire [9:0]  tx_dma_rd_req_length_dw;
    wire [12:0] tx_dma_rd_req_bram_offset;
    wire        tx_dma_rd_cpl_valid;
    wire [31:0] tx_dma_rd_cpl_data;
    wire [12:0] tx_dma_rd_cpl_bram_offset;
    wire        tx_dma_rd_cpl_tag_done;
    wire        tx_dma_rd_tag_available;
    wire        tx_dma_rd_all_tags_idle;
    wire        tx_dma_busy;

    captainusb_ring_tx_dma i_ring_tx_dma (
        .clk(clk), .rst(data_path_rst),
        .ring_enable(txq_enable),
        .ring_base_addr(txq_base_addr),
        .ring_prod_ptr(txq_prod_ptr),
        .ring_cons_ptr(txq_cons_ptr),
        .cons_update_valid(txq_cons_update_valid),
        .cons_update_value(txq_cons_update_value),
        .rd_req_valid(tx_dma_rd_req_valid),
        .rd_req_ready(tx_dma_rd_req_ready),
        .rd_req_addr(tx_dma_rd_req_addr),
        .rd_req_length_dw(tx_dma_rd_req_length_dw),
        .rd_req_bram_offset(tx_dma_rd_req_bram_offset),
        .rd_cpl_valid(tx_dma_rd_cpl_valid),
        .rd_cpl_data(tx_dma_rd_cpl_data),
        .rd_cpl_bram_offset(tx_dma_rd_cpl_bram_offset),
        .rd_cpl_tag_done(tx_dma_rd_cpl_tag_done),
        .rd_tag_available(tx_dma_rd_tag_available),
        .rd_all_tags_idle(tx_dma_rd_all_tags_idle),
        .stream_data(ft601_tx_dma_data),
        .stream_valid(ft601_tx_dma_valid),
        .stream_ready(ft601_tx_dma_ready),
        .busy(tx_dma_busy),
        .debug_slot_count(tx_dma_slot_count),
        .debug_mrd_count(tx_dma_mrd_count)
    );
    wire        rx_dma_wr_req_valid, rx_dma_wr_req_ready;
    wire [63:0] rx_dma_wr_req_addr;
    wire [31:0] rx_dma_wr_req_data;
    wire [9:0]  rx_dma_wr_req_length_dw;
    wire [3:0]  rx_dma_wr_req_first_be, rx_dma_wr_req_last_be;
    wire [31:0] rx_dma_wr_data;
    wire        rx_dma_wr_data_valid, rx_dma_wr_data_ready;
    wire        rx_dma_busy;

    captainusb_ring_rx_dma i_ring_rx_dma (
        .clk(clk), .rst(data_path_rst),
        .ring_enable(rxq_enable),
        .ring_base_addr(rxq_base_addr),
        .ring_prod_ptr(rxq_prod_ptr),
        .ring_cons_ptr(rxq_cons_ptr),
        .prod_update_valid(rxq_prod_update_valid),
        .prod_update_value(rxq_prod_update_value),
        .wr_req_valid(rx_dma_wr_req_valid),
        .wr_req_ready(rx_dma_wr_req_ready),
        .wr_req_addr(rx_dma_wr_req_addr),
        .wr_req_data(rx_dma_wr_req_data),
        .wr_req_length_dw(rx_dma_wr_req_length_dw),
        .wr_req_first_be(rx_dma_wr_req_first_be),
        .wr_req_last_be(rx_dma_wr_req_last_be),
        .wr_data(rx_dma_wr_data),
        .wr_data_valid(rx_dma_wr_data_valid),
        .wr_data_ready(rx_dma_wr_data_ready),
        .stream_data(ft601_rx_dma_data),
        .stream_valid(ft601_rx_dma_valid),
        .stream_ready(ft601_rx_dma_ready),
        .busy(rx_dma_busy),
        .debug_slot_count(rx_dma_slot_count),
        .debug_mwr_count(rx_dma_mwr_count)
    );

    assign ft601_rx_dma_capture_enable = rxq_enable;

    wire        requester_tx_valid, requester_tx_ready;
    wire [1:0]  requester_tx_type;
    wire [63:0] requester_tx_addr;
    wire [31:0] requester_tx_data;
    wire [7:0]  requester_tx_tag;
    wire [9:0]  requester_tx_length_dw;
    wire [3:0]  requester_tx_first_be, requester_tx_last_be;
    wire [31:0] requester_tx_data_word;
    wire        requester_tx_data_valid, requester_tx_data_ready;
    wire        requester_busy;
    captainusb_pcie_requester_7x #(
        .MAX_RD_TAGS(32)
    ) i_pcie_requester (
        .clk(clk), .rst(data_path_rst),
        .rd_req_valid(tx_dma_rd_req_valid),
        .rd_req_ready(tx_dma_rd_req_ready),
        .rd_req_addr(tx_dma_rd_req_addr),
        .rd_req_length_dw(tx_dma_rd_req_length_dw),
        .rd_req_bram_offset(tx_dma_rd_req_bram_offset),
        .rd_cpl_valid(tx_dma_rd_cpl_valid),
        .rd_cpl_data(tx_dma_rd_cpl_data),
        .rd_cpl_bram_offset(tx_dma_rd_cpl_bram_offset),
        .rd_cpl_tag_done(tx_dma_rd_cpl_tag_done),
        .rd_tag_available(tx_dma_rd_tag_available),
        .rd_all_tags_idle(tx_dma_rd_all_tags_idle),
        .wr_req_valid(rx_dma_wr_req_valid),
        .wr_req_ready(rx_dma_wr_req_ready),
        .wr_req_addr(rx_dma_wr_req_addr),
        .wr_req_data(rx_dma_wr_req_data),
        .wr_req_length_dw(rx_dma_wr_req_length_dw),
        .wr_req_first_be(rx_dma_wr_req_first_be),
        .wr_req_last_be(rx_dma_wr_req_last_be),
        .wr_data(rx_dma_wr_data),
        .wr_data_valid(rx_dma_wr_data_valid),
        .wr_data_ready(rx_dma_wr_data_ready),
        .tx_req_valid(requester_tx_valid),
        .tx_req_ready(requester_tx_ready),
        .tx_req_type(requester_tx_type),
        .tx_req_addr(requester_tx_addr),
        .tx_req_data(requester_tx_data),
        .tx_req_tag(requester_tx_tag),
        .tx_req_length_dw(requester_tx_length_dw),
        .tx_req_first_be(requester_tx_first_be),
        .tx_req_last_be(requester_tx_last_be),
        .tx_data_word(requester_tx_data_word),
        .tx_data_valid(requester_tx_data_valid),
        .tx_data_ready(requester_tx_data_ready),
        .cpl_valid(cpl_valid),
        .cpl_tag(cpl_tag),
        .cpl_data(cpl_data),
        .busy(requester_busy),
        .tag_mismatch_count(requester_tag_mismatch_count)
    );
    reg        bar_cpl_pending = 1'b0;
    reg [15:0] bar_cpl_req_id = 16'h0;
    reg [7:0]  bar_cpl_tag = 8'h0;
    reg [6:0]  bar_cpl_lower_addr = 7'h0;
    reg [31:0] bar_cpl_data = 32'h0;
    reg        bar_rd_stage_valid = 1'b0;
    reg [15:0] bar_rd_req_id_q = 16'h0;
    reg [7:0]  bar_rd_tag_q = 8'h0;
    reg [6:0]  bar_rd_lower_addr_q = 7'h0;

    wire       tx_req_valid = bar_cpl_pending || requester_tx_valid;
    wire       tx_req_ready;
    wire [1:0] tx_req_type = bar_cpl_pending ? REQ_CPLD : requester_tx_type;
    wire [15:0] tx_req_requester_id = bar_cpl_pending ? bar_cpl_req_id : cfg_completer_id;
    wire [7:0] tx_req_tag = bar_cpl_pending ? bar_cpl_tag : requester_tx_tag;
    wire [63:0] tx_req_addr = bar_cpl_pending ? 64'h0 : requester_tx_addr;
    wire [31:0] tx_req_data = bar_cpl_pending ? bar_cpl_data : requester_tx_data;
    wire [6:0]  tx_req_lower_addr = bar_cpl_pending ? bar_cpl_lower_addr : 7'h0;
    wire [9:0]  tx_req_length_dw = bar_cpl_pending ? 10'd1 : requester_tx_length_dw;
    wire [3:0]  tx_req_first_be = bar_cpl_pending ? 4'hf : requester_tx_first_be;
    wire [3:0]  tx_req_last_be = bar_cpl_pending ? 4'h0 : requester_tx_last_be;
    assign      requester_tx_ready = (!bar_cpl_pending) && tx_req_ready;

    captainusb_tlp_tx64 i_tlp_tx (
        .clk(clk), .rst(rst),
        .req_valid(tx_req_valid), .req_ready(tx_req_ready),
        .req_type(tx_req_type),
        .completer_id(cfg_completer_id),
        .requester_id(tx_req_requester_id),
        .tag(tx_req_tag),
        .addr(tx_req_addr),
        .data(tx_req_data),
        .first_be(tx_req_first_be),
        .last_be(tx_req_last_be),
        .lower_addr(tx_req_lower_addr),
        .length_dw(tx_req_length_dw),
        .data_word(requester_tx_data_word),
        .data_valid(requester_tx_data_valid),
        .data_ready(requester_tx_data_ready),
        .tx_tdata(s_axis_tx_tdata),
        .tx_tkeep(s_axis_tx_tkeep),
        .tx_tlast(s_axis_tx_tlast),
        .tx_tuser(s_axis_tx_tuser),
        .tx_tvalid(s_axis_tx_tvalid),
        .tx_tready(s_axis_tx_tready)
    );
    always @(posedge clk) begin
        if (rst) begin
            bar_cpl_pending <= 1'b0;
            bar_rd_stage_valid <= 1'b0;
            bar_rd_addr_q <= 16'h0;
        end else begin
            if (bar_rd_valid) begin
                bar_rd_stage_valid <= 1'b1;
                bar_rd_addr_q <= bar_addr;
                bar_rd_req_id_q <= bar_req_id;
                bar_rd_tag_q <= bar_tag;
                bar_rd_lower_addr_q <= bar_lower_addr;
            end else begin
                bar_rd_stage_valid <= 1'b0;
            end

            if (bar_rd_stage_valid) begin
                bar_cpl_pending <= 1'b1;
                bar_cpl_req_id <= bar_rd_req_id_q;
                bar_cpl_tag <= bar_rd_tag_q;
                bar_cpl_lower_addr <= bar_rd_lower_addr_q;
                bar_cpl_data <= bar_rd_data;
            end else if (bar_cpl_pending && tx_req_ready) begin
                bar_cpl_pending <= 1'b0;
            end
        end
    end
    reg irq_seen_pending = 1'b0;
    reg legacy_irq_asserted = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            cfg_interrupt <= 1'b0;
            cfg_interrupt_assert <= 1'b0;
            irq_seen_pending <= 1'b0;
            legacy_irq_asserted <= 1'b0;
            data_activity_toggle <= 1'b0;
        end else begin
            if (requester_tx_valid && requester_tx_ready)
                data_activity_toggle <= !data_activity_toggle;

            if (cfg_interrupt && cfg_interrupt_rdy) begin
                cfg_interrupt <= 1'b0;
                if (!cfg_interrupt_msienable)
                    legacy_irq_asserted <= cfg_interrupt_assert;
            end

            if (!irq_pending) irq_seen_pending <= 1'b0;
            if (cfg_interrupt_msienable) begin
                legacy_irq_asserted <= 1'b0;
                cfg_interrupt_assert <= 1'b0;
            end

            if (irq_enable_w && cfg_interrupt_msienable && irq_pending && !irq_seen_pending && !cfg_interrupt) begin
                cfg_interrupt <= 1'b1;
                irq_seen_pending <= 1'b1;
            end else if (irq_enable_w && !cfg_interrupt_msienable && !cfg_interrupt && irq_pending && !legacy_irq_asserted) begin
                cfg_interrupt <= 1'b1;
                cfg_interrupt_assert <= 1'b1;
            end else if (!cfg_interrupt_msienable && !cfg_interrupt && !irq_pending && legacy_irq_asserted) begin
                cfg_interrupt <= 1'b1;
                cfg_interrupt_assert <= 1'b0;
            end
        end
    end

    assign cfg_interrupt_di = 8'h00;
    assign cfg_pciecap_interrupt_msgnum = 5'h00;
    assign cfg_interrupt_stat = irq_pending;

    wire unused = ^{cfg_interrupt_mmenable, tx_dma_busy, rx_dma_busy, requester_busy};
endmodule
