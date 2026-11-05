/**
 * @file RouteService.cpp
 */

#include "RouteService.h"
#include "../core/AssetLoader.h"
#include "../core/Database.h"
#include "../core/Logger.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"  // 2026-09-21: Phase 5 写操作切 Result
#include "../common/DbHelper.h"  // 2026-09-21: Phase 2 DbHelper 统一 DDL 错误日志

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QChar>
#include <QSqlQuery>
#include <QSqlError>
#include <QFileInfo>
#include <QStandardPaths>
#include <QSet>
#include <algorithm>
#include <cmath>

namespace outdoor {

// 简单 haversine 距离计算
static double haversine(double lat1, double lon1, double lat2, double lon2) {
    constexpr double R = 6371.0;  // km
    double dLat = (lat2 - lat1) * M_PI / 180.0;
    double dLon = (lon2 - lon1) * M_PI / 180.0;
    double a = std::sin(dLat/2) * std::sin(dLat/2) +
               std::cos(lat1 * M_PI/180.0) * std::cos(lat2 * M_PI/180.0) *
               std::sin(dLon/2) * std::sin(dLon/2);
    return 2 * R * std::atan2(std::sqrt(a), std::sqrt(1-a));
}

// 是否向用户推荐(过滤掉明令不推荐的高海拔/极高海拔攀登类)
static bool isRecommended(const Route& r) {
    if (r.notRecommended) return false;
    // 6000m+ 默认不推荐(非观景/非成熟徒步),除非类型为「休闲徒步/休闲登山」
    if (r.maxAltitudeM >= 6000) {
        const QString t = r.type;
        if (!(t == "休闲徒步" || t == "休闲登山")) return false;
    }
    return true;
}

// routes.json 的端点对象 → QGeoCoordinate。
// (0,0) 与显式 coord_unavailable 都算「坐标不可用」—— 全站就是这个约定(MapPage
// _validCoord、CommonOptions::isValidWgs84、searchPlaces), 端点被判定不可信时
// 数据侧只删 lat/lon、保留名称与地址, 读到这里必须还原成 invalid coordinate,
// 不能造一个 QGeoCoordinate(0.0, 0.0)(那是合法的几内亚湾坐标)。
static QGeoCoordinate readEndpoint(const QJsonObject& ep, bool* unavailable) {
    const bool off = ep.value("coord_unavailable").toBool(false);
    const double lat = ep.value("lat").toDouble(0.0);
    const double lon = ep.value("lon").toDouble(0.0);
    const bool usable = !off && !(lat == 0.0 && lon == 0.0);
    if (unavailable) *unavailable = !usable;
    return usable ? QGeoCoordinate(lat, lon) : QGeoCoordinate();
}

RouteService::RouteService(Database* db, QObject* parent)
    
