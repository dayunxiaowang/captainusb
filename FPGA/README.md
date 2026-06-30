# CaptainUSB

> **FPGA-based USB 3.0 (FT601) ↔ PCIe DMA data mover**
> **基于 FPGA 的 USB 3.0 (FT601) 到 PCIe DMA 数据搬运器**

Target: **xc7a75tfgg484-2** (Artix-7 75T, FG484)

---

## 概述 / Overview

CaptainUSB 是一个纯 FPGA 工程，实现 FTDI FT601Q USB 3.0 桥接芯片与 PCIe Gen2 x1 接口之间的高速数据搬运。设计采用 NIC 风格的描述符环 DMA 架构，所有数据流控制、时钟域交叉、FIFO 管理均在 FPGA 内完成，无需外部控制器。

CaptainUSB is a pure FPGA project that bridges an FTDI FT601Q USB 3.0 interface to a PCIe Gen2 x1 link using NIC-style descriptor ring DMA. All flow control, clock-domain crossing, and FIFO management are handled entirely inside the FPGA fabric.

---

## 硬件平台 / Hardware Platform

| Component | Detail |
|-----------|--------|
| FPGA | Xilinx Artix-7 XC7A75T-2FGG484 |
| USB Bridge | FTDI FT601Q (USB 3.0, 245 synchronous FIFO mode) |
| PCIe | Gen2 x1, 5.0 GT/s, 64-bit interface @ 62.5 MHz |
| Clocks | 100 MHz system, 100 MHz FT601, 100 MHz PCIe reference |

---

## 设计架构 / Architecture

```
                    ┌──────────────────────────────────────────┐
                    │               captainusb_top              │
                    │                                          │
  ┌─────────┐      │  ┌────────────┐    ┌──────────────────┐   │
  │  FT601   │◄────►│  │ FT601 PHY  │    │   PCIe App +     │   │
  │  FT601Q  │      │  │ + Loopback │◄──►│  Ring DMA Engine │◄──► PCIe
  │  USB 3.0 │      │  │ (CDC FIFO) │    │  (TX/RX rings)   │   │  Endpoint
  └─────────┘      │  └────────────┘    └──────────────────┘   │
                    │      100 MHz           62.5 MHz           │
                    └──────────────────────────────────────────┘
```

### 时钟域 / Clock Domains

| Domain | Source | Frequency | Used By |
|--------|--------|-----------|---------|
| sys_clk | Board oscillator (pin J19) | 100 MHz | Power-on reset, LED, DNA read |
| ft601_clk | FT601 output (pin K18) | 100 MHz | FT601 PHY, RX/TX FIFOs (one side) |
| pcie_user_clk | PCIe IP core output | 62.5 MHz | PCIe app, DMA engine, FIFOs (other side) |

两个异步时钟域通过 3 组异步 FIFO 桥接，`ASYNC_REG` 同步链处理 CDC 信号。

---

## 模块详解 / Module Details

### RTL 目录结构 / Source Tree

```
rtl/
├── captainusb_top.sv              Top-level
├── common/
│   ├── captainusb_pkg.sv          Package: version, magic, enums
│   ├── captainusb_sync_fifo.sv    Synchronous FIFO (FWFT)
│   ├── captainusb_async_fifo.sv   Asynchronous (dual-clock) FIFO
│   ├── captainusb_reset_sync.sv   Reset synchronizer
│   └── captainusb_stream_if.sv    Stream interface helper
├── ft601/
│   ├── captainusb_ft601_phy.sv    FT245 synchronous FIFO master
│   └── captainusb_ft601_loopback.sv  CDC wrapper + PING responder
├── pcie/
│   ├── captainusb_pcie_minimal_a7.sv  7-series PCIe wrapper
│   ├── captainusb_pcie_app.sv         PCIe application top
│   ├── captainusb_bar0_regs.sv        BAR0 register file
│   ├── captainusb_tlp_rx64.sv         TLP receive (64-bit)
│   ├── captainusb_tlp_tx64.sv         TLP transmit (64-bit)
│   └── captainusb_pcie_requester_7x.sv  PCIe requester
└── dma/
    ├── captainusb_ring_tx_dma.sv    TX descriptor ring DMA
    └── captainusb_ring_rx_dma.sv    RX descriptor ring DMA
```

### FT601 PHY / Loopback

- **captainusb_ft601_phy.sv** — FT245 同步 FIFO 主控，兼容 FT601 时序。5 级发送暂存队列，接收路径带 0x66665555 填充字过滤。所有数据/控制信号 IOB 约束以降低输出延迟。
- **captainusb_ft601_loopback.sv** — 异步时钟域桥接。包含 128 KiB RX FIFO、1 KiB TX 暂存 FIFO、硬件 PING 应答器（无 DMA 时自动回应 PING 帧）。

### PCIe Endpoint

