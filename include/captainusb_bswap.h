/* FT601 以大端发送 32 位 fabric DWORD，主机端每 DWORD 字节序需翻转。
 * RX 帧解析前、TX 帧提交前各调用一次。 */

#ifndef CAPTAINUSB_LIB_BSWAP_H
#define CAPTAINUSB_LIB_BSWAP_H

#ifdef _KERNEL_MODE
#include <ntddk.h>
#else
#include <windows.h>
#include <stdlib.h>
#endif

FORCEINLINE VOID
CusbHw_Bswap32Buffer(
    _Inout_updates_bytes_(Length) PUCHAR Buffer,
    _In_ ULONG Length)
{
    PULONG p = (PULONG)Buffer;
    ULONG  i, count = Length / 4;
    for (i = 0; i < count; i++)
        p[i] = _byteswap_ulong(p[i]);
}

#endif