    : ServiceBase(db, "RouteService", parent) {
}

RouteService::~RouteService() {
}

bool RouteService::loadInitialData() {
    if (!ensureSchema()) return false;
    bool ok = loadFromJson();
    // 性能优化:数据加载后立即建索引(一次 O(n),后续查询 O(1) 或 O(log n))
    rebuildIndex();
    return ok;
}

bool RouteService::ensureSchema() {
    if (!m_db || !m_db->isOpen(Database::Name::Routes)) return false;

    QSqlDatabase db = m_db->get(Database::Name::Routes);
    QSqlQuery q(db);

    // 2026-09-21: Phase 2 - 改用 DbHelper::execDdl, 失败自动 log + 返回 false
    // 之前 11 次裸 q.exec(...) 后无条件 return true, 出错静默吞.
    int failed = 0;
    const char* tag = "RouteService::ensureSchema";

    if (!DbHelper::execDdl(q, R"(
        CREATE TABLE IF NOT EXISTS routes (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            alias TEXT,
            province TEXT,
            province_code TEXT,
            city TEXT,
            area TEXT,
            mountain TEXT,
            difficulty INTEGER,
            type TEXT,
            distance_km REAL,
            duration_hours REAL,
            days_needed INTEGER,
            elevation_gain_m INTEGER,
            elevation_loss_m INTEGER,
            max_altitude_m INTEGER,
            min_altitude_m INTEGER,
            best_season TEXT,
            terrain TEXT,
            highlights TEXT,
            description TEXT,
            source TEXT,
            source_url TEXT,
            local_track_path TEXT,
            permit_required INTEGER DEFAULT 0,
            permit_info TEXT,
            rescue_phone TEXT,
            trailhead_lat REAL,
            trailhead_lon REAL,
            trailend_lat REAL,
            trailend_lon REAL,
            coord_precision_m INTEGER DEFAULT 0,
            coord_source TEXT,
            tags TEXT,
            author TEXT,
            visit_count INTEGER DEFAULT 0,
            associated_species TEXT,
            created_at TEXT,
            updated_at TEXT,
            user_imported INTEGER DEFAULT 0
        )
    )", tag)) ++failed;

    // 兼容旧库:补列 (CREATE/ALTER 都走 DbHelper)
    // 2026-09-24: 仅当缺列时才 ALTER, 否则每次启动必撞 "duplicate column name"
    // 2026-10-27 #131: 同一套「查列→缺则 ALTER」写到第三遍了(associated_species +
    // 两个坐标可信度列), 改成一次 PRAGMA 收齐列名再按缺项补。空列名集同时是
    // "PRAGMA 没跑成" 的哨兵 —— 那时跳过 ALTER, 而不是把缺列判断建立在空集上。
    {
        QSet<QString> cols;
        QSqlQuery info(db);
        if (info.exec("PRAGMA table_info(routes)")) {
            while (info.next()) cols.insert(info.value(1).toString());
        }
        if (cols.isEmpty()) {
            Logger::warn("RouteService::ensureSchema: PRAGMA table_info(routes) 无结果, 跳过补列");
        } else {
            struct { const char* name; const char* ddl; } addCols[] = {
                {"associated_species",  "ALTER TABLE routes ADD COLUMN associated_species TEXT"},
                {"coord_precision_m",   "ALTER TABLE routes ADD COLUMN coord_precision_m INTEGER DEFAULT 0"},
                {"coord_source",        "ALTER TABLE routes ADD COLUMN coord_source TEXT"},
            };
            for (const auto& c : addCols) {
                if (!cols.contains(QLatin1String(c.name))) {
                    DbHelper::execDdl(q, QString::fromLatin1(c.ddl), tag);
                }
            }
        }
    }

    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_route_province ON routes(province_code)", tag)) ++failed;
    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_route_difficulty ON routes(difficulty)", tag)) ++failed;
    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_route_mountain ON routes(mountain)", tag)) ++failed;
    if (!DbHelper::execDdl(q, "CREATE INDEX IF NOT EXISTS idx_route_user ON routes(user_imported)", tag)) ++failed;

    if (!DbHelper::execDdl(q, R"(
        CREATE TABLE IF NOT EXISTS route_favorites (
            route_id TEXT NOT NULL,
            user_id TEXT DEFAULT 'default',
            favorited_at TEXT,
            PRIMARY KEY (route_id, user_id)
        )
    )", tag)) ++failed;

    if (!DbHelper::execDdl(q, R"(
        CREATE TABLE IF NOT EXISTS waypoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            route_id TEXT NOT NULL,
            name TEXT,
            type TEXT,
            lat REAL,
            lon REAL,
            elevation INTEGER,
            sequence INTEGER,
            description TEXT,
            FOREIGN KEY (route_id) REFERENCES routes(id) ON DELETE CASCADE
        )
    )", tag)) ++failed;

    if (!DbHelper::execDdl(q, R"(
        CREATE TABLE IF NOT EXISTS dangers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            route_id TEXT NOT NULL,
            type TEXT,
            severity TEXT,
            description TEXT,
            locations TEXT,
            season TEXT,
            countermeasure TEXT,
            FOREIGN KEY (route_id) REFERENCES routes(id) ON DELETE CASCADE
        )
    )", tag)) ++failed;

    return failed == 0;
}

bool RouteService::loadFromJson() {
    QString err;
    auto doc = AssetLoader::loadJson("routes.json", &err);
    if (!doc) {
        Logger::warn(QString("RouteService: %1").arg(err));
        return false;
    }
    if (!doc->isObject()) {
        Logger::warn("RouteService: routes.json root is not an object");
        return false;
    }

    QJsonArray arr = doc->object()["routes"].toArray();
    int count = 0;
    for (const auto& v : arr) {
        QJsonObject o = v.toObject();
        Route r;
        r.id = o["id"].toString();
        r.name = o["name"].toString();
        r.province = o["province"].toString();
        r.provinceCode = o["province_code"].toString();
        r.city = o["city"].toString();
        r.area = o["area"].toString();
        r.mountain = o["mountain"].toString();
        r.difficulty = o["difficulty"].toInt();
        r.type = o["type"].toString();
        r.distanceKm = o["distance_km"].toDouble();
        r.durationHours = o["duration_hours"].toDouble();
        r.daysNeeded = o["days_needed"].toInt();
        r.elevationGainM = o["elevation_gain_m"].toInt();
        r.elevationLossM = o["elevation_loss_m"].toInt();
        r.maxAltitudeM = o["max_altitude_m"].toInt();
        r.minAltitudeM = o["min_altitude_m"].toInt();
        r.highlights = o["highlights"].toString();
        r.description = o["description"].toString();
        r.source = "built_in";
        r.permitRequired = o["permit_required"].toBool();
        r.permitInfo = o["permit_info"].toString();
        r.rescuePhone = o["rescue_phone"].toString();
        r.author = o["author"].toString();
        r.notRecommended = o["not_recommended"].toBool(false);
        r.notRecommendedReason = o["not_recommended_reason"].toString();

        QJsonObject th = o["trailhead"].toObject();
        r.trailhead = readEndpoint(th, &r.trailheadCoordUnavailable);
        r.trailheadName = th["name"].toString();
        r.trailheadAddress = th["address"].toString();

        QJsonObject te = o["trailend"].toObject();
        r.trailend = readEndpoint(te, &r.trailendCoordUnavailable);
        r.trailendName = te["name"].toString();
        r.trailendAddress = te["address"].toString();
        r.coordPrecisionM = o["coord_precision_m"].toInt(0);
        r.coordSource = o["coord_source"].toString();

        for (const auto& s : o["alias"].toArray()) r.alias << s.toString();
        for (const auto& s : o["best_season"].toArray()) r.bestSeason << s.toString();
        for (const auto& s : o["terrain"].toArray()) r.terrain << s.toString();
        for (const auto& s : o["tags"].toArray()) r.tags << s.toString();
        r.routeNature = o["route_nature"].toString(QStringLiteral("穿越"));
        r.isWild = o["is_wild"].toBool(false);
        r.hasPermit = o["has_permit"].toBool(r.permitRequired);
        r.score = o["score"].toInt(0);
        // routes.json 里这一项写成驼峰 "scoreDetail" 且是对象, 而本文件其余字段一律
        // 读下划线键 —— 原来那句 o["score_detail"].toString() 两重都落空: 键不存在,
        // 而且 QJsonValue::toString() 对对象返回空串. 结果 entity.scoreDetail 全站恒为
        // 空, 详情页拿不到 11 项分项 (海拔/路况/水源/蛇虫/补给...).
        // 两种拼法都收, 对象先序列化再存, 与 associatedSpeciesJson 同一口径.
        const QJsonValue sd = o.contains("score_detail") ? o.value("score_detail")
                                                         : o.value("scoreDetail");
        r.scoreDetail = sd.isObject()
                ? QString::fromUtf8(QJsonDocument(sd.toObject()).toJson(QJsonDocument::Compact))
                : sd.toString();
        if (o.contains("associated_species")) {
            r.associatedSpeciesJson = QString(QJsonDocument(o["associated_species"].toObject()).toJson(QJsonDocument::Compact));
        }

        // 2026-09-24: 先入库再入内存. 之前先写 m_routes 会导致 insertRoute 内
        // routeExists() (查内存) 提前 return, 那条 INSERT 从不执行.
        if (insertRoute(r)) count++;
        // 实测轨迹(2026-10-27 #131): waypoints 表此前只建不写 —— getWaypoints() 是
        // 全工程唯一的 polyline 通道, 于是 749 条路线一律退化成 MapPage 里
        // approx:true 的起终点直线. 现在 routes.json 带 "waypoints" 数组的条目
        // 在装载时灌进去, 顺序按数组下标(sequence), 读取侧 getWaypoints 不动.
        const QJsonArray wps = o["waypoints"].toArray();
        if (!wps.isEmpty()) seedWaypoints(r.id, wps);
        m_routes[r.id] = r;
    }

    Logger::info(QString("RouteService loaded: %1 routes").arg(count));
    emit dataChanged();
    return count > 0;
}

int RouteService::seedWaypoints(const QString& routeId, const QJsonArray& points) {
    if (!m_db || !m_db->isOpen(Database::Name::Routes)) return 0;

    QSqlDatabase db = m_db->get(Database::Name::Routes);
    if (!db.transaction()) {
        Logger::warn(QString("RouteService::seedWaypoints: 开事务失败 (%1)").arg(db.lastError().text()));
        return 0;
    }

    int written = 0;
    QSqlQuery q(db);
    // 整批替换: 库里可能有这批路线的旧行(改点/改名后的残留), 先按 route_id 清空.
    if (DbHelper::execDmlPositional(q, "DELETE FROM waypoints WHERE route_id = ?",
                                     {routeId}, "RouteService::seedWaypoints.clear")
        != DmlResult::Ok) {
        db.rollback();
        return 0;
    }
    QSqlQuery ins(db);
    for (int i = 0; i < points.size(); ++i) {
        const QJsonObject p = points[i].toObject();
        const double lat = p["lat"].toDouble();
        const double lon = p["lon"].toDouble();
        if (lat == 0.0 && lon == 0.0) continue;  // (0,0) 不是路径点, 不入库
        ins.prepare("INSERT INTO waypoints (route_id, name, type, lat, lon, elevation, sequence, description)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
        ins.bindValue(0, routeId);
        ins.bindValue(1, p["name"].toString());
        ins.bindValue(2, p["type"].toString());
        ins.bindValue(3, lat);
        ins.bindValue(4, lon);
        ins.bindValue(5, p["elevation"].toInt());
        ins.bindValue(6, i);
        ins.bindValue(7, p["description"].toString());
        if (!ins.exec()) {
            Logger::warn(QString("RouteService::seedWaypoints %1 #%2: %3")
                             .arg(routeId).arg(i).arg(ins.lastError().text()));
            db.rollback();
            return 0;
        }
        ++written;
    }
    if (!db.commit()) {
        Logger::warn(QString("RouteService::seedWaypoints %1: 提交失败 (%2)").arg(routeId).arg(db.lastError().text()));
        db.rollback();
        return 0;
    }
    return written;
}

bool RouteService::insertRoute(const Route& route) {
    if (!m_db || !m_db->isOpen(Database::Name::Routes)) return false;
    if (routeExists(route.id)) return true;  // 已存在

    // 2026-09-21 阶段 L2.2: 切 DbHelper::execDmlPositional
    QString aliasJson = QJsonDocument(QJsonArray::fromStringList(route.alias))
                            .toJson(QJsonDocument::Compact);
    QString seasonJson = QJsonDocument(QJsonArray::fromStringList(route.bestSeason))
                            .toJson(QJsonDocument::Compact);
    QString terrainJson = QJsonDocument(QJsonArray::fromStringList(route.terrain))
                            .toJson(QJsonDocument::Compact);
    QString tagsJson = QJsonDocument(QJsonArray::fromStringList(route.tags))
                            .toJson(QJsonDocument::Compact);
    QString assocJson = route.associatedSpeciesJson;

    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::Routes);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        R"(
        INSERT OR REPLACE INTO routes (
            id, name, alias, province, province_code, city, area, mountain,
            difficulty, type, distance_km, duration_hours, days_needed,
            elevation_gain_m, elevation_loss_m, max_altitude_m, min_altitude_m,
            best_season, terrain, highlights, description, source,
            permit_required, permit_info, rescue_phone,
            trailhead_lat, trailhead_lon, trailend_lat, trailend_lon,
            coord_precision_m, coord_source,
            tags, author, associated_species, created_at, updated_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?,
            ?, ?, ?, ?,
            ?, ?, ?, ?, ?,
            ?, ?, ?,
            ?, ?, ?, ?,
            ?, ?,
            ?, ?, ?, ?, ?
        )
    )",
        {route.id, route.name, aliasJson, route.province, route.provinceCode,
         route.city, route.area, route.mountain,
         route.difficulty, route.type, route.distanceKm, route.durationHours,
         route.daysNeeded,
         route.elevationGainM, route.elevationLossM, route.maxAltitudeM, route.minAltitudeM,
         seasonJson, terrainJson, route.highlights, route.description, route.source,
         route.permitRequired ? 1 : 0, route.permitInfo, route.rescuePhone,
         route.trailhead.isValid() ? route.trailhead.latitude() : 0.0,
         route.trailhead.isValid() ? route.trailhead.longitude() : 0.0,
         route.trailend.isValid() ? route.trailend.latitude() : 0.0,
         route.trailend.isValid() ? route.trailend.longitude() : 0.0,
         route.coordPrecisionM, route.coordSource,
         tagsJson, route.author, assocJson,
         QDateTime::currentDateTime().toString(Qt::ISODate),
         QDateTime::currentDateTime().toString(Qt::ISODate)},
        "RouteService::insertRoute");
    return rc == DmlResult::Ok;
}

int RouteService::totalCount() const {
    return m_routes.size();
}

int RouteService::favoriteCount() const {
    return getFavorites().size();
}

// 2026-09-21: 阶段 L3.1 - saveRoute 返回 Result<QString> (value=routeId)
QVariantMap RouteService::saveRoute(const Route& route) {
    using namespace outdoor::internal;
    const char* ctx = "RouteService::saveRoute";

    if (auto e = dbOpenCheck(m_db, Database::Name::Routes, ctx)) return *e;
    if (auto e = requireNonEmpty(route.id, "这条路线的编号", ctx)) return *e;

    if (insertRoute(route)) {
        m_routes[route.id] = route;
        emit routeAdded(route.id);
        emit dataChanged();
        return toQVariant(Ok(route.id));
    }
    return toQVariant(Err<QString>(ServiceErrorCode::DbError,
                                     QStringLiteral("insertRoute 失败"), ctx));
}

QVariantMap RouteService::updateRoute(const QString& id, const Route& route) {
    using namespace outdoor::internal;
    const char* ctx = "RouteService::updateRoute";

    if (auto e = dbOpenCheck(m_db, Database::Name::Routes, ctx)) return *e;

    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::Routes);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        R"(
        UPDATE routes SET
            name=?, difficulty=?, distance_km=?, duration_hours=?,
            elevation_gain_m=?, description=?, highlights=?, updated_at=?
        WHERE id=?
    )",
        {route.name, route.difficulty, route.distanceKm, route.durationHours,
         route.elevationGainM, route.description, route.highlights,
         QDateTime::currentDateTime().toString(Qt::ISODate), id},
        ctx);
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }

    m_routes[id] = route;
    emit routeUpdated(id);
    emit dataChanged();
    return toQVariant(Ok(true));
}

