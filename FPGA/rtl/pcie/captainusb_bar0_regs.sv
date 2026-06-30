`timescale 1ns / 1ps

module captainusb_bar0_regs (
    input  wire        clk,
    input  wire        rst,

    input  wire        pcie_link_up,
    input  wire [31:0] unsupported_tlp_count,
    input  wire        ft601_active,
    input  wire [31:0] ft601_rx_words,
    input  wire [31:0] ft601_tx_words,
    input  wire [31:0] ft601_drop_words,

    input  wire        wr_valid,
    input  wire [15:0] wr_addr,
    input  wire [31:0] wr_data,
    input  wire [3:0]  wr_be,

    input  wire [15:0] rd_addr,
    output reg  [31:0] rd_data,
    output wire        txq_enable,
    output wire [63:0] txq_base_addr,
    output wire [15:0] txq_prod_ptr,
    output wire [15:0] txq_cons_ptr,
    input  wire        txq_cons_update_valid,
    input  wire [15:0] txq_cons_update_value,
    output wire        rxq_enable,
    output wire [63:0] rxq_base_addr,
    output wire [15:0] rxq_prod_ptr,
    output wire [15:0] rxq_cons_ptr,
    input  wire        rxq_prod_update_valid,
    input  wire [15:0] rxq_prod_update_value,
    input  wire [31:0] tx_dma_slot_count,
    input  wire [31:0] tx_dma_mrd_count,
    input  wire [31:0] rx_dma_slot_count,
    input  wire [31:0] rx_dma_mwr_count,
    input  wire [31:0] requester_tag_mismatch_count,

    output reg         data_path_reset_req = 1'b0,
    output reg         irq_enable = 1'b0,
    output wire        irq_pending
);
    localparam logic [31:0] MAGIC   = 32'h43555342;
    localparam logic [31:0] VERSION = 32'h00020000;

    reg [31:0] irq_mask   = 32'h0;
    reg [31:0] irq_status = 32'h0;

    reg        txq_en = 1'b0;
    reg [15:0] txq_prod = 16'h0;
    reg [15:0] txq_cons = 16'h0;
    reg [31:0] txq_base_lo = 32'h0;
    reg [31:0] txq_base_hi = 32'h0;

    reg        rxq_en = 1'b0;
    reg [15:0] rxq_prod = 16'h0;
    reg [15:0] rxq_cons = 16'h0;
    reg [31:0] rxq_base_lo = 32'h0;
    reg [31:0] rxq_base_hi = 32'h0;

    assign txq_enable    = txq_en;
    assign txq_base_addr = {txq_base_hi, txq_base_lo};
    assign txq_prod_ptr  = txq_prod;
    assign txq_cons_ptr  = txq_cons;
    assign rxq_enable    = rxq_en;
    assign rxq_base_addr = {rxq_base_hi, rxq_base_lo};
    assign rxq_prod_ptr  = rxq_prod;
    assign rxq_cons_ptr  = rxq_cons;
    assign irq_pending   = irq_enable && ((irq_status & irq_mask) != 32'h0);

    function automatic [31:0] apply_be;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  byte_enable;
        begin
            apply_be[7:0]   = byte_enable[0] ? new_value[7:0]   : old_value[7:0];
            apply_be[15:8]  = byte_enable[1] ? new_value[15:8]  : old_value[15:8];
            apply_be[23:16] = byte_enable[2] ? new_value[23:16] : old_value[23:16];
            apply_be[31:24] = byte_enable[3] ? new_value[31:24] : old_value[31:24];
        end
    endfunction
    reg [31:0] irq_set_bits;
    reg [31:0] irq_clr_bits;

    always @(*) begin
        irq_set_bits = 32'h0;
        irq_clr_bits = 32'h0;
        if (txq_cons_update_valid) irq_set_bits = irq_set_bits | 32'h1;
        if (rxq_prod_update_valid) irq_set_bits = irq_set_bits | 32'h2;
        if (wr_valid && wr_addr[15:0] == 16'h0010)
            irq_clr_bits = wr_data;
    end

    always @(posedge clk) begin
        if (rst) begin
            data_path_reset_req <= 1'b0;
            irq_enable <= 1'b0;
            irq_mask <= 32'h0;
            irq_status <= 32'h0;
            txq_en <= 1'b0;
            txq_prod <= 16'h0;
            txq_cons <= 16'h0;
            txq_base_lo <= 32'h0;
            txq_base_hi <= 32'h0;
            rxq_en <= 1'b0;
            rxq_prod <= 16'h0;
            rxq_cons <= 16'h0;
            rxq_base_lo <= 32'h0;
            rxq_base_hi <= 32'h0;
        end else begin
            data_path_reset_req <= 1'b0;
            if (txq_cons_update_valid) txq_cons <= txq_cons_update_value;
            if (rxq_prod_update_valid) rxq_prod <= rxq_prod_update_value;
            irq_status <= (irq_status | irq_set_bits) & ~irq_clr_bits;

            if (wr_valid) begin
                case (wr_addr[15:0])
                    16'h000C: begin
                        irq_enable <= wr_data[8];
                        if (wr_data[1]) begin
                            data_path_reset_req <= 1'b1;
                            txq_prod <= 16'h0;
                            txq_cons <= 16'h0;
                            rxq_prod <= 16'h0;
                            rxq_cons <= 16'h0;
                        end
                    end
                    16'h0014: irq_mask <= apply_be(irq_mask, wr_data, wr_be);

                    16'h0100: txq_en <= wr_data[0];
                    16'h0104: txq_prod <= wr_data[15:0];
                    16'h0108: txq_base_lo <= apply_be(txq_base_lo, wr_data, wr_be);
                    16'h010C: txq_base_hi <= apply_be(txq_base_hi, wr_data, wr_be);

                    16'h0200: rxq_en <= wr_data[0];
                    16'h0204: rxq_cons <= wr_data[15:0];
                    16'h0208: rxq_base_lo <= apply_be(rxq_base_lo, wr_data, wr_be);
                    16'h020C: rxq_base_hi <= apply_be(rxq_base_hi, wr_data, wr_be);
                    default: begin end
                endcase
            end
        end
    end

    always @(*) begin
        case (rd_addr[15:0])
            16'h0000: rd_data = MAGIC;
            16'h0004: rd_data = VERSION;
            16'h0008: rd_data = {28'h0, ft601_active, irq_pending, 1'b0, pcie_link_up};
            16'h000C: rd_data = {23'h0, irq_enable, 8'h0};
            16'h0010: rd_data = irq_status;
            16'h0014: rd_data = irq_mask;
            16'h0018: rd_data = 32'd5120;
            16'h001C: rd_data = 32'd512;

            16'h0100: rd_data = {31'h0, txq_en};
            16'h0104: rd_data = {txq_cons, txq_prod};
            16'h0108: rd_data = txq_base_lo;
            16'h010C: rd_data = txq_base_hi;

            16'h0200: rd_data = {31'h0, rxq_en};
            16'h0204: rd_data = {rxq_cons, rxq_prod};
            16'h0208: rd_data = rxq_base_lo;
            16'h020C: rd_data = rxq_base_hi;

            16'h0500: rd_data = ft601_rx_words;
            16'h0504: rd_data = ft601_tx_words;
            16'h0508: rd_data = ft601_drop_words;
            16'h050C: rd_data = unsupported_tlp_count;
            16'h0510: rd_data = tx_dma_slot_count;
            16'h0514: rd_data = tx_dma_mrd_count;
            16'h0518: rd_data = rx_dma_slot_count;
            16'h051C: rd_data = rx_dma_mwr_count;
            16'h0520: rd_data = requester_tag_mismatch_count;
            default:  rd_data = 32'h0;
        endcase
    end
endmodule
