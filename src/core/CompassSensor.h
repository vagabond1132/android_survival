/**
 * @file CompassSensor.h
 * @brief 电子罗盘封装 (QtSensors QCompass) — 丁骨架的朝向来源 (2026-10-20)
 *
 * 为什么要在 C++ 侧包一层而不是 QML 里直接 `import QtSensors`:
 *   ①营地的方位盘、⑤求助的读数块、地图页的方向指针要读同一个 heading. 之前
 *   DirectionCompassOverlay.qml 的注释写着"heading 来源: mapService.getCurrentHeading()",
 *   但全站没有任何一处实现 —— 那个指针永远停在 0°, MapPage 的 currentHeading
 *   也从没被赋值过. 包一个单例出来, 三个页面绑同一个属性, 不再各写各的.
 *   另外本项目 QML 侧一律走 context property (见 ServiceRegistry::registerToQmlContext
 *   里 2026-09-11 那段回滚说明), 不引入新的 QML module import.
 *
 * 只在页面可见时 active: 罗盘传感器持续开会明显吃电, 户外场景恰恰是电量最金贵的.
 */

#pragma once

#include <QObject>
#include <QCompass>
#include <QCompassReading>

namespace outdoor {

class CompassSensor : public QObject
{
    Q_OBJECT
    // 设备朝向, 0=北 顺时针. valid 为 false 时不要拿去画指针.
    Q_PROPERTY(qreal heading READ heading NOTIFY headingChanged)
    Q_PROPERTY(bool valid READ valid NOTIFY validChanged)
    // 校准度 0-100; -1 = 系统不提供该信息 (部分机型). 低于 ~40 时读数会漂,
    // 界面应提示"画 8 字校准"而不是直接显示角度.
    Q_PROPERTY(int calibrationPercent READ calibrationPercent NOTIFY calibrationChanged)
    Q_PROPERTY(bool active READ isActive WRITE setActive NOTIFY activeChanged)
    // 有罗盘硬件 (后端可连). false 时界面要退成"空盘 + 手动方位", 不画假指针.
    Q_PROPERTY(bool available READ available CONSTANT)

public:
    explicit CompassSensor(QObject* parent = nullptr);
    ~CompassSensor() override;

    qreal heading() const { return m_heading; }
    bool valid() const { return m_valid; }
    int calibrationPercent() const { return m_calibration; }
    bool isActive() const { return m_compass && m_compass->isActive(); }
    bool available() const { return m_available; }

    void setActive(bool on);

signals:
    void headingChanged();
    void validChanged();
    void calibrationChanged();
    void activeChanged();

private slots:
    void onReadingChanged();

private:
    QCompass* m_compass;
    bool m_available = false;
    qreal m_heading = 0;
    bool m_valid = false;
    int m_calibration = -1;
};

} // namespace outdoor