QVariantMap RouteService::deleteRoute(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "RouteService::deleteRoute";

    if (auto e = dbOpenCheck(m_db, Database::Name::Routes, ctx)) return *e;

    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::Routes);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        "DELETE FROM routes WHERE id = ?", {id}, ctx);
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }

    m_routes.remove(id);
    emit routeDeleted(id);
    emit dataChanged();
    return toQVariant(Ok(true));
}

bool RouteService::routeExists(const QString& id) {
    return m_routes.contains(id);
}

QVariantMap RouteService::getById(const QString& id) {
    QVariantMap result;
    auto it = m_routes.constFind(id);
    if (it == m_routes.constEnd()) return result;

    const Route& r = it.value();
    result["id"] = r.id;
    result["name"] = r.name;
    result["alias"] = r.alias;
    result["province"] = r.province;
    result["city"] = r.city;
    result["area"] = r.area;
    result["mountain"] = r.mountain;
    result["difficulty"] = r.difficulty;
    result["type"] = r.type;
    result["distanceKm"] = r.distanceKm;
    result["durationHours"] = r.durationHours;
    result["daysNeeded"] = r.daysNeeded;
    result["elevationGainM"] = r.elevationGainM;
    result["elevationLossM"] = r.elevationLossM;
    result["maxAltitudeM"] = r.maxAltitudeM;
    result["minAltitudeM"] = r.minAltitudeM;
    result["bestSeason"] = r.bestSeason;
    result["terrain"] = r.terrain;
    result["highlights"] = r.highlights;
    result["description"] = r.description;
    result["permitRequired"] = r.permitRequired;
    result["permitInfo"] = r.permitInfo;
    result["rescuePhone"] = r.rescuePhone;
    result["isFavorite"] = isFavorite(r.id);
    result["notRecommended"] = r.notRecommended;
    result["notRecommendedReason"] = r.notRecommendedReason;
    // 性质与是否野线
    result["routeNature"] = r.routeNature;
    result["isWild"] = r.isWild;
    result["hasPermit"] = r.hasPermit;
    // 综合评分
    result["score"] = r.score;
    result["scoreDetail"] = r.scoreDetail;
    // 起终点信息(便于导航)
    result["trailheadName"] = r.trailheadName;
    result["trailheadAddress"] = r.trailheadAddress;
    result["trailheadLat"] = r.trailhead.isValid() ? r.trailhead.latitude() : 0.0;
    result["trailheadLon"] = r.trailhead.isValid() ? r.trailhead.longitude() : 0.0;
    result["trailendName"] = r.trailendName;
    result["trailendAddress"] = r.trailendAddress;
    result["trailendLat"] = r.trailend.isValid() ? r.trailend.latitude() : 0.0;
    result["trailendLon"] = r.trailend.isValid() ? r.trailend.longitude() : 0.0;
    // 端点坐标可信度(2026-10-27 #131): UI 据此决定能不能把端点当导航目标,
    // 以及读数要写成「±10 米」还是「±56 公里 / 城区中心点」。
    // unavailable 为真时上面四个 lat/lon 恒为 0.0(哨兵), 名称与地址仍然给全 ——
    // 「不知道在哪」要说得出地名, 但绝不能画出一个假点。
    result["trailheadCoordUnavailable"] = r.trailheadCoordUnavailable;
    result["trailendCoordUnavailable"] = r.trailendCoordUnavailable;
    result["coordPrecisionM"] = r.coordPrecisionM;
    result["coordSource"] = r.coordSource;
    result["waypointCount"] = waypointCount(r.id);
    return result;
}

