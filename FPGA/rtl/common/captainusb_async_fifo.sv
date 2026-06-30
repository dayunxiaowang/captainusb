`timescale 1ns / 1ps

module captainusb_async_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 6
) (
    input  wire                  wr_clk,
    input  wire                  wr_rst,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire                  wr_valid,
    output wire                  wr_ready,

    input  wire                  rd_clk,
    input  wire                  rd_rst,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_valid,
    input  wire                  rd_ready,

    output wire                  full,
    output wire                  empty,
    output wire [ADDR_WIDTH:0]   rd_data_count,
    output wire [ADDR_WIDTH:0]   wr_data_count
);
    localparam int DEPTH = 1 << ADDR_WIDTH;

    wire data_valid;
    wire wr_rst_busy;
    wire rd_rst_busy;

    wire almost_empty_unused;
    wire almost_full_unused;
    wire dbiterr_unused;
    wire overflow_unused;
    wire prog_empty_unused;
    wire prog_full_unused;
    wire sbiterr_unused;
    wire underflow_unused;
    wire wr_ack_unused;
    assign wr_ready = !full && !wr_rst_busy;
    assign rd_valid = !empty && !rd_rst_busy;
    xpm_fifo_async #(
        .CDC_SYNC_STAGES        (2),
        .DOUT_RESET_VALUE       ("0"),
        .ECC_MODE               ("no_ecc"),
        .FIFO_MEMORY_TYPE       ("block"),
        .FIFO_READ_LATENCY      (0),
        .FIFO_WRITE_DEPTH       (DEPTH),
        .FULL_RESET_VALUE       (0),
        .PROG_EMPTY_THRESH      (10),
        .PROG_FULL_THRESH       (10),
        .RD_DATA_COUNT_WIDTH    (ADDR_WIDTH + 1),
        .READ_DATA_WIDTH        (DATA_WIDTH),
        .READ_MODE              ("fwft"),
        .RELATED_CLOCKS         (0),
        .SIM_ASSERT_CHK         (0),
        .USE_ADV_FEATURES       ("0707"),
        .WAKEUP_TIME            (0),
        .WRITE_DATA_WIDTH       (DATA_WIDTH),
        .WR_DATA_COUNT_WIDTH    (ADDR_WIDTH + 1)
    ) i_xpm_fifo_async (
        .almost_empty           (almost_empty_unused),
        .almost_full            (almost_full_unused),
        .data_valid             (data_valid),
        .dbiterr                (dbiterr_unused),
        .dout                   (rd_data),
        .empty                  (empty),
        .full                   (full),
        .overflow               (overflow_unused),
        .prog_empty             (prog_empty_unused),
        .prog_full              (prog_full_unused),
        .rd_data_count          (rd_data_count),
        .rd_rst_busy            (rd_rst_busy),
        .sbiterr                (sbiterr_unused),
        .underflow              (underflow_unused),
        .wr_ack                 (wr_ack_unused),
        .wr_data_count          (wr_data_count),
        .wr_rst_busy            (wr_rst_busy),
        .din                    (wr_data),
        .injectdbiterr          (1'b0),
        .injectsbiterr          (1'b0),
        .rd_clk                 (rd_clk),
        .rd_en                  (rd_ready && rd_valid),
        .rst                    (wr_rst),
        .sleep                  (1'b0),
        .wr_clk                 (wr_clk),
        .wr_en                  (wr_valid && wr_ready)
    );
endmodule
