/**
 * @file MapService_photos.cpp
 * @brief MapService::photo 相关方法 (2026-09-21 阶段 L5.4 拆分)
 *
 * 从 MapService.cpp 拆出, 包含:
 *   - extractExif
 *   - addPhoto / getAllPhotos / getPhotosByCategory / getPhotosInBounds / getPhotoById
 *   - deletePhoto / updatePhotoNote / updatePhotoSpecies / setPhotoFavorite
 */

#include "MapService.h"
#include "../core/Logger.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"

#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QImageReader>

namespace outdoor {

QVariantMap MapService::extractExif(const QString& imagePath) {
    QVariantMap result;
    QFileInfo info(imagePath);
    if (!info.exists()) {
        result["error"] = "文件不存在";
        return result;
    }

    // 使用 QImageReader 获取基本元数据
    QImageReader reader(imagePath);
    // Qt 6: QImageReader::comment() 已移除,改用 text("Comment")(EXIF/ITPC 注释键名)
    QString comment = reader.text(QStringLiteral("Comment"));
    if (!comment.isEmpty()) {
        result["comment"] = comment;
    }

    // 读取文件修改时间作为拍摄时间（fallback）
    result["fileModified"] = info.lastModified();
    result["fileSize"] = info.size();
    result["fileName"] = info.fileName();

    // 实际 EXIF GPS 提取需要 libexif 或 QExifTool
    // 这里使用文件时间作为 takenAt
    result["takenAt"] = info.lastModified();

    // 简化：标记需要 libexif
    result["gpsAvailable"] = false;
    result["note"] = "EXIF GPS 解析需要 libexif 库（V2 实现）";

    return result;
}

QVariantMap MapService::addPhoto(const QString& imagePath,
                                    const QVariantMap& exifData) {
    QVariantMap result;
    qint64 id = QDateTime::currentMSecsSinceEpoch();

    MapPhoto photo;
    photo.id = id;
    photo.imagePath = imagePath;
    photo.imageThumbPath = imagePath;  // 简化

    if (exifData.contains("lat")) {
        photo.lat = exifData["lat"].toDouble();
    }
    if (exifData.contains("lon")) {
        photo.lon = exifData["lon"].toDouble();
    }
    if (exifData.contains("altitude")) {
        photo.altitude = exifData["altitude"].toDouble();
    }
    if (exifData.contains("takenAt")) {
        photo.takenAt = exifData["takenAt"].toDateTime();
    }
    if (exifData.contains("speciesId")) {
        photo.speciesId = exifData["speciesId"].toString();
    }
    if (exifData.contains("speciesName")) {
        photo.speciesName = exifData["speciesName"].toString();
    }
    if (exifData.contains("speciesCategory")) {
        photo.speciesCategory = exifData["speciesCategory"].toString();
    }
    if (exifData.contains("confidence")) {
        photo.confidence = exifData["confidence"].toDouble();
    }
    if (exifData.contains("speciesSource")) {
        photo.speciesSource = exifData["speciesSource"].toString();
    }
    if (exifData.contains("note")) {
        photo.note = exifData["note"].toString();
    }

    // 验证：必须有 GPS
    if (photo.lat == 0 && photo.lon == 0) {
        result["error"] = "无 GPS 信息";
        return result;
    }

    // 保存到 JSON
    QJsonObject obj;
    obj["id"] = QString::number(id);
    obj["imagePath"] = photo.imagePath;
    obj["imageThumbPath"] = photo.imageThumbPath;
    obj["lat"] = photo.lat;
    obj["lon"] = photo.lon;
    obj["altitude"] = photo.altitude;
    obj["accuracy"] = photo.accuracy;
    obj["takenAt"] = photo.takenAt.toString(Qt::ISODate);
    obj["speciesId"] = photo.speciesId;
    obj["speciesName"] = photo.speciesName;
    obj["speciesCategory"] = photo.speciesCategory;
    obj["speciesSource"] = photo.speciesSource;
    obj["confidence"] = photo.confidence;
    obj["note"] = photo.note;
    obj["isFavorite"] = photo.isFavorite;

    QFile file(m_storagePath + QString("/photo_%1.json").arg(id));
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    } else {
        result["error"] = "无法保存";
        return result;
    }

    result["id"] = id;
    result["lat"] = photo.lat;
    result["lon"] = photo.lon;
    result["altitude"] = photo.altitude;

    emit photoAdded(id);
    emit dataChanged();
    Logger::info(QString("Photo added: %1 at (%2, %3)")
                     .arg(id).arg(photo.lat).arg(photo.lon));
    return result;
}