int RouteService::waypointCount(const QString& routeId) {
    if (!m_db || !m_db->isOpen(Database::Name::Routes)) return 0;

    QSqlQuery q(m_db->get(Database::Name::Routes));
    QVariantMap row = DbHelper::selectOne(q,
            "SELECT COUNT(*) AS n FROM waypoints WHERE route_id = ?",
            {routeId}, "RouteService::waypointCount",
            [](const QSqlQuery& q) -> QVariantMap {
                QVariantMap m;
                m["n"] = q.value(0).toInt();
                return m;
            });
    return row.value("n").toInt();
}

QVariantList RouteService::getAll() {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        QVariantMap m;
        m["id"] = r.id;
        m["name"] = r.name;
        m["province"] = r.province;
        m["difficulty"] = r.difficulty;
        m["distanceKm"] = r.distanceKm;
        m["durationHours"] = r.durationHours;
        m["mountain"] = r.mountain;
        list.append(m);
    }
    return list;
}

QVariantList RouteService::getByProvince(const QString& province) {
    QVariantList list;
    if (province.isEmpty()) return getAll();
    // 性能优化:用省份索引(平均 O(1) 查询而非 O(n) 扫描)
    const QStringList& ids = m_provinceIndex.value(province);
    for (const QString& id : ids) {
        auto it = m_routes.constFind(id);
        if (it == m_routes.constEnd()) continue;
        const Route& r = it.value();
        if (!isRecommended(r)) continue;
        QVariantMap m;
        m["id"] = r.id;
        m["name"] = r.name;
        m["difficulty"] = r.difficulty;
        m["distanceKm"] = r.distanceKm;
        list.append(m);
    }
    return list;
}

