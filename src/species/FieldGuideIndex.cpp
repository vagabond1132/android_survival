/**
 * @file FieldGuideIndex.cpp
 * @brief 图鉴数据索引实现
 */

#include "FieldGuideIndex.h"
#include "../core/Logger.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QDir>
#include <QSet>

namespace outdoor {

FieldGuideIndex::FieldGuideIndex() = default;

void FieldGuideIndex::clear() {
    m_all.clear();
    m_plants.clear();
    m_animals.clear();
    m_insects.clear();
    m_mushrooms.clear();
    m_idIndex.clear();
}

bool FieldGuideIndex::loadAll(const QString& dataDir) {
    clear();

    // 2026-09-23: 修 双斜杠路径 bug. dataDir 来自 AssetLoader::assetRoot(), 末尾已带 '/',
    //   旧逻辑 dataDir + "/filename.json" 拼出 "data//filename.json" 这种 qrc URL,
    //   QFile::open 在 Qt 6.7 qrc 解析下认不出 (双斜杠当 scheme 终止符处理), 4 个 JSON
    //   全 fail, m_plants/animals/insects/mushrooms 全空 → 动植物图鉴 4 个 kingdom 0 条.
    //   修法: dataDir 已带 '/', 直接拼 filename 即可.
    auto join = [](const QString& base, const QString& name) {
        if (base.isEmpty()) return name;
        return base.endsWith(QLatin1Char('/')) ? base + name : base + QLatin1Char('/') + name;
    };

    bool ok = true;
    ok &= loadPlants(join(dataDir, QStringLiteral("field_guide_plants.json")));
    ok &= loadAnimals(join(dataDir, QStringLiteral("field_guide_animals.json")));
    ok &= loadInsects(join(dataDir, QStringLiteral("field_guide_insects.json")));
    ok &= loadMushrooms(join(dataDir, QStringLiteral("field_guide_mushrooms.json")));

    // 旧 danger_species.json 兼容加载(防止数据丢失)
    // 2026-09-19: dedup 重叠 ID - danger_species.json 与 field_guide_*.json 有 18 个
    //   共享 id (plant_aconitum / insect_aedes / mushroom_amanita_subjunquillea 等).
    //   旧逻辑后加载的 legacy 条目会覆盖 m_idIndex 位置, 但 legacy 条目的 kingdom=""
    //   不匹配 service 端 getById 的 kingdom 过滤, 导致从图鉴进入详情页时
    //   plantService.getById / insectService.getById 等返回 {}, entity 为空,
    //   Section "识别特征" 等字段全空. 修法:legacy id 已在 field_guide 中存在则跳过.
    QString legacy = join(dataDir, QStringLiteral("danger_species.json"));
    if (QFile::exists(legacy)) {
        QFile f(legacy);
        if (f.open(QIODevice::ReadOnly)) {
            QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
            f.close();
            if (doc.isObject()) {
                int legacyLoaded = 0;
                int legacySkipped = 0;
                QSet<QString> existing;
                for (const auto& ex : m_all) existing.insert(ex.id);
                for (const auto& v : doc.object()["species"].toArray()) {
                    FieldGuideEntity e = parseEntity(v.toObject().toVariantMap(), "", "");
                    if (existing.contains(e.id)) {
                        ++legacySkipped;
                        continue;
                    }
                    existing.insert(e.id);
                    if (e.kingdom == "plantae") m_plants.append(e);
                    else if (e.kingdom == "animalia") m_animals.append(e);
                    else if (e.kingdom == "insecta") m_insects.append(e);
                    else if (e.kingdom == "fungi") m_mushrooms.append(e);
                    m_all.append(e);
                    ++legacyLoaded;
                }
                Logger::info(QString("FieldGuideIndex legacy: %1 loaded, %2 skipped (shadowed by field_guide)")
                                 .arg(legacyLoaded).arg(legacySkipped));
            }
        }
    }

    rebuildIndices();
    Logger::info(QString("FieldGuideIndex: %1 plants, %2 animals, %3 insects, %4 mushrooms")
                     .arg(m_plants.size()).arg(m_animals.size())
                     .arg(m_insects.size()).arg(m_mushrooms.size()));
    return ok;
}

FieldGuideEntity FieldGuideIndex::parseEntity(const QVariantMap& m,
                                                const QString& kingdom,
                                                const QString& defaultCategory) {
    FieldGuideEntity e;
    e.id = m.value("id").toString();
    e.kingdom = m.value("kingdom", kingdom).toString();
    e.commonName = m.value("common_name").toString();
    e.scientificName = m.value("scientific_name").toString();
    e.category = m.value("category", defaultCategory).toString();
    e.dangerLevel = m.value("danger_level", 0).toInt();

    for (const auto& v : m.value("alias").toList()) e.alias << v.toString();
    for (const auto& v : m.value("features").toList()) e.features << v.toString();
    for (const auto& v : m.value("distribution").toList()) e.distribution << v.toString();
    for (const auto& v : m.value("habitats").toList()) e.habitats << v.toString();
    for (const auto& v : m.value("active_months").toList()) e.activeMonths << v.toString();
    for (const auto& v : m.value("symptoms").toList()) e.symptoms << v.toString();

    e.minElevation = m.value("min_elevation", 0).toInt();
    e.maxElevation = m.value("max_elevation", 5000).toInt();
    e.description = m.value("description").toString();
    e.source = m.value("source").toString();
    e.reviewer = m.value("reviewer").toString();
    e.firstAidId = m.value("first_aid_id").toString();
    e.protectionLevel = m.value("protection_level", "无").toString();

    for (const auto& v : m.value("protective_gear").toList()) e.protectiveGear << v.toString();
    // 2026-09-19: 修复图册空数据 — JSON 字段是 "photo_sources" (复数, 含检索词),
    //   旧代码读 "photos" 拿不到 (e.photos 永远空), 导致 QML 端 entity.photoSources
    //   空 → imageFetcher.fetchImages 不被调用 → 图册区"暂无图片".
    for (const auto& v : m.value("photo_sources").toList()) e.photos << v.toString();

    // 植物特有
    for (const auto& v : m.value("edible_part").toList()) e.ediblePart << v.toString();
    for (const auto& v : m.value("edible_months").toList()) e.edibleMonths << v.toString();
    for (const auto& v : m.value("edible_method").toList()) e.edibleMethod << v.toString();
    e.rawEdible = m.value("raw_edible", false).toBool();
    e.mustCook = m.value("must_cook", false).toBool();
    e.taste = m.value("taste").toString();
    e.harvestTips = m.value("harvest_tips").toString();
    e.nutrition = m.value("nutrition").toString();

    // 动物特有
    e.venomType = m.value("venom_type").toString();
    e.venomLocation = m.value("venom_location").toString();
    e.attackDistanceCm = m.value("attack_distance_cm", 0).toInt();
    e.activeTime = m.value("active_time").toString();
    for (const auto& v : m.value("hibernation_months").toList()) e.hibernationMonths << v.toString();

    // 蘑菇特有
    e.poisoningType = m.value("poisoning_type").toString();
    e.latencyHours = m.value("latency_hours", 0).toInt();
    e.mortalityRate = m.value("mortality_rate").toString();

    // 易混种
    // 2026-10-08: 保留 name/fatality, 且不再丢弃无 id 的"外部提及"项
    //   (旧代码 if(!lid.isEmpty()) 直接跳过, 导致这类参考物种整条消失).
    for (const auto& v : m.value("look_alike").toList()) {
        QVariantMap la = v.toMap();
        FieldGuideLookAlike item;
        item.id = la.value("id").toString();
        item.name = la.value("name").toString();
        item.distinction = la.value("distinction").toString();
        item.fatality = la.value("fatality").toString();
        // 全空项无展示价值, 跳过; 有任一字段则保留
        if (!item.id.isEmpty() || !item.name.isEmpty()
            || !item.distinction.isEmpty() || !item.fatality.isEmpty()) {
            e.lookAlike.append(item);
        }
    }

    // 急救联动
    QVariantMap fa = m.value("first_aid_links").toMap();
    e.firstAidLinks = fa;

    // 路线联动
    for (const auto& v : m.value("route_associations").toList()) {
        QVariantMap ra = v.toMap();
        QString rid = ra.value("route_id").toString();
        QStringList months;
        for (const auto& mv : ra.value("months").toList()) months << mv.toString();
        if (!rid.isEmpty()) e.routeAssociations.append({rid, months});
    }

    // 代表色
    e.representativeColor = m.value("representative_color").toMap();

    // 图片角度
    for (const auto& v : m.value("images").toList()) e.images << v.toString();

    return e;
}

bool FieldGuideIndex::loadPlants(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        Logger::warn(QString("FieldGuide plants not found: %1").arg(path));
        return false;
    }
    QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isObject()) return false;

    for (const auto& v : doc.object()["plants"].toArray()) {
        FieldGuideEntity e = parseEntity(v.toObject().toVariantMap(), "plantae", "wild_vegetable");
        m_plants.append(e);
        m_all.append(e);
    }
    return true;
}

