`timescale 1ns / 1ps

package captainusb_pkg;
    localparam int CAPTAINUSB_VERSION_MAJOR = 0;
    localparam int CAPTAINUSB_VERSION_MINOR = 1;

    localparam logic [31:0] CAPTAINUSB_MAGIC = 32'h43555342;

    typedef enum logic [7:0] {
        FRAME_TYPE_DATA        = 8'h01,
        FRAME_TYPE_LINK_STATUS = 8'h02,
        FRAME_TYPE_ERROR       = 8'h7f
    } captainusb_frame_type_t;

    typedef enum logic [7:0] {
        DMA_DESC_FREE      = 8'h00,
        DMA_DESC_READY     = 8'h01,
        DMA_DESC_ACTIVE    = 8'h02,
        DMA_DESC_COMPLETE  = 8'h03,
        DMA_DESC_ERROR     = 8'h80
    } captainusb_desc_status_t;
endpackage