- **captainusb_pcie_minimal_a7.sv** — 封装 `pcie_7x` IP 核，包含 IBUFDS_GTE2、时钟桥接、复位同步。
- **captainusb_pcie_app.sv** — PCIe 应用层：BAR0 MMIO 读写处理、TX/RX 描述符环引擎、MSI 中断产生、TLP 请求器共享仲裁。
- **captainusb_tlp_rx64.sv / tlp_tx64.sv** — 64 位 TLP 收发，支持 MRd、MWr、CplD、Cfg 等事务类型。

### DMA 引擎 / Ring DMA

TX 和 RX 各有一个独立的描述符环引擎，每个环最多 512 个槽，每个槽描述符指向一个 5120 字节的主机物理缓冲区。

| Feature | TX Ring | RX Ring |
|---------|---------|---------|
| Slot count | 512 max | 512 max |
| Buffer size | 5120 B | 5120 B |
| Producer | Driver (BAR0 write) | FPGA (hardware) |
| Consumer | FPGA (PCIe read) | Driver (BAR0 read + advance) |
| Ownership | Driver sets OWN=1 | FPGA sets OWN=1 |
| Interrupt | On completion (configurable) | On completion (configurable) |

---

## 寄存器接口 / Register Interface (BAR0, 64 KB)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x000 | CUSB_VERSION | RO | Hardware version (4 BCD digits) |
| 0x004 | CUSB_MAGIC | RO | Always 0x43555342 ("CUSB") |
| 0x010 | CUSB_CTRL | RW | Control: reset rings, enable DMA, enable interrupts |
| 0x014 | CUSB_STATUS | RO | Status: FT601 link up, DMA active, error flags |
| 0x020 | CUSB_TX_RING_BASE | RW | TX descriptor ring base address (host physical) |
| 0x024 | CUSB_TX_RING_SIZE | RW | TX ring slot count |
| 0x028 | CUSB_TX_PROD_IDX | RW | TX producer index (driver writes) |
| 0x02C | CUSB_TX_CONS_IDX | RO | TX consumer index (FPGA advances) |
| 0x030 | CUSB_RX_RING_BASE | RW | RX descriptor ring base address |
| 0x034 | CUSB_RX_RING_SIZE | RW | RX ring slot count |
| 0x038 | CUSB_RX_PROD_IDX | RO | RX producer index (FPGA writes) |
| 0x03C | CUSB_RX_CONS_IDX | RW | RX consumer index (driver advances) |
| 0x040 | CUSB_MSI_ADDR | RW | MSI memory write address |
| 0x044 | CUSB_MSI_DATA | RW | MSI memory write data |
| 0x048 | CUSB_MSI_CTRL | RW | MSI control: enable, assert |
| 0x100+ | CUSB_PING_DATA | RW | Hardware PING test data (16 x 32-bit) |

---

## 数据帧格式 / FT601 Frame Format (5120 bytes)

| Offset | Size | Field |
|--------|------|-------|
| 0x000 | 1024 | Frame header |
| 0x400 | 4096 | Payload data |

**Frame header structure:**

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0x000 | 4 | magic | 0x43555342 ("CUSB") |
| 0x004 | 4 | frame_type | 0=PING, 1=PONG, 2=DATA, 3=CMD |
| 0x008 | 4 | seq | Sequence number |
| 0x00C | 4 | length | Payload length in bytes |
| 0x010 | 4 | flags | Reserved |
| 0x014 | 4 | checksum | XOR32 over magic..payload end |
| 0x018 | 1004 | reserved | Zero-padded |

---

## 描述符格式 / Descriptor Format (16 bytes)

| Offset | Size | Field |
|--------|------|-------|
| 0x000 | 8 | buffer_addr (host physical) |
| 0x008 | 4 | byte_count |
| 0x00C | 1 | flags (bit0=own, bit1=irq) |
| 0x00D | 1 | status |
| 0x00E | 2 | reserved |

---

## 构建 / Build

```bash
# Prerequisites: Vivado 2025.2 on PATH (or set VIVADO env var)

make             # Full bitstream build (default target)
make project     # Create Vivado project only
make synth       # Quick synthesis check
make clean       # Remove build artifacts
make distclean   # Remove build/ and IP generated files
```

Bitstream output: `build/CaptainUSB/CaptainUSB.runs/impl_1/captainusb_top.bit`

---

## 目录结构 / Directory Structure

```
CaptainUSB/
├── Makefile            Build automation
├── README.md           This file
├── constraints/        XDC pin & timing constraints
├── ip/                 PCIe 7-series IP core configuration (XCI)
├── scripts/            Vivado Tcl build scripts
└── rtl/                SystemVerilog RTL sources
    ├── common/         Shared primitives (FIFOs, reset, stream)
    ├── ft601/          FT601 USB PHY & loopback
    ├── pcie/           PCIe endpoint & TLP layer
    └── dma/            Descriptor ring DMA engines
```

---

## License

MIT