bool FieldGuideIndex::loadAnimals(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        Logger::warn(QString("FieldGuide animals not found: %1").arg(path));
        return false;
    }
    QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isObject()) return false;

    for (const auto& v : doc.object()["animals"].toArray()) {
        FieldGuideEntity e = parseEntity(v.toObject().toVariantMap(), "animalia", "venomous_snake");
        m_animals.append(e);
        m_all.append(e);
    }
    return true;
}

bool FieldGuideIndex::loadInsects(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        Logger::warn(QString("FieldGuide insects not found: %1").arg(path));
        return false;
    }
    QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isObject()) return false;

    for (const auto& v : doc.object()["insects"].toArray()) {
        FieldGuideEntity e = parseEntity(v.toObject().toVariantMap(), "insecta", "tick");
        m_insects.append(e);
        m_all.append(e);
    }
    return true;
}

bool FieldGuideIndex::loadMushrooms(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        Logger::warn(QString("FieldGuide mushrooms not found: %1").arg(path));
        return false;
    }
    QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isObject()) return false;

    for (const auto& v : doc.object()["mushrooms"].toArray()) {
        FieldGuideEntity e = parseEntity(v.toObject().toVariantMap(), "fungi", "deadly_mushroom");
        m_mushrooms.append(e);
        m_all.append(e);
    }
    return true;
}

