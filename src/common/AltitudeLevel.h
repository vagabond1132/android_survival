/**
 * @file AltitudeLevel.h
 * @brief 海拔段位 —— 全站唯一定义 (#18 C3 统一)
 *
 * 2026-10-21 之前这件事有两份实现:
 *   - `MapService::AltitudeLevel`        5 段, >=3500 一律 L4 (自己封顶)
 *   - `EquipmentService::EquipmentAltitudeLevel` 7 段, 前四段阈值与上面完全相同
 * 同一个 4800 m 在装备侧是 L5、在地图侧是 L4; 而 QML 的海拔色阶是按 int 档去取
 * `CommonOptions::altitudeColor(level)` (0..6 七档), 所以地图侧永远拿不到后两档的颜色.
 *
 * 现在只留这一份 7 段定义, 两个服务都转发到这里.
 * **本头不出颜色**: 颜色单一来源仍然是 `src/core/CommonOptions.h` (B2 定的规矩),
 * 谁想要颜色谁自己去取 token.
 */
#ifndef ALTITUDE_LEVEL_H
#define ALTITUDE_LEVEL_H

#include <QString>
#include <limits>

// 上界一律开区间: L0 <500 / L1 <1500 / L2 <2500 / L3 <3500 / L4 <4500 / L5 <5500 / L6 其余
enum class AltitudeLevel {
    L0 = 0, L1 = 1, L2 = 2, L3 = 3, L4 = 4, L5 = 5, L6 = 6
};

namespace AltitudeScale {

inline AltitudeLevel fromMeters(double m) {
    if (m < 500.0)   return AltitudeLevel::L0;
    if (m < 1500.0)  return AltitudeLevel::L1;
    if (m < 2500.0)  return AltitudeLevel::L2;
    if (m < 3500.0)  return AltitudeLevel::L3;
    if (m < 4500.0)  return AltitudeLevel::L4;
    if (m < 5500.0)  return AltitudeLevel::L5;
    return AltitudeLevel::L6;
}

inline QString nameOf(AltitudeLevel level) {
    switch (level) {
        case AltitudeLevel::L0: return QStringLiteral("低海拔");
        case AltitudeLevel::L1: return QStringLiteral("中海拔");
        case AltitudeLevel::L2: return QStringLiteral("中高海拔");
        case AltitudeLevel::L3: return QStringLiteral("高海拔");
        case AltitudeLevel::L4: return QStringLiteral("极高海拔");
        case AltitudeLevel::L5: return QStringLiteral("超高海拔");
        case AltitudeLevel::L6: return QStringLiteral("极高山");
    }
    return QStringLiteral("低海拔");
}

inline double minM(AltitudeLevel level) {
    switch (level) {
        case AltitudeLevel::L0: return 0.0;
        case AltitudeLevel::L1: return 500.0;
        case AltitudeLevel::L2: return 1500.0;
        case AltitudeLevel::L3: return 2500.0;
        case AltitudeLevel::L4: return 3500.0;
        case AltitudeLevel::L5: return 4500.0;
        case AltitudeLevel::L6: return 5500.0;
    }
    return 0.0;
}

// 最高档没有上界. 返回的是 double 最大值而不是某个"看起来像山峰"的数字:
// 谁要把它印到界面上, 必须先判 L6 并改写文案, 不能直接当高度显示.
inline double maxM(AltitudeLevel level) {
    if (level == AltitudeLevel::L6) return (std::numeric_limits<double>::max)();
    switch (level) {
        case AltitudeLevel::L0: return 500.0;
        case AltitudeLevel::L1: return 1500.0;
        case AltitudeLevel::L2: return 2500.0;
        case AltitudeLevel::L3: return 3500.0;
        case AltitudeLevel::L4: return 4500.0;
        case AltitudeLevel::L5: return 5500.0;
        case AltitudeLevel::L6: break;
    }
    return 500.0;
}

}  // namespace AltitudeScale

#endif  // ALTITUDE_LEVEL_H