QVariantList RouteService::getByDifficulty(int minLevel, int maxLevel) {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (r.difficulty >= minLevel && r.difficulty <= maxLevel) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            list.append(m);
        }
    }
    return list;
}

QVariantList RouteService::getByType(const QString& type) {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (r.type == type) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["type"] = r.type;
            m["difficulty"] = r.difficulty;
            list.append(m);
        }
    }
    return list;
}

QVariantList RouteService::getByMountain(const QString& mountain) {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (r.mountain.contains(mountain, Qt::CaseInsensitive)) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["mountain"] = r.mountain;
            m["difficulty"] = r.difficulty;
            list.append(m);
        }
    }
    return list;
}

QVariantList RouteService::getByMonth(int month) {  // 2026-09-20: rename
    QVariantList list;
    // 2026-09-14: month=0 表示"全部月份", 跳过月份过滤
    if (month < 1 || month > 12) {
        for (const auto& r : m_routes) {
            if (!isRecommended(r)) continue;
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            m["bestSeason"] = r.bestSeason;
            list.append(m);
        }
        return list;
    }
    const QString monthToken = QString::number(month) + "月";
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (r.bestSeason.contains(monthToken)) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            m["bestSeason"] = r.bestSeason;
            list.append(m);
        }
    }
    return list;
}

QVariantList RouteService::getByProvinceAndDifficulty(const QString& province,
                                                     int minLevel,
                                                     int maxLevel) {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        bool provinceOk = province.isEmpty() ||
                          r.province == province ||
                          r.provinceCode == province;
        bool difficultyOk = r.difficulty >= minLevel &&
                            r.difficulty <= maxLevel;
        if (provinceOk && difficultyOk) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            list.append(m);
        }
    }
    return list;
}

// 2026-09-21: Phase 5 批次 3 - getFiltered 返回 Result (RouteListPage 主列表, 高频)
QVariantMap RouteService::getFiltered(const QString& province,
                                       int minDifficulty,
                                       int maxDifficulty,
                                       int month) {
    using namespace outdoor::internal;
    QVariantList list;
    const QString monthToken = (month >= 1 && month <= 12)
                                   ? QString::number(month) + "月"
                                   : QString();
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        bool provinceOk = province.isEmpty() ||
                          r.province == province ||
                          r.provinceCode == province;
        bool difficultyOk = r.difficulty >= minDifficulty &&
                            r.difficulty <= maxDifficulty;
        bool seasonOk = monthToken.isEmpty() ||
                        r.bestSeason.contains(monthToken);
        if (provinceOk && difficultyOk && seasonOk) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            m["bestSeason"] = r.bestSeason;
            list.append(m);
        }
    }
    return toQVariant(Ok(list));
}

QVariantList RouteService::getByNature(const QString& nature) {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (nature.isEmpty() || r.routeNature == nature) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            m["routeNature"] = r.routeNature;
            m["isWild"] = r.isWild;
            list.append(m);
        }
    }
    return list;
}

QVariantList RouteService::getByWildness(bool isWild) {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (r.isWild == isWild) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            m["routeNature"] = r.routeNature;
            m["isWild"] = r.isWild;
            list.append(m);
        }
    }
    return list;
}

QVariantList RouteService::getByDaysRange(int minDays, int maxDays) {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (r.daysNeeded >= minDays && r.daysNeeded <= maxDays) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            m["daysNeeded"] = r.daysNeeded;
            list.append(m);
        }
    }
    return list;
}

QVariantList RouteService::getByDistanceRange(double minKm, double maxKm) {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (r.distanceKm >= minKm && r.distanceKm <= maxKm) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            list.append(m);
        }
    }
    return list;
}

QVariantList RouteService::getByAltitudeRange(int minAlt, int maxAlt) {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (r.maxAltitudeM >= minAlt && r.maxAltitudeM <= maxAlt) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            m["maxAltitudeM"] = r.maxAltitudeM;
            list.append(m);
        }
    }
    return list;
}

QVariantList RouteService::getAdvanced(const QString& province,
                                      int minDifficulty,
                                      int maxDifficulty,
                                      int month,
                                      const QString& nature,
                                      bool includeWild,
                                      bool includeScenic,
                                      int minDays,
                                      int maxDays,
                                      double minKm,
                                      double maxKm) {
    QVariantList list;
    const QString monthToken = (month >= 1 && month <= 12)
                                   ? QString::number(month) + "月"
                                   : QString();
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        bool provinceOk = province.isEmpty() ||
                          r.province == province ||
                          r.provinceCode == province;
        bool difficultyOk = (minDifficulty <= 0 || maxDifficulty <= 0) ||
                            (r.difficulty >= minDifficulty && r.difficulty <= maxDifficulty);
        bool seasonOk = monthToken.isEmpty() || r.bestSeason.contains(monthToken);
        bool natureOk = nature.isEmpty() || r.routeNature == nature;
        bool wildOk = (!includeWild && !includeScenic) ||
                      (includeWild && r.isWild) ||
                      (includeScenic && !r.isWild);
        bool daysOk = (minDays <= 0 && maxDays <= 0) ||
                      (r.daysNeeded >= minDays && r.daysNeeded <= maxDays);
        bool distOk = (minKm <= 0 && maxKm <= 0) ||
                      (r.distanceKm >= minKm && r.distanceKm <= maxKm);
        if (provinceOk && difficultyOk && seasonOk && natureOk && wildOk && daysOk && distOk) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            m["daysNeeded"] = r.daysNeeded;
            m["bestSeason"] = r.bestSeason;
            m["routeNature"] = r.routeNature;
            m["isWild"] = r.isWild;
            m["maxAltitudeM"] = r.maxAltitudeM;
            list.append(m);
        }
    }
    return list;
}