void FieldGuideIndex::rebuildIndices() {
    m_idIndex.clear();
    for (int i = 0; i < m_all.size(); ++i) {
        m_idIndex.insert(m_all[i].id, i);
    }
}

const FieldGuideEntity* FieldGuideIndex::getById(const QString& id) const {
    auto it = m_idIndex.constFind(id);
    if (it == m_idIndex.constEnd()) return nullptr;
    return &m_all[it.value()];
}

int FieldGuideIndex::dangerousCount() const {
    int n = 0;
    for (const auto& e : m_all) if (e.dangerLevel >= 4) ++n;
    return n;
}

bool FieldGuideIndex::matchProvince(const QStringList& distribution,
                                    const QString& province) {
    if (province.isEmpty() || province == "全部") return true;
    for (const auto& d : distribution) {
        if (d.isEmpty()) continue;
        // "全国" / "全国广布" / "全国(栽培)" 视为遍布全国, 任意省份都命中
        if (d.startsWith("全国")) return true;
        // 包含式: "山东(鲁中)" 命中 "山东"; "河南(豫西伏牛、太行)" 命中 "河南";
        // "河北南部" 命中 "河北"; "陕西/河南/山东" 命中其中任一省份
        if (d.contains(province)) return true;
    }
    return false;
}

// 34 个省级行政区 (不含"全国", 单独处理). 顺序即下拉框展示顺序.
QStringList FieldGuideIndex::canonicalProvinces(const QStringList& distribution) {
    static const QStringList kProvinces = {
        "北京", "天津", "河北", "山西", "内蒙古", "辽宁", "吉林", "黑龙江",
        "上海", "江苏", "浙江", "安徽", "福建", "江西", "山东", "河南",
        "湖北", "湖南", "广东", "广西", "海南", "重庆", "四川", "贵州",
        "云南", "西藏", "陕西", "甘肃", "青海", "宁夏", "新疆", "台湾",
        "香港", "澳门"
    };
    // 用 QSet 记录已命中, 保持 kProvinces 固定顺序 (避免 JSON 里出现顺序影响 UI)
    QSet<QString> hit;
    for (const auto& d : distribution) {
        if (d.isEmpty()) continue;
        for (const auto& p : kProvinces) {
            if (d.contains(p)) hit.insert(p);
        }
    }
    QStringList result;
    for (const auto& p : kProvinces) {
        if (hit.contains(p)) result.append(p);
    }
    return result;
}

