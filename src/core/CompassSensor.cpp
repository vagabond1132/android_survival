#include "CompassSensor.h"
#include "Logger.h"

#include <QSensor>

#include <cmath>

namespace outdoor {

CompassSensor::CompassSensor(QObject* parent)
    : QObject(parent)
    , m_compass(new QCompass(this))
{
    // sensorsForType 是 QSensor 的静态函数 (不在 QSensorManager 里, 虽然实现在
    // qsensormanager.cpp). 要在 m_compass 构造之后调 —— QSensor 构造时才会把
    // "QCompass" 这个 type 注册进后端表.
    const QList<QByteArray> ids = QSensor::sensorsForType(QByteArray(QCompass::sensorType));
    m_available = !ids.isEmpty();
    if (!m_available)
        Logger::info(QStringLiteral("CompassSensor: 无罗盘硬件 (可用设备数 0), 方位盘退为空盘"));
    else
        Logger::info(QStringLiteral("CompassSensor: 找到 %1 个罗盘后端, 首个 id=%2")
                         .arg(ids.size()).arg(QString::fromLatin1(ids.first())));

    connect(m_compass, &QSensor::readingChanged, this, &CompassSensor::onReadingChanged);
}

CompassSensor::~CompassSensor()
{
    // QCompass 的 parent 是 this, 随对象析构; 这里只确保传感器停下来
    if (m_compass && m_compass->isActive())
        m_compass->stop();
}

void CompassSensor::setActive(bool on)
{
    if (!m_compass || isActive() == on) return;

    if (on) {
        if (!m_compass->start()) {
            Logger::warn(QStringLiteral("CompassSensor: start() 失败, error=%1")
                             .arg(m_compass->error()));
            m_valid = false;
            emit validChanged();
            emit activeChanged();
            return;
        }
        // 2026-10-26: 真机报"方位数据未变化", 而原来 start 成功这条路一个字都不说.
        Logger::info(QStringLiteral("CompassSensor: start() 成功, 等 readingChanged"));
    } else {
        m_compass->stop();
        m_valid = false;
        m_readingCount = 0;
        emit validChanged();
        Logger::info(QStringLiteral("CompassSensor: 已停止 (本页共收到 %1 帧读数)")
                         .arg(m_readingCount));
    }
    emit activeChanged();
}

void CompassSensor::onReadingChanged()
{
    QCompassReading* reading = m_compass ? m_compass->reading() : nullptr;
    if (!reading) return;

    const qreal az = reading->azimuth();
    const qreal cal = reading->calibrationLevel();

    ++m_readingCount;
    // 首帧只说一次: 这一句能区分"start 成功但后端从不送读数"和"读数一直是 0/NaN",
    //   这两种在界面上长得一模一样 (指针不动), 根因完全不同 (前者是插件/权限,
    //   后者是硬件或校准). release 包 logcat 全空, 只有 stage0.log 说得出这句话.
    if (!m_loggedFirstReading) {
        m_loggedFirstReading = true;
        Logger::info(QStringLiteral("CompassSensor: 首帧 azimuth=%1 calibrationLevel=%2")
                         .arg(az).arg(cal));
    }

    // calibrationLevel: 0..1, 部分后端给 -1 表示不提供
    const int calPct = (cal < 0) ? -1
                                 : qRound(qBound<qreal>(0.0, cal, 1.0) * 100.0);
    if (calPct != m_calibration) {
        m_calibration = calPct;
        emit calibrationChanged();
    }

    if (!std::isfinite(az)) {
        if (m_valid) { m_valid = false; emit validChanged(); }
        // 无效帧要说, 但每 50 帧一次就够 (持续 NaN 时不能刷屏)
        if (m_readingCount % 50 == 1)
            Logger::warn(QStringLiteral("CompassSensor: azimuth 非有限值, 第 %1 帧")
                             .arg(m_readingCount));
        return;
    }

    // 归一到 [0,360): 后端偶尔给 -180..180
    qreal normalized = std::fmod(az, 360.0);
    if (normalized < 0) normalized += 360.0;

    const bool wasValid = m_valid;
    const qreal oldHeading = m_heading;
    m_heading = normalized;
    m_valid = true;
    if (!wasValid) emit validChanged();
    if (m_heading != oldHeading) emit headingChanged();
}

} // namespace outdoor
