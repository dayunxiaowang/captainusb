`timescale 1ns / 1ps

module captainusb_tlp_tx64 (
    input  wire        clk,
    input  wire        rst,

    input  wire        req_valid,
    output wire        req_ready,
    input  wire [1:0]  req_type,
    input  wire [15:0] completer_id,
    input  wire [15:0] requester_id,
    input  wire [7:0]  tag,
    input  wire [63:0] addr,
    input  wire [31:0] data,
    input  wire [3:0]  first_be,
    input  wire [3:0]  last_be,
    input  wire [6:0]  lower_addr,
    input  wire [9:0]  length_dw,
    input  wire [31:0] data_word,
    input  wire        data_valid,
    output wire        data_ready,

    output reg  [63:0] tx_tdata = 64'h0000000000000000,
    output reg  [7:0]  tx_tkeep = 8'h00,
    output reg         tx_tlast = 1'b0,
    output wire [3:0]  tx_tuser,
    output reg         tx_tvalid = 1'b0,
    input  wire        tx_tready
);
    localparam logic [1:0] REQ_CPLD  = 2'd0;
    localparam logic [1:0] REQ_MRD32 = 2'd1;
    localparam logic [1:0] REQ_MWR32 = 2'd2;

    localparam int unsigned PAYLOAD_BUF_DW = 32;

    localparam logic [2:0] ST_IDLE        = 3'd0;
    localparam logic [2:0] ST_FETCH_BURST = 3'd1;
    localparam logic [2:0] ST_SEND0       = 3'd2;
    localparam logic [2:0] ST_SEND1       = 3'd3;
    localparam logic [2:0] ST_BURST_EMIT  = 3'd4;

    reg [2:0] state = ST_IDLE;

    reg [31:0] payload_buf [0:PAYLOAD_BUF_DW-1];

    reg [31:0] send_h0       = 32'h0;
    reg [31:0] send_h1       = 32'h0;
    reg [31:0] send_h2       = 32'h0;
    reg [31:0] send_first_dw = 32'h0;
    reg [9:0]  cur_length_dw = 10'd1;
    reg        cur_is_mwr    = 1'b0;
    reg        cur_is_burst  = 1'b0;
    reg [7:0]  send_keep1    = 8'hff;

    reg [9:0] fetch_idx       = 10'd0;
    reg [9:0] burst_emit_idx  = 10'd0;

    wire [4:0] fetch_idx_w     = fetch_idx[4:0];
    wire [4:0] emit_idx_lo_w   = burst_emit_idx[4:0];
    wire [9:0] emit_idx_hi_full = burst_emit_idx + 10'd1;
    wire [4:0] emit_idx_hi_w   = emit_idx_hi_full[4:0];

    reg data_pop = 1'b0;
    assign data_ready = data_pop;
    assign req_ready  = (state == ST_IDLE) && (!tx_tvalid || tx_tready);
    assign tx_tuser   = 4'h0;

    function automatic [15:0] bswap16;
        input [15:0] value;
        begin
            bswap16 = {value[7:0], value[15:8]};
        end
    endfunction

    function automatic [31:0] bswap32;
        input [31:0] value;
        begin
            bswap32 = {value[7:0], value[15:8], value[23:16], value[31:24]};
        end
    endfunction
    wire [31:0] cpld_h0 = {1'b0, 2'b10, 5'b01010, 1'b0, 3'b000, 4'b0000, 1'b0, 1'b0, 2'b00, 2'b00, 10'd1};
    wire [31:0] cpld_h1 = {bswap16(completer_id), 3'b000, 1'b0, 12'd4};
    wire [31:0] cpld_h2 = {requester_id, tag, 1'b0, lower_addr};

    wire [31:0] req_h1_static = {requester_id, tag, last_be, first_be};
    wire [31:0] req_h2_static = {addr[31:2], 2'b00};

    function automatic [31:0] mwr_h0_for(input [9:0] len_dw);
        mwr_h0_for = {1'b0, 2'b10, 5'b00000, 1'b0, 3'b000, 4'b0000, 1'b0, 1'b0, 2'b00, 2'b00, len_dw};
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state          <= ST_IDLE;
            tx_tvalid      <= 1'b0;
            tx_tdata       <= 64'h0;
            tx_tkeep       <= 8'h00;
            tx_tlast       <= 1'b0;
            cur_is_mwr     <= 1'b0;
            cur_is_burst   <= 1'b0;
            cur_length_dw  <= 10'd1;
            send_keep1     <= 8'hff;
            fetch_idx      <= 10'd0;
            burst_emit_idx <= 10'd0;
            data_pop       <= 1'b0;
        end else begin
            data_pop <= 1'b0;

            if (tx_tvalid && tx_tready) begin
                tx_tvalid <= 1'b0;
                tx_tlast  <= 1'b0;
                tx_tkeep  <= 8'h00;
            end

            case (state)
                ST_IDLE: begin
                    if (req_valid && req_ready) begin
                        case (req_type)
                            REQ_CPLD: begin
                                send_h0       <= cpld_h0;
                                send_h1       <= cpld_h1;
                                send_h2       <= cpld_h2;
                                send_first_dw <= bswap32(data);
                                send_keep1    <= 8'hff;
                                cur_is_mwr    <= 1'b0;
                                cur_is_burst  <= 1'b0;
                                cur_length_dw <= 10'd1;
                                state         <= ST_SEND0;
                            end
                            REQ_MRD32: begin
                                send_h0       <= {1'b0, 2'b00, 5'b00000, 1'b0, 3'b000,
                                                  4'b0000, 1'b0, 1'b0, 2'b00, 2'b00, length_dw};
                                send_h1       <= req_h1_static;
                                send_h2       <= req_h2_static;
                                send_first_dw <= 32'h0;
                                send_keep1    <= 8'h0f;
                                cur_is_mwr    <= 1'b0;
                                cur_is_burst  <= 1'b0;
                                cur_length_dw <= length_dw;
                                state         <= ST_SEND0;
                            end
                            REQ_MWR32: begin
                                send_h0       <= mwr_h0_for(length_dw);
                                send_h1       <= req_h1_static;
                                send_h2       <= req_h2_static;
                                send_keep1    <= 8'hff;
                                cur_is_mwr    <= 1'b1;
                                cur_is_burst  <= (length_dw > 10'd1);
                                cur_length_dw <= length_dw;
                                if (length_dw > 10'd1) begin
                                    fetch_idx <= 10'd0;
                                    state     <= ST_FETCH_BURST;
                                end else begin
                                    send_first_dw <= bswap32(data);
                                    state         <= ST_SEND0;
                                end
                            end
                            default: state <= ST_IDLE;
                        endcase
                    end
                end

                ST_FETCH_BURST: begin
                    if (data_valid) begin
                        payload_buf[fetch_idx_w] <= bswap32(data_word);
                        data_pop <= 1'b1;
                        if (fetch_idx + 10'd1 == cur_length_dw) begin
                            fetch_idx <= 10'd0;
                            state     <= ST_SEND0;
                        end else begin
                            fetch_idx <= fetch_idx + 10'd1;
                        end
                    end
                end

                ST_SEND0: begin
                    if (!tx_tvalid || tx_tready) begin
                        tx_tdata  <= {send_h1, send_h0};
                        tx_tkeep  <= 8'hff;
                        tx_tlast  <= 1'b0;
                        tx_tvalid <= 1'b1;
                        state     <= ST_SEND1;
                    end
                end

                ST_SEND1: begin
                    if (!tx_tvalid || tx_tready) begin
                        if (cur_is_burst) begin
                            tx_tdata[31:0]  <= send_h2;
                            tx_tdata[63:32] <= payload_buf[5'd0];
                            tx_tkeep        <= 8'hff;
                            tx_tlast        <= 1'b0;
                            burst_emit_idx  <= 10'd1;
                            state           <= ST_BURST_EMIT;
                        end else begin
                            tx_tdata[31:0]  <= send_h2;
                            tx_tdata[63:32] <= send_first_dw;
                            tx_tkeep        <= send_keep1;
                            tx_tlast        <= 1'b1;
                            state           <= ST_IDLE;
                        end
                        tx_tvalid <= 1'b1;
                    end
                end

                ST_BURST_EMIT: begin
                    if (!tx_tvalid || tx_tready) begin
                        tx_tdata[31:0] <= payload_buf[emit_idx_lo_w];
                        if (burst_emit_idx + 10'd1 < cur_length_dw) begin
                            tx_tdata[63:32] <= payload_buf[emit_idx_hi_w];
                            tx_tkeep        <= 8'hff;
                            if (burst_emit_idx + 10'd2 >= cur_length_dw) begin
                                tx_tlast       <= 1'b1;
                                state          <= ST_IDLE;
                            end else begin
                                tx_tlast       <= 1'b0;
                                burst_emit_idx <= burst_emit_idx + 10'd2;
                            end
                        end else begin
                            tx_tdata[63:32] <= 32'h0;
                            tx_tkeep        <= 8'h0f;
                            tx_tlast        <= 1'b1;
                            state           <= ST_IDLE;
                        end
                        tx_tvalid <= 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    wire unused_header = ^addr[63:32];
endmodule
