/*
 * CaptainUSB FPGA 硬件层。
 * 封装 BAR0、DMA 环、MSI；提供 5120 字节槽的 acquire / commit 接口。
 * 线协议由消费者在槽数据上实现。
 */

#ifndef CAPTAINUSB_LIB_HW_H
#define CAPTAINUSB_LIB_HW_H

#include <ntddk.h>
#include "captainusb_regs.h"
#include "captainusb_bswap.h"

#define CUSB_HW_VERSION_MAJOR  0
#define CUSB_HW_VERSION_MINOR  1
#define CUSB_HW_VERSION_PATCH  0
#define CUSB_HW_VERSION_STRING "0.1.0"

#define CUSB_HW_MAKE_VERSION(maj, min, pat) \
    (((maj) << 24) | ((min) << 16) | (pat))
#define CUSB_HW_VERSION CUSB_HW_MAKE_VERSION( \
    CUSB_HW_VERSION_MAJOR, CUSB_HW_VERSION_MINOR, CUSB_HW_VERSION_PATCH)

typedef struct _CUSB_HW_CTX CUSB_HW_CTX, *PCUSB_HW_CTX;

/* 字段置 0 表示采用默认值 (SlotSize=5120, RingDepth=512, IrqMask=TX|RX)。 */
typedef struct _CUSB_HW_CONFIG {
    ULONG SlotSize;
    ULONG RingDepth;
    ULONG IrqMask;
} CUSB_HW_CONFIG, *PCUSB_HW_CONFIG;

typedef struct _CUSB_HW_INFO {
    ULONGLONG Bar0PhysicalAddress;
    ULONG     Bar0Length;
    ULONG     Started;
    ULONG     IsrCount;
    ULONG     DpcCount;
    USHORT    RxProd;
    USHORT    RxCons;
    USHORT    TxProd;
    USHORT    TxCons;
    ULONG     RxqPtrRaw;
    ULONG     TxqPtrRaw;
} CUSB_HW_INFO, *PCUSB_HW_INFO;

NTSTATUS CusbHw_Alloc(_Outptr_ PCUSB_HW_CTX *Hw);
VOID     CusbHw_Free (_In_opt_ _Frees_ptr_opt_ PCUSB_HW_CTX Hw);

/* 在 IRP_MN_START_DEVICE 处理中调用；调用方需先将 IRP 转发至下层 PCI。
 * Config 为 NULL 时采用默认值。 */
NTSTATUS CusbHw_StartDevice(
    _Inout_ PCUSB_HW_CTX        Hw,
    _In_    PDEVICE_OBJECT      Pdo,
    _In_    PDEVICE_OBJECT      LowerDevice,
    _In_    PCM_RESOURCE_LIST   ResourcesTranslated,
    _In_opt_ PCUSB_HW_CONFIG    Config);

/* 可重复调用。 */
VOID CusbHw_StopDevice(_Inout_ PCUSB_HW_CTX Hw);

ULONG CusbHw_ReadReg (_In_ PCUSB_HW_CTX Hw, _In_ ULONG Offset);
VOID  CusbHw_WriteReg(_In_ PCUSB_HW_CTX Hw, _In_ ULONG Offset, _In_ ULONG Value);

/* 槽数据为 fabric 字节序，解析前需调用 CusbHw_Bswap32Buffer。
 * 无新帧时返回 NULL。返回的指针在对应 CusbHw_RxConsume 调用前保持有效。 */
_Ret_maybenull_ PUCHAR CusbHw_RxPeek(_In_ PCUSB_HW_CTX Hw);
VOID                   CusbHw_RxConsume(_Inout_ PCUSB_HW_CTX Hw);

/* TX 环满时返回 NULL。CusbHw_TxCommit 前需调用 CusbHw_Bswap32Buffer。 */
_Ret_maybenull_ PUCHAR CusbHw_TxAcquire(_In_ PCUSB_HW_CTX Hw);
VOID                   CusbHw_TxCommit(_Inout_ PCUSB_HW_CTX Hw);

/* DPC 置位的 SynchronizationEvent。生命周期与 ctx 一致。 */
PKEVENT CusbHw_GetWakeEvent(_In_ PCUSB_HW_CTX Hw);

VOID CusbHw_GetInfo(_In_ PCUSB_HW_CTX Hw, _Out_ PCUSB_HW_INFO Info);

/* Timeout 单位 100ns；NULL 表示无限等待，0 表示立即返回。
 * 阻塞前重写 CUSB_REG_IRQ_MASK，消除 ISR 屏蔽中断后的丢失窗口。 */
NTSTATUS CusbHw_WaitForWork(_In_ PCUSB_HW_CTX Hw, _In_opt_ PLARGE_INTEGER Timeout);

#endif
