#pragma once
/*
 * MinGW ships sdkddkver.h. The Visual Studio project includes SDKDDKVer.h,
 * which on a case-sensitive filesystem is a different name. This shim matches
 * the Windows SDK header: pick the newest platform macros when none are set.
 */
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#include <sdkddkver.h>
