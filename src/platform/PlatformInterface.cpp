/**
 * @file PlatformInterface.cpp
 */

#include "PlatformInterface.h"
#include "AndroidPlatform.h"
#include "../core/Logger.h"

namespace outdoor {

PlatformInterface* PlatformInterface::create() {
#ifdef Q_OS_ANDROID
    return new AndroidPlatform();
#else
    // 桌面平台：桩实现
    return new AndroidPlatform();  // 桩实现
#endif
}

} // namespace outdoor
