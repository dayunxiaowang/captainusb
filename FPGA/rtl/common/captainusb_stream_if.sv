`timescale 1ns / 1ps

interface captainusb_stream_if #(
    parameter int DATA_WIDTH = 32
);
    logic [DATA_WIDTH-1:0] data;
    logic                  valid;
    logic                  ready;
    logic                  last;

    modport source (
        output data, valid, last,
        input  ready
    );

    modport sink (
        input  data, valid, last,
        output ready
    );
endinterface
