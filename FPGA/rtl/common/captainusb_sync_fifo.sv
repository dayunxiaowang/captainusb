`timescale 1ns / 1ps

module captainusb_sync_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 6
) (
    input  wire                  clk,
    input  wire                  rst,

    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire                  wr_valid,
    output wire                  wr_ready,

    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_valid,
    input  wire                  rd_ready,

    output wire                  full,
    output wire                  empty
);
    localparam int DEPTH = 1 << ADDR_WIDTH;

    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wr_ptr = '0;
    reg [ADDR_WIDTH:0] rd_ptr = '0;

    wire do_write = wr_valid && wr_ready;
    wire do_read  = rd_valid && rd_ready;

    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                   (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    assign wr_ready = !full;
    assign rd_valid = !empty;
    assign rd_data  = mem[rd_ptr[ADDR_WIDTH-1:0]];

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (do_write) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end

            if (do_read) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end
endmodule
