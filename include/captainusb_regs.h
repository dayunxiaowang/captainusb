/* CaptainUSB BAR0 寄存器映射。仅偏移宏，内核态与用户态均可包含。 */

#ifndef CAPTAINUSB_LIB_REGS_H
#define CAPTAINUSB_LIB_REGS_H

#define CUSB_REG_MAGIC              0x0000  /* RO 0x43555342 "CUSB" */
#define CUSB_REG_VERSION            0x0004  /* RO */
#define CUSB_REG_STATUS             0x0008  /* RO bit0 = link up */
#define CUSB_REG_CONTROL            0x000C  /* W bit1=reset bit8=run */
#define CUSB_REG_IRQ_STATUS         0x0010  /* W1C */
#define CUSB_REG_IRQ_MASK           0x0014  /* bit0=TX bit1=RX */
#define CUSB_REG_SLOT_SIZE          0x0018  /* RO 5120 */
#define CUSB_REG_RING_DEPTH         0x001C  /* RO 512 */

/* TX：主机为生产者，FPGA 为消费者，最终经 FT601 IN 端点发送。 */
#define CUSB_REG_TXQ_CTRL           0x0100  /* bit0=enable */
#define CUSB_REG_TXQ_PTR            0x0104  /* W tx_prod[15:0]; R {cons,prod} */
#define CUSB_REG_TXQ_BASE_LO        0x0108
#define CUSB_REG_TXQ_BASE_HI        0x010C

/* RX：FPGA 自 FT601 OUT 端点接收，DMA 写入环。 */
#define CUSB_REG_RXQ_CTRL           0x0200  /* bit0=enable */
#define CUSB_REG_RXQ_PTR            0x0204  /* W rx_cons[15:0]; R {cons,prod} */
#define CUSB_REG_RXQ_BASE_LO        0x0208
#define CUSB_REG_RXQ_BASE_HI        0x020C

/* 调试计数器（只读）。 */
#define CUSB_REG_FT601_RX_WORDS     0x0500
#define CUSB_REG_FT601_TX_WORDS     0x0504
#define CUSB_REG_FT601_DROP_WORDS   0x0508
#define CUSB_REG_TLP_UNSUPPORTED    0x050C
#define CUSB_REG_TX_DMA_SLOT_COUNT  0x0510
#define CUSB_REG_TX_DMA_MRD_COUNT   0x0514
#define CUSB_REG_RX_DMA_SLOT_COUNT  0x0518
#define CUSB_REG_RX_DMA_MWR_COUNT   0x051C
#define CUSB_REG_TAG_MISMATCH       0x0520

#define CUSB_HW_SLOT_SIZE           5120u
#define CUSB_HW_RING_DEPTH          512u
#define CUSB_HW_RING_BYTES          (CUSB_HW_SLOT_SIZE * CUSB_HW_RING_DEPTH)

#define CUSB_HW_IRQ_TX              0x00000001u
#define CUSB_HW_IRQ_RX              0x00000002u
#define CUSB_HW_IRQ_DEFAULT_MASK    (CUSB_HW_IRQ_TX | CUSB_HW_IRQ_RX)

#endif
