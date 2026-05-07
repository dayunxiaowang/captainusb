# captainusb_hw

CaptainUSB FPGA 的内核态硬件层，WDK10 静态库。
封装 BAR0、DMA 环、MSI；消费者在 5120 字节槽上实现协议。

版本 0.1.0，MIT。0.x 期间 API 不固定，新增或删减时，会增加说明。

## 项目

板卡基于 [ufrisk/pcileech-fpga](https://github.com/ufrisk/pcileech-fpga) 的 Captain 75T x1（Artix-7 XC7A75T，PCIe Gen2 x1，FT601 USB3）。

本项目复用该板传递任意主机端数据流：消费者将原始字节填入 5120 字节槽，FPGA 经 PCIe ↔ FT601 透传，对载荷不做解释。
单链路上行 / 下行实测带宽约 160 MB/s（去除上层协议层开销）。

在host端可以参考ufrisk的leechcore调用方式，在fpga中我使用了同样的哨兵字段填充。

## 内容

```
include/                            公开头文件
bin/x64/Release/captainusb_hw.lib   静态库（含 .pdb）
firmware/captainusb.bit             Vivado 比特流
firmware/captainusb.bin             SPI flash 镜像
captainusb_hw.props                 .vcxproj 集成用属性表
```

库实现：

- `MmMapIoSpace` BAR0
- bus master + DMA 适配器
- TX/RX 各 512 × 5120 公共缓冲环
- 中断连接（优先 MSI，回退 INTx），ISR + DPC
- 生产/消费指针、唤醒事件
- BAR0 32 位寄存器读写

库不实现：DriverEntry、PnP 框架、线协议、IOCTL、控制设备、应用层逻辑。

## 固件

`firmware/captainusb.bit` 用 Vivado 加载到 FPGA，`captainusb.bin` 用于固化到板载 SPI flash。

板载用户 LED 未在该比特流中接出。设备上电后只有 PCIe 电源指示灯亮；链路状态与运行状态请通过 `lspci` 或读取 `CUSB_REG_STATUS`、`CUSB_REG_*_COUNT` 系列寄存器确认。

## 集成

在消费者 `.vcxproj` 中 `Microsoft.Cpp.props` 之后追加：

```xml
<Import Project="$(VCTargetsPath)\Microsoft.Cpp.props" />
<Import Project="C:\libs\captainusb-hw-0.1.0\captainusb_hw.props" />
```

属性表自动配置 include 路径、lib 路径、链接依赖。源代码：

```c
#include "captainusb_hw.h"
```

## 使用

设备扩展：

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

START_DEVICE（先转发至下层 PCI 总线驱动）：

```c
CusbHw_StartDevice(ext->Hw,
                   ext->PhysicalDeviceObject,
                   ext->LowerDeviceObject,
                   sp->Parameters.StartDevice.AllocatedResourcesTranslated,
                   NULL);
```

工作线程：

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

STOP / REMOVE 顺序：先终止工作线程，再 `CusbHw_StopDevice`，最后 `CusbHw_Free`。

## 字节序

FT601 在 USB 线上以大端发送 32 位 fabric DWORD，主机端每个 DWORD 字节序需翻转。RX 帧解析前、TX 帧提交前各调用一次：

```c
CusbHw_Bswap32Buffer(rx, CUSB_HW_SLOT_SIZE);
/* 解析 rx；填充 tx */
CusbHw_Bswap32Buffer(tx, CUSB_HW_SLOT_SIZE);
CusbHw_TxCommit(...);
```

## 线程

- 单设备对应单 `CUSB_HW_CTX`。库内部不对 API 做串行化。
- `CusbHw_RxPeek` / `CusbHw_RxConsume` 须由同一线程调用。`CusbHw_TxAcquire` / `CusbHw_TxCommit` 同。
- `CusbHw_ReadReg` / `CusbHw_WriteReg` 任意线程安全（32 位 MMIO 原子）。
- ISR / DPC 由库持有，仅置位唤醒事件并更新计数器。

## 版本检测

```c
#if CUSB_HW_VERSION < CUSB_HW_MAKE_VERSION(0, 1, 0)
#  error require >= 0.1.0
#endif
```

## 许可

[MIT](LICENSE)。本库不约束基于其构建的下游驱动的许可方式。