QStringList RouteService::getAvailableNatures() {
    QSet<QString> set;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (!r.routeNature.isEmpty()) set.insert(r.routeNature);
    }
    QStringList list(set.begin(), set.end());
    std::sort(list.begin(), list.end());
    return list;
}

QStringList RouteService::getAvailableProvinces() {
    // 2026-09-11 (#34 修): m_provinceSet 之前同时包含中文 province + 拼音缩写
    // provinceCode (SC/JX/SN 等), 导致 UI 下拉框出现 66 项混用.
    // 修: 只返回中文 province (用 QChar::isLetter + Unicode 范围过滤, 排除 2 字母拼音).
    // provinceCode 仍保留在 m_provinceSet/m_provinceIndex 里供内部按 code 查询.
    // 2026-09-21: Phase 4 - 改 QStringList (跟 TravelService 一致).
    QStringList list(m_provinceSet.begin(), m_provinceSet.end());
    std::sort(list.begin(), list.end());
    QStringList result;
    result.append(QStringLiteral("全部"));
    for (const auto& s : list) {
        // 过滤 2 字母全大写拼音 (SC/JX/SN 形式): 长度 ≤ 4 且都是 ASCII 字母
        bool isPinyin = !s.isEmpty() && s.length() <= 4
                         && std::all_of(s.begin(), s.end(),
                             [](QChar c) { return c.isLetter() && c.unicode() < 128; });
        if (!isPinyin) {
            result.append(s);
        }
    }
    return result;
}

QStringList RouteService::getAvailableMonths() {
    // 2026-09-21: Phase 4 - 改 QStringList (跟 TravelService::getAvailableMonths 一致)
    QSet<int> set;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        for (const auto& s : r.bestSeason) {
            // 形如 "5月"
            QString trimmed = s;
            trimmed.remove(QChar(0x6708));  // "月"
            bool ok = false;
            int m = trimmed.toInt(&ok);
            if (ok && m >= 1 && m <= 12) set.insert(m);
        }
    }
    QList<int> ms(set.begin(), set.end());
    std::sort(ms.begin(), ms.end());
    QStringList result;
    result.append(QStringLiteral("全部"));
    for (int m : ms) result.append(QString::number(m) + QStringLiteral("月"));
    return result;
}

QVariantList RouteService::search(const QString& keyword) {
    QVariantList list;
    if (keyword.isEmpty()) return list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (r.name.contains(keyword, Qt::CaseInsensitive) ||
            r.mountain.contains(keyword, Qt::CaseInsensitive) ||
            r.area.contains(keyword, Qt::CaseInsensitive) ||
            r.province.contains(keyword, Qt::CaseInsensitive) ||
            r.description.contains(keyword, Qt::CaseInsensitive)) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["province"] = r.province;
            m["difficulty"] = r.difficulty;
            m["distanceKm"] = r.distanceKm;
            list.append(m);
        }
    }
    return list;
}

// === 地点级检索 ================================================================
namespace {

// 起终点摊平出来的一个 POI 候选.
struct PlaceHit {
    int score = 0;
    QString name;
    QString routeId;
    QString routeName;
    QString side;        // "起点" | "终点"
    QString address;
    QStringList region;  // 省 / 市 / 山 (展示时按非空拼接)
    double lat = 0;
    double lon = 0;
};

// 命中强度: POI 名直接命中 > 路线名或别名命中 > 山/区域/市/省命中.
// 给分而不是布尔, 是为了让"武功山"这种既像 POI 又像山的词把山门排前面.
int placeScore(const QString& kw, const QString& poiName,
               const QStringList& routeNames, const Route& r) {
    if (poiName.contains(kw, Qt::CaseInsensitive)) return 3;
    for (const auto& e : routeNames)
        if (e.contains(kw, Qt::CaseInsensitive)) return 2;
    if (r.mountain.contains(kw, Qt::CaseInsensitive) ||
        r.area.contains(kw, Qt::CaseInsensitive) ||
        r.city.contains(kw, Qt::CaseInsensitive) ||
        r.province.contains(kw, Qt::CaseInsensitive))
        return 1;
    return 0;
}

} // namespace

QVariantList RouteService::searchPlaces(const QString& keyword, int limit) {
    QVariantList list;
    const QString kw = keyword.trimmed();
    if (kw.isEmpty() || limit <= 0) return list;

    QList<PlaceHit> hits;
    for (const auto& r : m_routes) {
        // 不按 isRecommended 过滤: 那是"别去爬这座 6000m+"的产品建议,
        // 不是"这个地方不存在" —— 搜地点时被过滤掉等于地名凭空消失.
        QStringList routeNames;
        routeNames << r.name << r.alias;
        for (int side = 0; side < 2; ++side) {
            const bool isStart = (side == 0);
            const QGeoCoordinate& c = isStart ? r.trailhead : r.trailend;
            const QString& poi = isStart ? r.trailheadName : r.trailendName;
            if (poi.isEmpty()) continue;
            // 没有坐标的端点摊不成 POI。此前用 (0,0) 哨兵判, 现在装载层把
            // "缺坐标/坐标不可信" 一律还原成 invalid coordinate(读出来是
            // 91.0/181.0 而不是 0), 所以按 isValid() 判 —— 两种来源一起覆盖。
            if (!c.isValid()) continue;
            const int score = placeScore(kw, poi, routeNames, r);
            if (score == 0) continue;
            PlaceHit h;
            h.score = score;
            h.name = poi;
            h.routeId = r.id;
            h.routeName = r.name;
            h.side = isStart ? QStringLiteral("起点") : QStringLiteral("终点");
            h.address = isStart ? r.trailheadAddress : r.trailendAddress;
            h.region << r.province << r.city << r.mountain;
            h.lat = c.latitude();
            h.lon = c.longitude();
            hits.append(h);
        }
    }

    std::stable_sort(hits.begin(), hits.end(),
                     [](const PlaceHit& a, const PlaceHit& b) { return a.score > b.score; });

    const int n = std::min(limit, static_cast<int>(hits.size()));
    for (int i = 0; i < n; ++i) {
        const PlaceHit& h = hits.at(i);
        QVariantMap m;
        m["id"] = h.routeId + (h.side == QStringLiteral("起点") ? "#start" : "#end");
        m["name"] = h.name;
        m["routeId"] = h.routeId;
        m["routeName"] = h.routeName;
        m["side"] = h.side;
        m["lat"] = h.lat;
        m["lon"] = h.lon;
        m["address"] = h.address;
        // 同名 POI 在数据里成批出现 (749 条里 189 条起终点同名), 归属路线是唯一的区分线索
        QStringList region;
        for (const QString& s : h.region)
            if (!s.trimmed().isEmpty() && !region.contains(s)) region << s;
        m["region"] = region.join(QStringLiteral(" · "));
        list.append(m);
    }
    return list;
}

