# captainusb_hw

CaptainUSB FPGA 的内核态硬件层，WDK10 静态库。
封装 BAR0、DMA 环、MSI；消费者在 5120 字节槽上实现协议。

Kernel-mode hardware abstraction layer for the CaptainUSB FPGA, built as a WDK10 static library.
Wraps BAR0, DMA rings, MSI; consumers implement their protocol on 5120-byte slots.

版本 0.1.0，MIT。0.x 期间 API 不固定，新增或删减时，会增加说明。
Version 0.1.0, MIT. During 0.x the API is unstable; changes are documented.

## 项目 / Project

板卡基于 [ufrisk/pcileech-fpga](https://github.com/ufrisk/pcileech-fpga) 的 Captain 75T x1（Artix-7 XC7A75T，PCIe Gen2 x1，FT601 USB3）。

This board is based on [ufrisk/pcileech-fpga](https://github.com/ufrisk/pcileech-fpga)'s Captain 75T x1 (Artix-7 XC7A75T, PCIe Gen2 x1, FT601 USB3).

本项目复用该板传递任意主机端数据流：消费者将原始字节填入 5120 字节槽，FPGA 经 PCIe ↔ FT601 透传，对载荷不做解释。
单链路上行 / 下行实测带宽约 160 MB/s（去除上层协议层开销）。

This project uses the board as a transparent pipe for arbitrary host data streams: consumers fill 5120-byte slots, the FPGA passes them through PCIe ↔ FT601 without inspecting payloads.
Single-link throughput ~160 MB/s in each direction (net of protocol overhead).

在 host 端可以参考 ufrisk 的 leechcore 调用方式，在 FPGA 中我使用了同样的哨兵字段填充。

On the host side, refer to ufrisk's leechcore API; the FPGA uses the same sentinel padding scheme.

## 内容 / Contents

```
include/                            公开头文件 / Public headers
bin/x64/Release/captainusb_hw.lib   静态库（含 .pdb）/ Static library (with .pdb)
FPGA/                               FPGA 源码（见下方说明）/ FPGA source (see below)
captainusb_hw.props                 .vcxproj 集成用属性表 / MSBuild property sheet
```

> **注意：** 旧版 `firmware/` 目录已移除，替换为 `FPGA/` 完整源码。`.bit` / `.bin` 请从源码自行构建。
> **Note:** The old `firmware/` directory has been replaced with full `FPGA/` sources. Build `.bit` / `.bin` from source.

库实现 / Library implements:

- `MmMapIoSpace` BAR0
- bus master + DMA 适配器 / DMA adapter
- TX/RX 各 512 × 5120 公共缓冲环 / 512 × 5120 shared buffer rings per direction
- 中断连接（优先 MSI，回退 INTx），ISR + DPC / Interrupt wiring (MSI preferred, INTx fallback), ISR + DPC
- 生产/消费指针、唤醒事件 / Producer/consumer pointers, wake events
- BAR0 32 位寄存器读写 / 32-bit BAR0 register read/write

库不实现 / Library does NOT implement：DriverEntry、PnP 框架、线协议、IOCTL、控制设备、应用层逻辑。
DriverEntry, PnP framework, wire protocol, IOCTL, control device, or application logic.

## FPGA 源码 / FPGA Source

本项目 FPGA 源码位于 `FPGA/` 目录，包含完整的 SystemVerilog RTL 和 Vivado 构建脚本。

FPGA source code lives in the `FPGA/` directory, with complete SystemVerilog RTL and Vivado build scripts.

**构建要求 / Prerequisites：** Vivado 2025.2

```bash
cd FPGA
make             # 完整 bitstream 构建 / Full bitstream build
make project     # 仅创建 Vivado 项目 / Create Vivado project only
make synth       # 综合检查 / Synthesis check
make clean       # 清理构建产物 / Remove build artifacts
```

输出 bitstream / Output: `FPGA/build/CaptainUSB/CaptainUSB.runs/impl_1/captainusb_top.bit`

详细文档见 / See [FPGA/README.md](FPGA/README.md) for details.

## 集成 / Integration

在消费者 `.vcxproj` 中 `Microsoft.Cpp.props` 之后追加 / Add after `Microsoft.Cpp.props` in your consumer `.vcxproj`:

```xml
<Import Project="$(VCTargetsPath)\Microsoft.Cpp.props" />
<Import Project="C:\libs\captainusb-hw-0.1.0\captainusb_hw.props" />
```

属性表自动配置 include 路径、lib 路径、链接依赖。源代码 / The property sheet sets include paths, lib paths, and link dependencies. Source:

```c
#include "captainusb_hw.h"
```

## 使用 / Usage

设备扩展 / Device extension:

```c
typedef struct _MY_DEVEXT {
    PDEVICE_OBJECT  DeviceObject;
    PDEVICE_OBJECT  LowerDeviceObject;
    PDEVICE_OBJECT  PhysicalDeviceObject;
    PCUSB_HW_CTX    Hw;
} MY_DEVEXT;
```

AddDevice：

```c
CusbHw_Alloc(&ext->Hw);
```

START_DEVICE（先转发至下层 PCI 总线驱动）/ Forward to the lower PCI bus driver first:

```c
CusbHw_StartDevice(ext->Hw,
                   ext->PhysicalDeviceObject,
                   ext->LowerDeviceObject,
                   sp->Parameters.StartDevice.AllocatedResourcesTranslated,
                   NULL);
```

工作线程 / Worker thread:

```c
PKEVENT wake = CusbHw_GetWakeEvent(ext->Hw);

while (!Stopping(ext)) {
    BOOLEAN progressed = FALSE;
    PUCHAR rx;

    while ((rx = CusbHw_RxPeek(ext->Hw)) != NULL) {
        PUCHAR tx;
        while ((tx = CusbHw_TxAcquire(ext->Hw)) == NULL) {
            if (Stopping(ext)) return;
        }
        HandleFrame(rx, tx);
        CusbHw_TxCommit(ext->Hw);
        CusbHw_RxConsume(ext->Hw);
        progressed = TRUE;
    }

    if (!progressed) {
        LARGE_INTEGER to = { .QuadPart = -10 * 1000 };
        CusbHw_WaitForWork(ext->Hw, &to);
    }
}
```

`CusbHw_WaitForWork` 在阻塞前重写 `CUSB_REG_IRQ_MASK`。如需自行管理 IRQ 重置，直接 `KeWaitForSingleObject` 等待 `CusbHw_GetWakeEvent` 返回的事件。

`CusbHw_WaitForWork` rewrites `CUSB_REG_IRQ_MASK` before blocking. To manage IRQ reset yourself, wait directly on the event from `CusbHw_GetWakeEvent` with `KeWaitForSingleObject`.

STOP / REMOVE 顺序 / Order：先终止工作线程，再 `CusbHw_StopDevice`，最后 `CusbHw_Free`。
Terminate the worker thread first, then `CusbHw_StopDevice`, then `CusbHw_Free`.

## 字节序 / Byte Order

FT601 在 USB 线上以大端发送 32 位 fabric DWORD，主机端每个 DWORD 字节序需翻转。RX 帧解析前、TX 帧提交前各调用一次：

The FT601 sends 32-bit fabric DWORDs in big-endian on the USB wire; each DWORD must be byte-swapped on the host side. Call once before RX frame parsing and once before TX frame commit:

```c
CusbHw_Bswap32Buffer(rx, CUSB_HW_SLOT_SIZE);
/* 解析 rx；填充 tx / Parse rx; fill tx */
CusbHw_Bswap32Buffer(tx, CUSB_HW_SLOT_SIZE);
CusbHw_TxCommit(...);
```

## 线程 / Threading

- 单设备对应单 `CUSB_HW_CTX`。库内部不对 API 做串行化。
  One `CUSB_HW_CTX` per device. The library does not serialize API calls internally.
- `CusbHw_RxPeek` / `CusbHw_RxConsume` 须由同一线程调用。`CusbHw_TxAcquire` / `CusbHw_TxCommit` 同。
  `CusbHw_RxPeek` / `CusbHw_RxConsume` must be called from the same thread. Same for `CusbHw_TxAcquire` / `CusbHw_TxCommit`.
- `CusbHw_ReadReg` / `CusbHw_WriteReg` 任意线程安全（32 位 MMIO 原子）。
  `CusbHw_ReadReg` / `CusbHw_WriteReg` are thread-safe (32-bit MMIO is atomic).
- ISR / DPC 由库持有，仅置位唤醒事件并更新计数器。
  ISR / DPC are owned by the library; they only set the wake event and update counters.

## 版本检测 / Version Check

```c
#if CUSB_HW_VERSION < CUSB_HW_MAKE_VERSION(0, 1, 0)
#  error require >= 0.1.0
#endif
```

## 许可 / License

[MIT](LICENSE)。本库不约束基于其构建的下游驱动的许可方式。
The library does not restrict the license of downstream drivers built on top of it.
