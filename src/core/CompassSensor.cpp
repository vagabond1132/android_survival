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
    } else {
        m_compass->stop();
        m_valid = false;
        emit validChanged();
    }
    emit activeChanged();
}

void CompassSensor::onReadingChanged()
{
    QCompassReading* reading = m_compass ? m_compass->reading() : nullptr;
    if (!reading) return;

    const qreal az = reading->azimuth();
    const qreal cal = reading->calibrationLevel();

    // calibrationLevel: 0..1, 部分后端给 -1 表示不提供
    const int calPct = (cal < 0) ? -1
                                 : qRound(qBound<qreal>(0.0, cal, 1.0) * 100.0);
    if (calPct != m_calibration) {
        m_calibration = calPct;
        emit calibrationChanged();
    }

    if (!std::isfinite(az)) {
        if (m_valid) { m_valid = false; emit validChanged(); }
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
