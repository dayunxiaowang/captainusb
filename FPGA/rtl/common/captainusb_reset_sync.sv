`timescale 1ns / 1ps

module captainusb_reset_sync #(
    parameter int STAGES = 3
) (
    input  wire clk,
    input  wire arst,
    output wire srst
);
    (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] sync = {STAGES{1'b1}};

    always @(posedge clk or posedge arst) begin
        if (arst) begin
            sync <= {STAGES{1'b1}};
        end else begin
            sync <= {sync[STAGES-2:0], 1'b0};
        end
    end

    assign srst = sync[STAGES-1];
endmodule