QVariantList RouteService::getFavorites() const {
    if (!m_db || !m_db->isOpen(Database::Name::Routes)) return {};

    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList (无 binds)
    QSqlQuery q(m_db->get(Database::Name::Routes));
    auto list = DbHelper::selectList(q,
            "SELECT route_id FROM route_favorites WHERE user_id = 'default' "
            "ORDER BY favorited_at DESC", {},
            "RouteService::getFavorites",
            [this](const QSqlQuery& q) -> QVariantMap {
                QString id = q.value(0).toString();
                auto it = m_routes.constFind(id);
                if (it == m_routes.constEnd()) return {};  // 跳过 (路由已删)
                QVariantMap m;
                m["id"] = it.value().id;
                m["name"] = it.value().name;
                m["difficulty"] = it.value().difficulty;
                m["distanceKm"] = it.value().distanceKm;
                return m;
            });
    // 过滤掉 lambda 返回的空 map (favorites 关联的 route 已删除)
    list.removeAll({});
    return list;
}

QVariantList RouteService::getMostVisited(int limit) {
    if (!m_db || !m_db->isOpen(Database::Name::Routes)) return {};

    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList
    QSqlQuery q(m_db->get(Database::Name::Routes));
    return DbHelper::selectList(q,
            "SELECT id, name, difficulty, distance_km, visit_count "
            "FROM routes WHERE user_imported = 0 "
            "ORDER BY visit_count DESC LIMIT ?",
            {limit},
            "RouteService::getMostVisited",
            [](const QSqlQuery& q) -> QVariantMap {
                QVariantMap m;
                m["id"] = q.value(0).toString();
                m["name"] = q.value(1).toString();
                m["difficulty"] = q.value(2).toInt();
                m["distanceKm"] = q.value(3).toDouble();
                m["visitCount"] = q.value(4).toInt();
                return m;
            });
}

QVariantList RouteService::getNearby(double lat, double lon, double radiusKm) {
    QVariantList list;
    for (const auto& r : m_routes) {
        if (!isRecommended(r)) continue;
        if (!r.trailhead.isValid()) continue;

        double dist = haversine(lat, lon,
                                 r.trailhead.latitude(),
                                 r.trailhead.longitude());
        if (dist <= radiusKm) {
            QVariantMap m;
            m["id"] = r.id;
            m["name"] = r.name;
            m["distance"] = dist;
            m["difficulty"] = r.difficulty;
            m["province"] = r.province;
            m["city"] = r.city;
            m["mountain"] = r.mountain;
            m["type"] = r.type;
            // 2026-09-15: 地图联动需要 - 让 QML 选路线后能立即在地图上画线 + 居中
            // 不再需要先 getById 一次
            m["trailheadLat"] = r.trailhead.latitude();
            m["trailheadLon"] = r.trailhead.longitude();
            m["trailheadName"] = r.trailheadName;
            m["trailendLat"] = r.trailend.isValid() ? r.trailend.latitude() : 0.0;
            m["trailendLon"] = r.trailend.isValid() ? r.trailend.longitude() : 0.0;
            m["trailendName"] = r.trailendName;
            m["distanceKm"] = r.distanceKm;
            m["daysNeeded"] = r.daysNeeded;
            m["routeNature"] = r.routeNature;
            m["isWild"] = r.isWild;
            m["notRecommended"] = r.notRecommended;
            m["score"] = r.score;
            list.append(m);
        }
    }
    std::sort(list.begin(), list.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap()["distance"].toDouble() < b.toMap()["distance"].toDouble();
    });
    return list;
}

QVariantMap RouteService::addFavorite(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "RouteService::addFavorite";

    if (auto e = dbOpenCheck(m_db, Database::Name::Routes, ctx)) return *e;
    if (!m_routes.contains(id)) {
        Logger::warn(QString("%1: 路线目录里没有这条: %2").arg(ctx, id));
        return fail(ServiceErrorCode::NotFound,
                    QStringLiteral("这条路线在目录里没有"), ctx);
    }

    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::Routes);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        "INSERT OR REPLACE INTO route_favorites (route_id, user_id, favorited_at) "
        "VALUES (?, 'default', ?)",
        {id, QDateTime::currentDateTime().toString(Qt::ISODate)},
        "RouteService::addFavorite");
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }

    emit favoriteChanged(id, true);
    emit dataChanged();
    return okVoid();
}

QVariantMap RouteService::deleteFavorite(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "RouteService::deleteFavorite";

    if (auto e = dbOpenCheck(m_db, Database::Name::Routes, ctx)) return *e;

    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::Routes);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        "DELETE FROM route_favorites WHERE route_id = ? AND user_id = 'default'",
        {id},
        "RouteService::deleteFavorite");
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }

    emit favoriteChanged(id, false);
    emit dataChanged();
    return okVoid();
}

