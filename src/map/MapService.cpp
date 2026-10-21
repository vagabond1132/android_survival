/**
 * @file MapService.cpp
 */

#include "MapService.h"
#include "../core/Logger.h"
#include "../core/PathService.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"  // 2026-09-21: Phase 5 创建返回 id 切 Result

#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QXmlStreamReader>
#include <QXmlStreamWriter>
#include <QUuid>
#include <QDateTime>
#include <QTextStream>
#include <cmath>
#include <algorithm>

// EXIF
#include <QImageReader>
#include <QImage>
#include <QBuffer>
#include <QFileInfo>
#include <QDir>

namespace outdoor {

// 简易 EXIF 解析（使用 Qt + libexif 思路）
// 实际可使用 libexif 库，但为减少依赖，用简化的 GPS 标签解析
class SimpleExifParser {
public:
    struct GpsData {
        double lat = 0;
        double lon = 0;
        double altitude = 0;
        QDateTime datetime;
        bool valid = false;
    };

    static GpsData parse(const QString& imagePath) {
        GpsData data;
        QFile file(imagePath);
        if (!file.open(QIODevice::ReadOnly)) {
            return data;
        }

        QByteArray content = file.readAll();
        file.close();

        // 查找 EXIF 标记
        int exifOffset = findExifOffset(content);
        if (exifOffset < 0) {
            // 尝试用 QImage 读取基础 EXIF
            QImageReader reader(imagePath);
            reader.setAutoTransform(true);
            // Qt 不直接暴露 EXIF，需用 libexif
            // 这里返回空数据
            return data;
        }

        // 简化：假设 EXIF 数据存在
        // 实际生产应使用 libexif
        return data;
    }

private:
    static int findExifOffset(const QByteArray& data) {
        // EXIF 标记在 JPEG 的 APP1 段
        for (int i = 0; i < data.size() - 1; ++i) {
            if ((quint8)data[i] == 0xFF && (quint8)data[i+1] == 0xE1) {
                return i;
            }
        }
        return -1;
    }
};

MapService::MapService(QObject* parent)
    : ServiceBase("MapService", parent) {  // 2026-09-21 阶段 L2 (无 db)
}

MapService::~MapService() {
}

bool MapService::initialize() {
    // 2026-09-10: 用 PathService 统一解析
    m_storagePath = PathService::mapDir();

    // 加载天地图 Key（从配置）
    // m_tianMapKey = Config::instance().getString("tianmap.key", "");

    if (!ensureSchema()) {
        Logger::error("MapService: failed to ensure schema");
        return false;
    }

    Logger::info("MapService initialized");
    return true;
}

bool MapService::ensureSchema() {
    QDir().mkpath(m_storagePath);
    QString schemaPath = m_storagePath + "/schema.json";
    QFile file(schemaPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append)) {
        return true;  // 不强制要求
    }
    file.close();
    return true;
}

int MapService::photoCount() const {
    return getAllPhotos().size();
}

int MapService::trackCount() const {
    return getAllTracks().size();
}

void MapService::setCurrentBaseMap(BaseMapType type) {
    if (m_currentBaseMap == type) return;
    m_currentBaseMap = type;
    emit baseMapChanged();
}

void MapService::setCurrentSource(TileSource source) {
    if (m_currentSource == source) return;
    m_currentSource = source;
    emit sourceChanged();
}

QString MapService::getTileUrl(int z, int x, int y) {
    if (m_currentSource == TileSource::TianMap) {
        QString vecUrl = QString(
            "https://t0.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&"
            "VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&"
            "TILEMATRIX=%1&TILEROW=%2&TILECOL=%3&FORMAT=tiles&tk=%4")
            .arg(z).arg(y).arg(x).arg(m_tianMapKey);

        QString imgUrl = QString(
            "https://t0.tianditu.gov.cn/img_w/wmts?SERVICE=WMTS&REQUEST=GetTile&"
            "VERSION=1.0.0&LAYER=img&STYLE=default&TILEMATRIXSET=w&"
            "TILEMATRIX=%1&TILEROW=%2&TILECOL=%3&FORMAT=tiles&tk=%4")
            .arg(z).arg(y).arg(x).arg(m_tianMapKey);

        // 简化返回，实际应返回两层瓦片
        if (m_currentBaseMap == BaseMapType::Satellite) {
            return imgUrl;
        } else {
            return vecUrl;
        }
    }
    return QString();
}

QString MapService::getBaseMapName(BaseMapType type) const {
    switch (type) {
        case BaseMapType::Terrain: return "地形图";
        case BaseMapType::Road: return "路网图";
        case BaseMapType::Satellite: return "卫星图";
    }
    return "未知";
}

// ===== 海拔段位: 全部转发 src/common/AltitudeLevel.h (#18 C3) =====
// 2026-10-21 起这里不再有第二份阈值, 也不再自带颜色.
// 行为变化 (有意): 原来 >=3500 一律封在 L4, 现在 3500-4500=L4 / 4500-5500=L5 / >=5500=L6,
// 与装备侧读法一致, QML 的 CommonOptions.altitudeColor(0..6) 也才拿得到后两档.

AltitudeLevel MapService::getAltitudeLevel(double altitudeM) {
    return AltitudeScale::fromMeters(altitudeM);
}

QString MapService::getAltitudeLevelName(AltitudeLevel level) {
    return AltitudeScale::nameOf(level);
}

double MapService::getAltitudeLevelMin(AltitudeLevel level) {
    return AltitudeScale::minM(level);
}

double MapService::getAltitudeLevelMax(AltitudeLevel level) {
    return AltitudeScale::maxM(level);
}

QString MapService::formatDistance(double meters) {
    if (meters < 1000) return QString::number(meters, 'f', 0) + " m";
    return QString::number(meters / 1000, 'f', 2) + " km";
}

QString MapService::formatDuration(qint64 seconds) {
    int hours = seconds / 3600;
    int minutes = (seconds % 3600) / 60;
    return QString("%1小时%2分钟").arg(hours).arg(minutes);
}

QString MapService::formatElevation(double meters) {
    return QString::number(meters, 'f', 0) + " m";
}

QString MapService::generateId() const {
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

void MapService::recomputeTrackStats(Track& track) {
    Q_UNUSED(track);  // 已在 stopTrack 中实现, 此函数保留为虚函数占位/未来扩展
}

} // namespace outdoor