QVariantList MapService::getAllPhotos() const {
    QVariantList list;
    QDir dir(m_storagePath);
    QStringList files = dir.entryList({"photo_*.json"}, QDir::Files);
    for (const QString& f : files) {
        QFile file(m_storagePath + "/" + f);
        if (!file.open(QIODevice::ReadOnly)) continue;
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (doc.isObject()) {
            QJsonObject obj = doc.object();
            QVariantMap m;
            m["id"] = obj["id"].toVariant().toLongLong();
            m["imagePath"] = obj["imagePath"].toString();
            m["lat"] = obj["lat"].toDouble();
            m["lon"] = obj["lon"].toDouble();
            m["altitude"] = obj["altitude"].toDouble();
            m["speciesId"] = obj["speciesId"].toString();
            m["speciesName"] = obj["speciesName"].toString();
            m["speciesCategory"] = obj["speciesCategory"].toString();
            m["confidence"] = obj["confidence"].toDouble();
            m["speciesSource"] = obj["speciesSource"].toString();
            m["note"] = obj["note"].toString();
            m["takenAt"] = obj["takenAt"].toString();
            list.append(m);
        }
    }
    return list;
}

QVariantList MapService::getPhotosByCategory(const QString& category) {
    QVariantList list;
    auto all = getAllPhotos();
    for (const auto& v : all) {
        if (v.toMap()["speciesCategory"].toString() == category) {
            list.append(v);
        }
    }
    return list;
}

QVariantList MapService::getPhotosInBounds(double minLat, double maxLat,
                                              double minLon, double maxLon) {
    QVariantList list;
    auto all = getAllPhotos();
    for (const auto& v : all) {
        QVariantMap m = v.toMap();
        double lat = m["lat"].toDouble();
        double lon = m["lon"].toDouble();
        if (lat >= minLat && lat <= maxLat &&
            lon >= minLon && lon <= maxLon) {
            list.append(m);
        }
    }
    return list;
}

QVariantMap MapService::getPhotoById(qint64 id) {  // 2026-09-20: rename
    QFile file(m_storagePath + QString("/photo_%1.json").arg(id));
    if (!file.open(QIODevice::ReadOnly)) return {};
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isObject()) return {};
    return doc.object().toVariantMap();
}

// 2026-09-21: 阶段 L3.4 - 写操作切 Result<bool>
QVariantMap MapService::deletePhoto(qint64 id) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::deletePhoto";

    QFile file(m_storagePath + QString("/photo_%1.json").arg(id));
    if (!file.exists()) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("照片不存在 id=%1").arg(id), ctx));
    }
    if (!file.remove()) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("文件删除失败"), ctx));
    }
    emit photoDeleted(id);
    emit dataChanged();
    return toQVariant(Ok(true));
}

QVariantMap MapService::updatePhotoNote(qint64 id, const QString& note) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::updatePhotoNote";

    auto photo = getPhotoById(id);  // 2026-09-20: rename
    if (photo.isEmpty()) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("照片不存在 id=%1").arg(id), ctx));
    }
    photo["note"] = note;

    QFile file(m_storagePath + QString("/photo_%1.json").arg(id));
    if (!file.open(QIODevice::WriteOnly)) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("文件打开失败"), ctx));
    }
    file.write(QJsonDocument(QJsonObject::fromVariantMap(photo))
                    .toJson(QJsonDocument::Indented));
    file.close();

    emit photoUpdated(id);
    return toQVariant(Ok(true));
}

QVariantMap MapService::updatePhotoSpecies(qint64 id, const QString& speciesId,
                                              const QString& speciesName,
                                              const QString& category) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::updatePhotoSpecies";

    auto photo = getPhotoById(id);  // 2026-09-20: rename
    if (photo.isEmpty()) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("照片不存在 id=%1").arg(id), ctx));
    }
    photo["speciesId"] = speciesId;
    photo["speciesName"] = speciesName;
    photo["speciesCategory"] = category;

    QFile file(m_storagePath + QString("/photo_%1.json").arg(id));
    if (!file.open(QIODevice::WriteOnly)) {
        return toQVariant(Err<bool>(ServiceErrorCode::IoError,
                                      QStringLiteral("文件打开失败"), ctx));
    }
    file.write(QJsonDocument(QJsonObject::fromVariantMap(photo))
                    .toJson(QJsonDocument::Indented));
    file.close();

    emit photoUpdated(id);
    return toQVariant(Ok(true));
}

QVariantMap MapService::setPhotoFavorite(qint64 id, bool favorite) {
    using namespace outdoor::internal;
    const char* ctx = "MapService::setPhotoFavorite";

    auto photo = getPhotoById(id);  // 2026-09-20: rename
    if (photo.isEmpty()) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("照片不存在 id=%1").arg(id), ctx));
    }
    photo["isFavorite"] = favorite;

    QFile file(m_storagePath + QString("/photo_%1.json").arg(id));
    if (!file.open(QIODevice::WriteOnly)) {
        return fail(ServiceErrorCode::IoError,
                    QStringLiteral("写入失败: %1").arg(file.errorString()), ctx);
    }
    file.write(QJsonDocument(QJsonObject::fromVariantMap(photo))
                    .toJson(QJsonDocument::Indented));
    file.close();

    emit photoUpdated(id);
    return okVoid();
}

} // namespace outdoor