bool RouteService::isFavorite(const QString& id) {
    if (!m_db || !m_db->isOpen(Database::Name::Routes)) return false;

    // 2026-09-21 阶段 L2.2: 切 DbHelper::execSelectPositional
    QSqlQuery q(m_db->get(Database::Name::Routes));
    if (!DbHelper::execSelectPositional(q,
            "SELECT 1 FROM route_favorites WHERE route_id = ? AND user_id = 'default'",
            {id},
            "RouteService::isFavorite")) return false;
    return q.next();
}

// 2026-09-21: 阶段 L3.5 - incrementVisitCount 切 Result<bool>
QVariantMap RouteService::incrementVisitCount(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "RouteService::incrementVisitCount";

    if (auto e = dbOpenCheck(m_db, Database::Name::Routes, ctx)) return *e;

    // 2026-09-21 阶段 L2.2: DbHelper::execDmlPositional 需 QSqlQuery lvalue, 提取本地变量
    QSqlDatabase db = m_db->get(Database::Name::Routes);
    QSqlQuery q(db);
    auto rc = DbHelper::execDmlPositional(q,
        "UPDATE routes SET visit_count = visit_count + 1 WHERE id = ?",
        {id},
        ctx);
    if (rc != DmlResult::Ok) {
        return dbErr(rc, db, ctx);
    }
    return toQVariant(Ok(true));
}

QVariantList RouteService::getWaypoints(const QString& routeId) {
    if (!m_db || !m_db->isOpen(Database::Name::Routes)) return {};

    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList
    QSqlQuery q(m_db->get(Database::Name::Routes));
    return DbHelper::selectList(q,
            "SELECT name, type, lat, lon, elevation, description "
            "FROM waypoints WHERE route_id = ? ORDER BY sequence",
            {routeId},
            "RouteService::getWaypoints",
            [](const QSqlQuery& q) -> QVariantMap {
                QVariantMap m;
                m["name"] = q.value(0).toString();
                m["type"] = q.value(1).toString();
                m["lat"] = q.value(2).toDouble();
                m["lon"] = q.value(3).toDouble();
                m["elevation"] = q.value(4).toInt();
                m["description"] = q.value(5).toString();
                return m;
            });
}

QVariantList RouteService::getDangers(const QString& routeId) {
    if (!m_db || !m_db->isOpen(Database::Name::Routes)) return {};

    // 2026-09-21 阶段 L4.x: 切 DbHelper::selectList
    QSqlQuery q(m_db->get(Database::Name::Routes));
    return DbHelper::selectList(q,
            "SELECT type, severity, description, locations, countermeasure "
            "FROM dangers WHERE route_id = ?",
            {routeId},
            "RouteService::getDangers",
            [](const QSqlQuery& q) -> QVariantMap {
                QVariantMap m;
                m["type"] = q.value(0).toString();
                m["severity"] = q.value(1).toString();
                m["description"] = q.value(2).toString();
                m["locations"] = q.value(3).toString();
                m["countermeasure"] = q.value(4).toString();
                return m;
            });
}

QVariantMap RouteService::getAssociatedSpecies(const QString& routeId) {
    QVariantMap result;
    if (!m_db || !m_db->isOpen(Database::Name::Routes)) return result;

    // 2026-09-21 阶段 L2.2: 切 DbHelper::execSelectPositional
    QSqlQuery q(m_db->get(Database::Name::Routes));
    if (DbHelper::execSelectPositional(q,
            "SELECT associated_species FROM routes WHERE id = ?",
            {routeId},
            "RouteService::getAssociatedSpecies")
        && q.next()) {
        QString json = q.value(0).toString();
        if (!json.isEmpty()) {
            QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
            if (doc.isObject()) {
                QJsonObject obj = doc.object();
                result["province"] = obj.value("province").toString();
                result["plants"] = obj.value("plants").toVariant().toStringList();
                result["animals"] = obj.value("animals").toVariant().toStringList();
                result["insects"] = obj.value("insects").toVariant().toStringList();
                result["mushrooms"] = obj.value("mushrooms").toVariant().toStringList();
            }
        }
    }
    return result;
}

QVariantList RouteService::recommend(int limit) {
    // 简单推荐：按访问次数
    return getMostVisited(limit);
}

void RouteService::rebuildIndex() {
    m_provinceIndex.clear();
    m_provinceSet.clear();
    m_monthIndex.clear();
    m_routeIdSet.clear();
    m_difficultyBucket.clear();
    m_indexBuilt = false;

    for (const auto& r : m_routes) {
        // 1. 路线 id 索引(O(1) 查重)
        m_routeIdSet.insert(r.id);
        // 2. 省份索引(支持省份名/省份代码)
        if (!r.province.isEmpty()) {
            m_provinceIndex[r.province] << r.id;
            m_provinceSet.insert(r.province);
        }
        if (!r.provinceCode.isEmpty()) {
            m_provinceIndex[r.provinceCode] << r.id;
            m_provinceSet.insert(r.provinceCode);
        }
        // 3. 月份索引(每条路线出现在其所有适宜月份)
        for (const QString& s : r.bestSeason) {
            QString trimmed = s;
            trimmed.remove(QChar(0x6708));  // 移除 "月"
            bool ok;
            int m = trimmed.toInt(&ok);
            if (ok && m >= 1 && m <= 12) {
                m_monthIndex[m] << r.id;
            }
        }
        // 4. 难度分桶
        m_difficultyBucket[r.name + QString::number(r.difficulty)] = 0;  // placeholder
        (void)m_difficultyBucket;  // 暂未使用,保留
    }
    m_indexBuilt = true;
    Logger::info(QString("RouteService index built: %1 routes, %2 provinces, %3 months")
                 .arg(m_routes.size())
                 .arg(m_provinceSet.size())
                 .arg(m_monthIndex.size()));
}

} // namespace outdoor