QVariantMap FieldGuideIndex::toMap(const FieldGuideEntity& e) {
    // 2026-09-14: 修复 QML 端 "Property 'join' of object QQmlListModel is not a function"
    // QStringList 在 QML 端是 QQmlListModel (有 length 但无 join/filter).
    // QVariantList 在 QML 端是普通 JS Array (有所有数组方法).
    // 把所有 list 字段转 QVariantList 暴露.
    auto toVariantList = [](const QStringList& sl) {
        QVariantList vl;
        for (const auto& s : sl) vl.append(s);
        return vl;
    };

    QVariantMap m;
    m["id"] = e.id;
    m["kingdom"] = e.kingdom;
    m["commonName"] = e.commonName;
    m["scientificName"] = e.scientificName;
    m["alias"] = toVariantList(e.alias);
    m["category"] = e.category;
    m["dangerLevel"] = e.dangerLevel;
    m["features"] = toVariantList(e.features);
    m["distribution"] = toVariantList(e.distribution);
    m["habitats"] = toVariantList(e.habitats);
    m["activeMonths"] = toVariantList(e.activeMonths);
    m["minElevation"] = e.minElevation;
    m["maxElevation"] = e.maxElevation;
    m["description"] = e.description;
    m["source"] = e.source;
    m["reviewer"] = e.reviewer;
    m["firstAidId"] = e.firstAidId;
    m["protectiveGear"] = toVariantList(e.protectiveGear);
    m["photos"] = toVariantList(e.photos);

    // 植物特有
    m["ediblePart"] = toVariantList(e.ediblePart);
    m["edibleMonths"] = toVariantList(e.edibleMonths);
    m["edibleMethod"] = toVariantList(e.edibleMethod);
    m["rawEdible"] = e.rawEdible;
    m["mustCook"] = e.mustCook;
    m["taste"] = e.taste;
    m["harvestTips"] = e.harvestTips;
    m["nutrition"] = e.nutrition;

    // 动物特有
    m["venomType"] = e.venomType;
    m["venomLocation"] = e.venomLocation;
    m["attackDistanceCm"] = e.attackDistanceCm;
    m["activeTime"] = e.activeTime;
    m["hibernationMonths"] = e.hibernationMonths;
    m["protectionLevel"] = e.protectionLevel;
    // 2026-10-20: 上面所有 list 字段都过了 toVariantList, 唯独 symptoms 漏了 ——
    //   QStringList 进 QVariantMap 到 QML 端仍是 QQmlListModel, 详情页 .join("；")
    //   直接 TypeError, 症状那一整块空白.
    m["symptoms"] = toVariantList(e.symptoms);

    // 蘑菇特有
    m["poisoningType"] = e.poisoningType;
    m["latencyHours"] = e.latencyHours;
    m["mortalityRate"] = e.mortalityRate;

    // 易混种 (2026-10-08: 暴露完整字段 id/name/distinction/fatality)
    QVariantList la;
    for (const auto& item : e.lookAlike) {
        QVariantMap lm;
        lm["id"] = item.id;
        lm["name"] = item.name;
        lm["distinction"] = item.distinction;
        lm["fatality"] = item.fatality;
        la.append(lm);
    }
    m["lookAlike"] = la;

    // 急救联动
    m["firstAidLinks"] = e.firstAidLinks;

    // 路线联动
    QVariantList ra;
    for (const auto& p : e.routeAssociations) {
        QVariantMap rm;
        rm["routeId"] = p.first;
        rm["months"] = p.second;
        ra.append(rm);
    }
    m["routeAssociations"] = ra;

    m["representativeColor"] = e.representativeColor;
    m["images"] = e.images;
    // 2026-09-19: 暴露为 photoSources (QML 端 FieldGuideDetailPage._loadPhotos
    //   读 entity.photoSources, 旧暴露名 "photos" 与 QML 不匹配 → 取到空)
    m["photoSources"] = toVariantList(e.photos);
    return m;
}

} // namespace outdoor
