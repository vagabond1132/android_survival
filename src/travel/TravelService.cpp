/**
 * @file TravelService.cpp
 */

#include "TravelService.h"
#include "../core/AssetLoader.h"
#include "../core/Logger.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"  // 2026-09-21: Phase 5 写操作切 Result

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSet>
#include <QChar>
#include <algorithm>

namespace outdoor {

TravelService::TravelService(QObject* parent)
    : ServiceBase("TravelService", parent) {  // 2026-09-21 阶段 L2 (无 db)
}

TravelService::~TravelService() {
}

bool TravelService::loadInitialData() {
    return loadFromJson();
}

bool TravelService::loadFromJson() {
    // 之前候选 #2 (相对路径 assets/data/travel.json) 在 Android APK 里 100% 失败, 已删除
    QString err;
    auto doc = AssetLoader::loadJson("travel.json", &err);
    if (!doc) {
        Logger::warn(QString("TravelService: %1").arg(err));
        return false;
    }
    if (!doc->isObject()) {
        Logger::warn("TravelService: travel.json root is not an object");
        return false;
    }

    QJsonArray arr = doc->object()["routes"].toArray();
    int count = 0;
    for (const auto& v : arr) {
        QJsonObject o = v.toObject();
        Travel t;
        t.id = o["id"].toString();
        t.name = o["name"].toString();
        t.province = o["province"].toString();
        t.startCity = o["startCity"].toString();
        t.endCity = o["endCity"].toString();
        t.startName = o["startName"].toString();
        t.endName = o["endName"].toString();
        t.startLat = o["startLat"].toDouble();
        t.startLon = o["startLon"].toDouble();
        t.endLat = o["endLat"].toDouble();
        t.endLon = o["endLon"].toDouble();
        t.distanceKm = o["distanceKm"].toDouble();
        t.days = o["days"].toInt();
        t.driveHours = o["driveHours"].toInt();
        t.roadType = o["roadType"].toString();
        t.maxAltitude = o["maxAltitude"].toInt();
        t.highlights = o["highlights"].toString();
        t.supply = o["supply"].toString();
        t.fuelCostCNY = o["fuelCostCNY"].toInt();
        t.description = o["description"].toString();
        for (const auto& s : o["bestSeason"].toArray()) t.bestSeason << s.toString();
        for (const auto& s : o["tags"].toArray()) t.tags << s.toString();
        m_travels[t.id] = t;
        count++;
    }
    Logger::info(QString("TravelService loaded: %1 routes").arg(count));
    emit dataChanged();
    return count > 0;
}

int TravelService::totalCount() const {
    return m_travels.size();
}

QVariantMap TravelService::getById(const QString& id) {
    QVariantMap result;
    auto it = m_travels.constFind(id);
    if (it == m_travels.constEnd()) return result;
    const Travel& t = it.value();
    result["id"] = t.id;
    result["name"] = t.name;
    result["province"] = t.province;
    result["startCity"] = t.startCity;
    result["endCity"] = t.endCity;
    result["startName"] = t.startName;
    result["endName"] = t.endName;
    result["startLat"] = t.startLat;
    result["startLon"] = t.startLon;
    result["endLat"] = t.endLat;
    result["endLon"] = t.endLon;
    result["distanceKm"] = t.distanceKm;
    result["days"] = t.days;
    result["driveHours"] = t.driveHours;
    result["roadType"] = t.roadType;
    result["maxAltitude"] = t.maxAltitude;
    result["bestSeason"] = t.bestSeason;
    result["highlights"] = t.highlights;
    result["supply"] = t.supply;
    result["fuelCostCNY"] = t.fuelCostCNY;
    result["description"] = t.description;
    result["tags"] = t.tags;
    result["isFavorite"] = t.isFavorite;
    return result;
}

QVariantList TravelService::getAll() {
    QVariantList list;
    for (const auto& t : m_travels) {
        QVariantMap m;
        m["id"] = t.id;
        m["name"] = t.name;
        m["province"] = t.province;
        m["distanceKm"] = t.distanceKm;
        m["days"] = t.days;
        m["startCity"] = t.startCity;
        m["endCity"] = t.endCity;
        m["maxAltitude"] = t.maxAltitude;
        m["tags"] = t.tags;
        list.append(m);
    }
    return list;
}

QVariantList TravelService::search(const QString& keyword) {
    QVariantList list;
    for (const auto& t : m_travels) {
        if (keyword.isEmpty() ||
            t.name.contains(keyword, Qt::CaseInsensitive) ||
            t.province.contains(keyword, Qt::CaseInsensitive) ||
            t.description.contains(keyword, Qt::CaseInsensitive) ||
            t.tags.join(",").contains(keyword, Qt::CaseInsensitive)) {
            QVariantMap m;
            m["id"] = t.id;
            m["name"] = t.name;
            m["province"] = t.province;
            m["distanceKm"] = t.distanceKm;
            m["days"] = t.days;
            list.append(m);
        }
    }
    return list;
}

QVariantList TravelService::getByProvince(const QString& province) {
    QVariantList list;
    for (const auto& t : m_travels) {
        if (t.province.contains(province) || t.province.split("/").contains(province)) {
            QVariantMap m;
            m["id"] = t.id;
            m["name"] = t.name;
            m["province"] = t.province;
            m["distanceKm"] = t.distanceKm;
            m["days"] = t.days;
            list.append(m);
        }
    }
    return list;
}

QVariantList TravelService::getByDaysRange(int minDays, int maxDays) {
    QVariantList list;
    for (const auto& t : m_travels) {
        if (t.days >= minDays && t.days <= maxDays) {
            QVariantMap m;
            m["id"] = t.id;
            m["name"] = t.name;
            m["province"] = t.province;
            m["days"] = t.days;
            m["distanceKm"] = t.distanceKm;
            list.append(m);
        }
    }
    return list;
}

QVariantList TravelService::getByDistanceRange(double minKm, double maxKm) {
    QVariantList list;
    for (const auto& t : m_travels) {
        if (t.distanceKm >= minKm && t.distanceKm <= maxKm) {
            QVariantMap m;
            m["id"] = t.id;
            m["name"] = t.name;
            m["province"] = t.province;
            m["distanceKm"] = t.distanceKm;
            m["days"] = t.days;
            list.append(m);
        }
    }
    return list;
}

QVariantList TravelService::getByMonth(int month) {  // 2026-09-20: rename
    QVariantList list;
    // 2026-09-14: month=0 表示"全部月份", 跳过月份过滤
    if (month < 1 || month > 12) {
        for (const auto& t : m_travels) {
            QVariantMap m;
            m["id"] = t.id;
            m["name"] = t.name;
            m["province"] = t.province;
            m["distanceKm"] = t.distanceKm;
            m["days"] = t.days;
            m["maxAltitude"] = t.maxAltitude;
            m["bestSeason"] = t.bestSeason;
            list.append(m);
        }
        return list;
    }
    const QString token = QString::number(month) + "月";
    for (const auto& t : m_travels) {
        if (t.bestSeason.contains(token)) {
            QVariantMap m;
            m["id"] = t.id;
            m["name"] = t.name;
            m["province"] = t.province;
            m["bestSeason"] = t.bestSeason;
            m["distanceKm"] = t.distanceKm;
            m["days"] = t.days;
            list.append(m);
        }
    }
    return list;
}

// 2026-09-21: Phase 5 批次 3 - getFiltered 返回 Result (TravelListPage 主列表, 高频)
QVariantMap TravelService::getFiltered(const QString& province,
                                      int minDays, int maxDays,
                                      double minKm, double maxKm,
                                      int month) {
    using namespace outdoor::internal;
    QVariantList list;
    const QString monthToken = (month >= 1 && month <= 12)
                                   ? QString::number(month) + "月" : QString();
    for (const auto& t : m_travels) {
        bool provOk = province.isEmpty() || t.province.contains(province) || t.province.split("/").contains(province);
        bool dayOk = (minDays <= 0 && maxDays <= 0) || (t.days >= minDays && t.days <= maxDays);
        bool distOk = (minKm <= 0 && maxKm <= 0) || (t.distanceKm >= minKm && t.distanceKm <= maxKm);
        bool monthOk = monthToken.isEmpty() || t.bestSeason.contains(monthToken);
        if (provOk && dayOk && distOk && monthOk) {
            QVariantMap m;
            m["id"] = t.id;
            m["name"] = t.name;
            m["province"] = t.province;
            // 2026-09-28: 补起终点 / 路面类型. 之前只返 7 个字段, TravelListPage
            //   delegate 要显示 startName/endName/roadType → 列表永远显示
            //   "起点 → 终点 · —" 占位符 (用户报"路线信息不全").
            m["startCity"] = t.startCity;
            m["endCity"] = t.endCity;
            m["startName"] = t.startName;
            m["endName"] = t.endName;
            m["roadType"] = t.roadType;
            m["distanceKm"] = t.distanceKm;
            m["days"] = t.days;
            m["maxAltitude"] = t.maxAltitude;
            m["bestSeason"] = t.bestSeason;
            list.append(m);
        }
    }
    return toQVariant(Ok(list));
}

QVariantMap TravelService::addFavorite(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "TravelService::addFavorite";

    if (!m_travels.contains(id)) {
        return fail(ServiceErrorCode::NotFound,
                    QStringLiteral("自驾游不存在: %1").arg(id), ctx);
    }
    m_travels[id].isFavorite = true;
    emit favoriteChanged(id, true);
    emit dataChanged();
    return okVoid();
}

QVariantMap TravelService::deleteFavorite(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "TravelService::deleteFavorite";

    if (!m_travels.contains(id)) {
        return fail(ServiceErrorCode::NotFound,
                    QStringLiteral("自驾游不存在: %1").arg(id), ctx);
    }
    m_travels[id].isFavorite = false;
    emit favoriteChanged(id, false);
    emit dataChanged();
    return okVoid();
}

bool TravelService::isFavorite(const QString& id) {
    if (!m_travels.contains(id)) return false;
    return m_travels[id].isFavorite;
}

QVariantList TravelService::getFavorites() {
    QVariantList list;
    for (const auto& t : m_travels) {
        if (t.isFavorite) {
            QVariantMap m;
            m["id"] = t.id;
            m["name"] = t.name;
            m["province"] = t.province;
            m["distanceKm"] = t.distanceKm;
            m["days"] = t.days;
            list.append(m);
        }
    }
    return list;
}

// 2026-09-21: 阶段 L3.5 - incrementVisitCount 切 Result<bool>
QVariantMap TravelService::incrementVisitCount(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "TravelService::incrementVisitCount";

    if (!m_travels.contains(id)) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("路线不存在: %1").arg(id), ctx));
    }
    m_travels[id].visitCount++;
    emit dataChanged();
    return toQVariant(Ok(true));
}

QStringList TravelService::getAvailableProvinces() {
    QSet<QString> set;
    for (const auto& t : m_travels) {
        for (const QString& p : t.province.split("/")) {
            if (!p.isEmpty()) set.insert(p);
        }
    }
    QStringList list(set.begin(), set.end());
    std::sort(list.begin(), list.end());
    // 2026-09-14: prepend "全部" 选项, 跟 RouteService 行为一致
    list.prepend(QStringLiteral("全部"));
    return list;
}

QStringList TravelService::getAvailableMonths() {
    QSet<int> set;
    for (const auto& t : m_travels) {
        for (const QString& s : t.bestSeason) {
            QString trimmed = s;
            trimmed.remove(QChar(0x6708));
            bool ok;
            int m = trimmed.toInt(&ok);
            if (ok && m >= 1 && m <= 12) set.insert(m);
        }
    }
    QList<int> ms(set.begin(), set.end());
    std::sort(ms.begin(), ms.end());
    QStringList list;
    list.append(QStringLiteral("全部"));  // 2026-09-14: prepend "全部"
    for (int m : ms) list.append(QString::number(m) + "月");
    return list;
}

} // namespace outdoor
