/**
 * @file EquipmentService.cpp
 */

#include "EquipmentService.h"
#include "../core/AssetLoader.h"
#include "../core/Logger.h"
#include "../core/PathService.h"
#include "../core/Result.h"
#include "../core/ServiceErrors.h"
#include "../core/internal/QmlResultBridge.h"  // 2026-09-21: Phase 5 写操作切 Result
#include "../common/SettingsStore.h"  // 2026-09-21: 阶段 L5.1 QSettings 封装
#include "RuleConditionFactory.h"  // 2026-09-21: Phase 3 接入 Strategy 工厂

#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QDir>
#include <QDateTime>
#include <QUuid>
#include <QCoreApplication>
#include <QSet>
#include <QJsonParseError>
#include <QRegularExpression>  // 2026-09-23: 复合条件 "X AND Y" 拆分
#include <algorithm>

namespace outdoor {

EquipmentService::EquipmentService(QObject* parent)
    : ServiceBase("EquipmentService", parent) {  // 2026-09-21 阶段 L2 (无 db)
}

EquipmentService::~EquipmentService() {
}

bool EquipmentService::initialize() {
    // 2026-09-10: 用 PathService 统一解析, 不再各自 QStandardPaths
    m_storagePath = PathService::equipmentDir();

    // 2026-09-21: Phase 3 - 注册 6 个内置策略到 Factory (一次性, 全局)
    RuleConditionFactory::initializeDefaults();

    if (!loadItems()) {
        Logger::error("Failed to load equipment items");
        return false;
    }

    if (!loadRules()) {
        Logger::error("Failed to load equipment rules");
        return false;
    }

    // 加载偏好
    int count = SettingsStore::beginReadArray("preferences");
    for (int i = 0; i < count; ++i) {
        SettingsStore::setArrayIndex(i);
        UserPreference pref;
        pref.id = SettingsStore::getString("id");
        pref.equipmentId = SettingsStore::getString("equipmentId");
        pref.action = SettingsStore::getString("action");
        pref.condition = SettingsStore::getString("condition");
        pref.confidence = SettingsStore::getInt("confidence");
        pref.useCount = SettingsStore::getInt("useCount");
        m_preferences.append(pref);
    }
    SettingsStore::endArray();

    Logger::info(QString("EquipmentService initialized: %1 items, %2 rules, %3 prefs")
                     .arg(m_items.size())
                     .arg(m_rules.size())
                     .arg(m_preferences.size()));
    emit dataChanged();
    return true;
}

// 2026-09-17: 用户自定义装备 - 存在 QSettings, 区别于 base JSON 只读库
// 命名空间: user_items/<id> = {id, name, category, weightG, isCritical, isUser: true}
// 2026-09-21: Phase 5 - 写操作切 Result
QVariantMap EquipmentService::addUserItem(const QString& name, const QString& category,
                                         int weightG, bool isCritical) {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::addUserItem";

    if (auto e = requireNonBlank(name, "装备名称", ctx)) return *e;
    if (weightG < 0) {
        return fail(ServiceErrorCode::InvalidArgument,
                    QStringLiteral("重量不能为负"), ctx);
    }

    QString id = "user_" + QString::number(QDateTime::currentMSecsSinceEpoch());
    SettingsStore::beginGroup("user_items");
    SettingsStore::beginGroup(id);
    SettingsStore::setValue("id", id);
    SettingsStore::setValue("name", name);
    SettingsStore::setValue("category", category);
    SettingsStore::setValue("weightG", weightG);
    SettingsStore::setValue("isCritical", isCritical);
    SettingsStore::endGroup();
    SettingsStore::endGroup();
    return saveUserItemsAndEmit(ctx);
}

QVariantMap EquipmentService::deleteUserItem(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::deleteUserItem";

    if (id.isEmpty() || !id.startsWith("user_")) {
        return fail(ServiceErrorCode::InvalidArgument,
                    QStringLiteral("只能删除用户装备 (id 必须 user_ 开头), 收到: %1").arg(id), ctx);
    }
    SettingsStore::beginGroup("user_items");
    SettingsStore::remove(id);
    SettingsStore::endGroup();
    return saveUserItemsAndEmit(ctx);
}

// 2026-09-20: 编辑 user item. id 必须以 user_ 开头 (只让 user item 可改, 基础库 JSON 不可改)
// 至少有一个字段非空才更新, name 不允许清空.
QVariantMap EquipmentService::updateUserItem(const QString& id, const QString& name,
                                             const QString& category, int weightG,
                                             bool isCritical) {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::updateUserItem";

    if (id.isEmpty() || !id.startsWith("user_")) {
        return fail(ServiceErrorCode::InvalidArgument,
                    QStringLiteral("只能编辑用户装备 (id 必须 user_ 开头), 收到: %1").arg(id), ctx);
    }
    if (auto e = requireNonBlank(name, "装备名称", ctx)) return *e;
    if (weightG < 0) {
        return fail(ServiceErrorCode::InvalidArgument,
                    QStringLiteral("重量不能为负"), ctx);
    }

    SettingsStore::beginGroup("user_items");
    if (!SettingsStore::childGroups().contains(id)) {
        SettingsStore::endGroup();
        return fail(ServiceErrorCode::NotFound,
                    QStringLiteral("用户装备不存在: %1").arg(id), ctx);
    }
    SettingsStore::beginGroup(id);
    SettingsStore::setValue("name", name);
    SettingsStore::setValue("category", category);
    SettingsStore::setValue("weightG", weightG);
    SettingsStore::setValue("isCritical", isCritical);
    SettingsStore::endGroup();
    SettingsStore::endGroup();
    return saveUserItemsAndEmit(ctx);
}

QVariantList EquipmentService::getUserItems() {
    QVariantList list;
    SettingsStore::beginGroup("user_items");
    for (const QString& id : SettingsStore::childGroups()) {
        SettingsStore::beginGroup(id);
        QVariantMap m;
        m["id"] = id;
        m["name"] = SettingsStore::getString("name");
        m["category"] = SettingsStore::getString("category");
        m["weightG"] = SettingsStore::getInt("weightG");
        m["isCritical"] = SettingsStore::getBool("isCritical");
        m["isUser"] = true;  // 标记 QML 端能区分
        list.append(m);
        SettingsStore::endGroup();
    }
    SettingsStore::endGroup();
    return list;
}

bool EquipmentService::loadItems() {
    // 之前 applicationDirPath() 候选在 Android 永远失败, 已删除
    QString err;
    auto doc = AssetLoader::loadJson("equipment_base.json", &err);
    if (!doc) {
        Logger::error(QString("EquipmentService: loadItems: %1").arg(err));
        return false;
    }
    if (!doc->isObject()) {
        Logger::error("EquipmentService: equipment_base.json root is not an object");
        return false;
    }

    QJsonArray items = doc->object()["items"].toArray();
    for (const auto& v : items) {
        QJsonObject o = v.toObject();
        EquipmentItem item;
        item.id = o["id"].toString();
        item.name = o["name"].toString();
        item.category = o["category"].toString();
        item.weightG = o["weight_g"].toInt();
        item.description = o["description"].toString();
        item.isCritical = o["is_critical"].toBool();
        item.isOTC = o["otc"].toBool();
        item.specs = o["specs"].toObject();
        m_items[item.id] = item;
    }
    return !m_items.isEmpty();
}

bool EquipmentService::loadRules() {
    QString err;
    auto doc = AssetLoader::loadJson("equipment_rules.json", &err);
    if (!doc) {
        Logger::error(QString("EquipmentService: loadRules: %1").arg(err));
        return false;
    }
    if (!doc->isObject()) {
        Logger::error("EquipmentService: equipment_rules.json root is not an object");
        return false;
    }

    m_rules = doc->object()["rules"].toArray();
    if (m_rules.isEmpty()) {
        Logger::warn("EquipmentService: equipment_rules.json has empty rules array");
    }
    return !m_rules.isEmpty();
}

int EquipmentService::totalItems() const { return m_items.size(); }
int EquipmentService::totalRules() const { return m_rules.size(); }

EquipmentAltitudeLevel EquipmentService::getAltitudeLevel(int altitudeM) {
    // 阈值唯一来源: src/common/AltitudeLevel.h (#18 C3)
    return AltitudeScale::fromMeters(static_cast<double>(altitudeM));
}

QString EquipmentService::getAltitudeLevelName(EquipmentAltitudeLevel level) {
    return AltitudeScale::nameOf(level);
}

// 2026-10-21 (#18 C3): 这里原来还有 getAltitudeLevelName / getAltitudeLevelColor 两份
//   switch. 名称转发到 AltitudeScale::nameOf; **颜色函数整个删掉** —— 它返回的是改版前
//   的 Material 老色 (#4CAF50 / #9C27B0 / #212121), 与 #E8ECEA 底不搭, 而 QML 侧早就改拿
//   CommonOptions.altitudeColor(level) 了 (EquipmentPage.qml:941/971). 色源只留 CommonOptions 一处.

// 2026-09-23: 数值 → 等级换算 (QML 只给 windSpeed / uvIndex 时用)
WindLevel EquipmentService::windLevelFromSpeed(float speedMs) {
    if (speedMs < 0.3f) return WindLevel::Calm;
    if (speedMs < 3.4f) return WindLevel::Light;
    if (speedMs < 8.0f) return WindLevel::Moderate;
    if (speedMs < 10.8f) return WindLevel::Strong;
    return WindLevel::Gale;
}

UVLevel EquipmentService::uvLevelFromIndex(float index) {
    if (index < 3.0f) return UVLevel::Weak;
    if (index < 6.0f) return UVLevel::Moderate;
    if (index < 8.0f) return UVLevel::Strong;
    if (index < 11.0f) return UVLevel::VeryStrong;
    return UVLevel::Extreme;
}

QJsonObject EquipmentService::getAltitudeSegment(EquipmentAltitudeLevel level) {
    QJsonObject seg;
    seg["level"] = static_cast<int>(level);
    seg["name"] = getAltitudeLevelName(level);
    // 2026-10-21 (#18 C3): 原来这里塞了 seg["color"] = 老 Material 十六进制.
    //   色不进数据层: 界面按 level 取 CommonOptions.altitudeColor(level).
    return seg;
}

QVariantList EquipmentService::getAllItems() {
    QVariantList list;
    for (const auto& item : m_items) {
        QVariantMap m;
        m["id"] = item.id;
        m["name"] = item.name;
        m["category"] = item.category;
        m["weightG"] = item.weightG;
        m["isCritical"] = item.isCritical;
        m["isOTC"] = item.isOTC;
        m["description"] = item.description;
        list.append(m);
    }
    return list;
}

QVariantList EquipmentService::getItemsByCategory(const QString& category) {
    QVariantList list;
    for (const auto& item : m_items) {
        if (item.category == category) {
            QVariantMap m;
            m["id"] = item.id;
            m["name"] = item.name;
            m["weightG"] = item.weightG;
            m["isCritical"] = item.isCritical;
            list.append(m);
        }
    }
    return list;
}

QVariantMap EquipmentService::getById(const QString& id) {  // 2026-09-20: rename
    QVariantMap result;
    auto it = m_items.constFind(id);
    if (it == m_items.constEnd()) return result;

    const auto& item = it.value();
    result["id"] = item.id;
    result["name"] = item.name;
    result["category"] = item.category;
    result["weightG"] = item.weightG;
    result["description"] = item.description;
    result["isCritical"] = item.isCritical;
    result["isOTC"] = item.isOTC;
    return result;
}

QVariantList EquipmentService::getCriticalItems() {
    QVariantList list;
    for (const auto& item : m_items) {
        if (item.isCritical) {
            QVariantMap m;
            m["id"] = item.id;
            m["name"] = item.name;
            list.append(m);
        }
    }
    return list;
}

QList<RecommendedItem> EquipmentService::applyRules(
    const TripParameters& params,
    const QHash<QString, EquipmentItem>& items) {

    // 2026-10-21 修复 (用户报"必带/强必带不随环境条件变化"):
    //   原来这里是 `addedIds` 去重 + 首条命中即定档 —— 一条 item 只要被前面某条规则
    //   收走, 后面所有命中它的规则**整条作废**, 既不提档也不留理由。
    //   现在改成: 同一 item 的多条命中规则全部累加理由, 优先级取**最高**那一档。
    //   注意实测边界 (扫过 18 组环境参数, _scratch_debug/gear_rules_20261021):
    //   当前 equipment_rules.json 里 16 个被多条规则覆盖的 item, 覆盖它们的规则**档位
    //   全相同**, 所以这个修复今天只让"推荐理由"栏从 1 条变多条, 桶数量一个没动 ——
    //   必带/强必带不随季节/降水/风/湿度变化是规则数据本身没在这个档位写这些条件
    //   (39 条: 11 critical / 4 important / 24 recommended; important 里 3 条还是
    //   always), 属于数据问题, 不在此函数职责内。
    QList<RecommendedItem> result;
    QHash<QString, int> indexOf;   // itemId -> result 下标 (保持首次出现的顺序, 可复现)

    for (const auto& ruleV : m_rules) {
        QJsonObject rule = ruleV.toObject();
        QString condition = rule["condition"].toString();
        // 2026-09-19: 规则 JSON priority 是 "critical"/"important"/"recommended"/"optional"
        //   字符串, 之前 .toInt() 永远返回 0, 全部进了 Optional 桶.
        QString prioStr = rule["priority"].toString();
        Priority priority = Priority::Optional;
        if (prioStr == "critical") priority = Priority::Critical;
        else if (prioStr == "important") priority = Priority::Important;
        else if (prioStr == "recommended") priority = Priority::Recommended;
        QString ruleName = rule["name"].toString();

        // 检查条件
        bool matched = false;
        if (condition == "always") {
            matched = true;
        } else {
            matched = matchCondition(condition, params) == "true";
        }

        if (!matched) continue;

        // 应用规则
        QJsonArray ruleItems = rule["items"].toArray();
        for (const auto& iv : ruleItems) {
            QString itemId = iv.toString();
            auto it = items.constFind(itemId);
            if (it == items.constEnd()) continue;

            const auto pos = indexOf.constFind(itemId);
            if (pos == indexOf.constEnd()) {
                RecommendedItem rec;
                rec.item = it.value();
                rec.priority = priority;
                rec.reasons << ruleName;
                rec.sourceRule = rule["id"].toString();
                indexOf.insert(itemId, result.size());
                result.append(rec);
                continue;
            }
            RecommendedItem& rec = result[pos.value()];
            if (!rec.reasons.contains(ruleName)) rec.reasons << ruleName;
            if (priority > rec.priority) {
                rec.priority = priority;
                rec.sourceRule = rule["id"].toString();
            }
        }
    }
    return result;
}

QString EquipmentService::matchCondition(const QString& conditionStr,
                                          const TripParameters& params) const {
    // 2026-09-21: Phase 3 - 改用 Strategy 模式. Factory 按前缀查策略, 找不到的
    // condition 退回 "false" (与原来 if-else 链全 fail 行为一致).
    // 新增条件只需在 RuleConditionStrategy.h 加子类 + Factory 加一行 register.
    QString cond = conditionStr.trimmed();

    // 2026-09-23 修复: json 里有复合条件 "altitude >= L4 AND season in [...]",
    //   之前前缀取到 "altitude" 后整串交给 AltitudeCondition, 与正则不符 → 恒 false,
    //   5 条 AND 规则全灭. 现按 " AND " (大小写不敏感) 拆成多个原子条件, 全部满足
    //   才算匹配.
    const QStringList atoms = cond.split(QRegularExpression(QStringLiteral("\\s+AND\\s+"),
                                                             QRegularExpression::CaseInsensitiveOption),
                                          Qt::SkipEmptyParts);
    for (const QString& atomRaw : atoms) {
        const QString atom = atomRaw.trimmed();
        if (atom.isEmpty()) continue;

        // 提取前缀: 第一个空格前的小写 token ("altitude" / "precipitation" / ...)
        const int sp = atom.indexOf(' ');
        const QString prefix = (sp < 0 ? atom : atom.left(sp)).toLower();

        auto strat = RuleConditionFactory::create(prefix);
        if (!strat) {
            Logger::warn(QString("EquipmentService::matchCondition: unknown prefix '%1' (cond='%2')")
                             .arg(prefix, cond));
            return QStringLiteral("false");
        }
        // 2026-09-23: phase 前缀用去掉前缀后的剩余段, 策略内部只认 RHS.
        //   传整个 atom 亦可 (各策略都 startsWith(prefix) 校验), 这里传 atom 保持
        //   与单条件路径一致的行为.
        if (!strat->matches(atom, params)) return QStringLiteral("false");
    }
    return QStringLiteral("true");
}

QList<RecommendedItem> EquipmentService::applyPreferences(
    const QList<RecommendedItem>& baseList,
    const TripParameters& params) {

    QList<RecommendedItem> result = baseList;
    QSet<QString> toRemove;

    for (const auto& pref : m_preferences) {
        if (pref.action == "always_skip") {
            // 始终跳过的偏好
            toRemove.insert(pref.equipmentId);
        } else if (pref.action == "remove") {
            // 条件移除: 简化匹配 — 若 condition 为空或匹配当前 params, 则移除
            // (完整 condition 解析待 P2 增强: 解析 JSON altitude/days/difficulty)
            if (pref.condition.isEmpty() ||
                preferenceMatchesParams(pref.condition, params)) {
                toRemove.insert(pref.equipmentId);
            }
        }
        // "add" 偏好待实现: 需 items 仓库查找, 见 removeUserExcluded
    }

    // 移除用户标记为始终跳过的
    result.erase(
        std::remove_if(result.begin(), result.end(),
            [&](const RecommendedItem& r) {
                return toRemove.contains(r.item.id);
            }),
        result.end());

    return result;
}

bool EquipmentService::preferenceMatchesParams(const QString& conditionJson,
                                                 const TripParameters& params) const {
    // 简化匹配: 解析 JSON {"altitudeMin":x,"altitudeMax":y,"daysMin":z,"daysMax":w}
    // params 在范围内则匹配
    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(conditionJson.toUtf8(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        return false;  // 非法 JSON 不匹配, 安全侧
    }
    QJsonObject obj = doc.object();
    if (obj.contains("altitudeMin") && params.altitudeMax < obj["altitudeMin"].toInt()) {
        return false;
    }
    if (obj.contains("altitudeMax") && params.altitudeMin > obj["altitudeMax"].toInt()) {
        return false;
    }
    if (obj.contains("daysMin") && params.days < obj["daysMin"].toInt()) {
        return false;
    }
    if (obj.contains("daysMax") && params.days > obj["daysMax"].toInt()) {
        return false;
    }
    return true;
}

QList<RecommendedItem> EquipmentService::removeUserExcluded(
    const QList<RecommendedItem>& list,
    const QHash<QString, EquipmentItem>& items) {
    Q_UNUSED(items);  // 参数保留供未来按 items 校验 equipmentId, 当前只用 list 即可完成过滤
    // 用户偏好里 action="remove" 的 equipmentId 对应的 RecommendedItem 从 list 移除
    // (applyPreferences 已处理 always_skip + 条件 remove, 这里兜底处理未匹配条件的强制 remove)
    QSet<QString> excludeIds;
    for (const auto& pref : m_preferences) {
        if (pref.action == "always_skip" || pref.action == "remove") {
            excludeIds.insert(pref.equipmentId);
        }
    }
    // items 仓库用于校验 equipmentId 存在(可选, 当前只做基础过滤)
    QList<RecommendedItem> result;
    result.reserve(list.size());
    for (const auto& r : list) {
        if (!excludeIds.contains(r.item.id)) {
            result.append(r);
        }
    }
    return result;
}

int EquipmentService::calculateTotalWeight(
    const QList<RecommendedItem>& items) {
    int total = 0;
    for (const auto& r : items) {
        total += r.item.weightG;
    }
    return total;
}

QString EquipmentService::generateListId() const {
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

// 2026-09-21 阶段 L3 重构: 抽 syncToQVariant + emit 公共块
QVariantMap EquipmentService::saveUserItemsAndEmit(const QString& ctx) {
    using namespace outdoor::internal;
    auto rc = syncToQVariant(SettingsStore::sync(), ctx);
    if (!isOk(rc)) return rc;
    emit dataChanged();
    return okVoid();
}

QVariantMap EquipmentService::generateList(const QString& name,
                                            const QVariantMap& paramsMap) {
    TripParameters params;
    params.altitudeMax = paramsMap.value("altitudeMax", 0).toInt();
    params.altitudeMin = paramsMap.value("altitudeMin", 0).toInt();
    params.altitudeCamp = paramsMap.value("altitudeCamp", 0).toInt();
    if (params.altitudeCamp == 0) params.altitudeCamp = params.altitudeMin;
    if (params.altitudeMin == 0) params.altitudeMin = params.altitudeMax;
    params.days = paramsMap.value("days", 1).toInt();
    params.people = paramsMap.value("people", 1).toInt();
    params.difficulty = paramsMap.value("difficulty", 1).toInt();
    params.season = static_cast<Season>(paramsMap.value("season", 1).toInt());
    params.tempAvg = paramsMap.value("tempAvg", 20.0f).toFloat();
    params.tempMin = paramsMap.value("tempMin", 10.0f).toFloat();
    params.windSpeed = paramsMap.value("windSpeed", 0.0f).toFloat();
    params.precipitation = static_cast<Precipitation>(
        paramsMap.value("precipitation", 0).toInt());
    params.uvIndex = paramsMap.value("uvIndex", 5.0f).toFloat();

    // 2026-09-23 修复: 之前只读 13 个字段, 地区气候维度的 8 个参数
    //   (diurnalRange/humidity/uvLevel/windLevel/isRainySeason/isCoastal/
    //    isDesert/isPlateau) 从未从 paramsMap 读出 → 永远用 struct 默认值 →
    //   json 里依赖这些维度的规则全部恒定匹配/不匹配。
    params.diurnalRange = paramsMap.value("diurnalRange", params.diurnalRange).toInt();
    params.humidity = static_cast<HumidityType>(
        paramsMap.value("humidity", static_cast<int>(params.humidity)).toInt());
    params.isRainySeason = paramsMap.value("isRainySeason", params.isRainySeason).toBool();
    params.isSnowySeason = paramsMap.value("isSnowySeason", params.isSnowySeason).toBool();
    params.isCoastal = paramsMap.value("isCoastal", params.isCoastal).toBool();
    params.isDesert = paramsMap.value("isDesert", params.isDesert).toBool();
    params.isPlateau = paramsMap.value("isPlateau", params.isPlateau).toBool();

    // windLevel / uvLevel 有对应的数值参数 (windSpeed / uvIndex), QML 未显式给等级
    // 时按标准换算, 否则 wind_level / uv_level 类规则在现有表单下永远不触发。
    if (paramsMap.contains("windLevel")) {
        params.windLevel = static_cast<WindLevel>(paramsMap.value("windLevel").toInt());
    } else {
        params.windLevel = windLevelFromSpeed(params.windSpeed);
    }
    if (paramsMap.contains("uvLevel")) {
        params.uvLevel = static_cast<UVLevel>(paramsMap.value("uvLevel").toInt());
    } else {
        params.uvLevel = uvLevelFromIndex(params.uvIndex);
    }
    // is_plateau 同上: 无显式输入时按海拔推断 (>= 2500m 视为高原)
    if (!paramsMap.contains("isPlateau")) {
        params.isPlateau = params.altitudeMax >= 2500;
    }

    // 应用规则
    QList<RecommendedItem> recommended = applyRules(params, m_items);

    // 应用偏好
    recommended = applyPreferences(recommended, params);

    // 2026-09-23: 修 - 之前 39 条规则只有 critical/important/recommended, Optional
    //   桶永远空, 用户报"生成清单 可选数据为空, 没有根据资料库信息关联".
    //   兜底: 把基础库里**没被任何规则选中** 的 item 全标 Optional (带 reasons
    //   "未触发规则,可按需携带"). 这样装备库所有条目都能在 UI 看到, 用户
    //   可勾选升级为强装. 排除用户已标记 remove 的.
    {
        QSet<QString> selectedIds;
        for (const auto& r : recommended) selectedIds.insert(r.item.id);
        for (auto it = m_items.constBegin(); it != m_items.constEnd(); ++it) {
            if (selectedIds.contains(it.key())) continue;
            RecommendedItem rec;
            rec.item = it.value();
            rec.priority = Priority::Optional;
            rec.reasons << QStringLiteral("基础库兜底,按需携带");
            rec.sourceRule = QStringLiteral("_base_fallback");
            recommended.append(rec);
        }
        // 再过一遍 preferences (可能用户标记过某些 base item 为 remove)
        recommended = removeUserExcluded(recommended, m_items);
    }

    // 分类
    EquipmentList list;
    list.id = generateListId();
    list.name = name;
    list.params = params;
    list.createdAt = QDateTime::currentDateTime();

    for (const auto& rec : recommended) {
        switch (rec.priority) {
            case Priority::Critical:
                list.critical.append(rec);
                break;
            case Priority::Important:
                list.important.append(rec);
                break;
            case Priority::Recommended:
                list.recommended.append(rec);
                break;
            case Priority::Optional:
                list.optional.append(rec);
                break;
        }
    }

    // 计算总重
    list.totalWeightG = calculateTotalWeight(recommended);

    // 保存
    saveListToStorage(list);

    // 返回 QVariantMap
    QVariantMap result;
    result["id"] = list.id;
    result["name"] = list.name;
    result["altitudeLevel"] = static_cast<int>(
        getAltitudeLevel(params.altitudeMax));
    result["altitudeLevelName"] = getAltitudeLevelName(
        getAltitudeLevel(params.altitudeMax));
    result["totalWeightG"] = list.totalWeightG;
    result["critical"] = QVariant::fromValue(list.critical);
    result["important"] = QVariant::fromValue(list.important);
    result["recommended"] = QVariant::fromValue(list.recommended);
    result["optional"] = QVariant::fromValue(list.optional);

    emit listGenerated(list.id);
    Logger::info(QString("Generated list %1: %2 critical, %3 important, %4 recommended, %5 optional")
                     .arg(list.id)
                     .arg(list.critical.size())
                     .arg(list.important.size())
                     .arg(list.recommended.size())
                     .arg(list.optional.size()));
    return result;
}

void EquipmentService::saveListToStorage(const EquipmentList& list) {
    QFile file(m_storagePath + "/" + list.id + ".json");
    if (!file.open(QIODevice::WriteOnly)) {
        Logger::error("Failed to save list: " + list.id);
        return;
    }

    QJsonObject obj;
    obj["id"] = list.id;
    obj["name"] = list.name;
    obj["createdAt"] = list.createdAt.toString(Qt::ISODate);
    obj["totalWeightG"] = list.totalWeightG;
    obj["checkedCount"] = list.checkedCount;
    obj["isCompleted"] = list.isCompleted;

    obj["altitudeMax"] = list.params.altitudeMax;
    obj["altitudeMin"] = list.params.altitudeMin;
    obj["altitudeCamp"] = list.params.altitudeCamp;
    obj["days"] = list.params.days;
    obj["difficulty"] = list.params.difficulty;

    QJsonArray checkedArr;
    for (const QString& id : list.checkedIds) {
        checkedArr.append(id);
    }
    obj["checked"] = checkedArr;

    // 2026-09-19: 关键修复 - 持久化 4 类装备列表 (critical/important/recommended/optional).
    //   旧版只存了 checkedCount/isCompleted/altitudeMax 等元数据, 装备项完全没存.
    //   导致 loadListFromStorage → getList 返回的 entity.critical/.../optional 全为空,
    //   EquipmentDetailPage 用 CategorySection 渲染时 4 个分类卡都是 0 项,
    //   用户报 "生成装备清单后, 无法查看自动生成清单列表".
    // 这里把 RecommendedItem 序列化成 {item: {...}, reasons: [...]} 数组.
    auto serializeRecs = [](const QList<RecommendedItem>& recs) -> QJsonArray {
        QJsonArray arr;
        for (const auto& r : recs) {
            QJsonObject o;
            QJsonObject item;
            item["id"] = r.item.id;
            item["name"] = r.item.name;
            item["category"] = r.item.category;
            item["weightG"] = r.item.weightG;
            item["isCritical"] = r.item.isCritical;
            item["description"] = r.item.description;
            o["item"] = item;
            QJsonArray rs;
            for (const QString& s : r.reasons) rs.append(s);
            o["reasons"] = rs;
            arr.append(o);
        }
        return arr;
    };
    obj["critical"] = serializeRecs(list.critical);
    obj["important"] = serializeRecs(list.important);
    obj["recommended"] = serializeRecs(list.recommended);
    obj["optional"] = serializeRecs(list.optional);

    QJsonDocument doc(obj);
    file.write(doc.toJson(QJsonDocument::Indented));
    file.close();
}

EquipmentList EquipmentService::loadListFromStorage(const QString& id) const {
    EquipmentList list;
    QFile file(m_storagePath + "/" + id + ".json");
    if (!file.open(QIODevice::ReadOnly)) return list;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isObject()) return list;

    QJsonObject obj = doc.object();
    list.id = obj["id"].toString();
    list.name = obj["name"].toString();
    list.params.altitudeMax = obj["altitudeMax"].toInt();
    list.params.altitudeMin = obj["altitudeMin"].toInt();
    list.params.altitudeCamp = obj["altitudeCamp"].toInt();
    list.params.days = obj["days"].toInt();
    list.params.difficulty = obj["difficulty"].toInt();
    list.totalWeightG = obj["totalWeightG"].toInt();
    list.checkedCount = obj["checkedCount"].toInt();
    list.isCompleted = obj["isCompleted"].toBool();
    // 反序列化已勾选 id 列表
    const QJsonArray checkedArr = obj["checked"].toArray();
    for (const QJsonValue& v : checkedArr) {
        if (v.isString()) list.checkedIds.append(v.toString());
    }

    // 2026-09-19: 反序列化 4 类装备列表 - 配套 saveListToStorage 的修复.
    //   没这段 load 后 list.critical/.../optional 都为空, EquipmentDetailPage 看不到清单.
    auto deserializeRecs = [](const QJsonArray& arr) -> QList<RecommendedItem> {
        QList<RecommendedItem> out;
        for (const QJsonValue& v : arr) {
            if (!v.isObject()) continue;
            QJsonObject o = v.toObject();
            RecommendedItem r2;
            QJsonObject item = o["item"].toObject();
            r2.item.id = item["id"].toString();
            r2.item.name = item["name"].toString();
            r2.item.category = item["category"].toString();
            r2.item.weightG = item["weightG"].toInt();
            r2.item.isCritical = item["isCritical"].toBool();
            r2.item.description = item["description"].toString();
            QJsonArray rs = o["reasons"].toArray();
            for (const QJsonValue& rv : rs) {
                if (rv.isString()) r2.reasons.append(rv.toString());
            }
            out.append(r2);
        }
        return out;
    };
    list.critical = deserializeRecs(obj["critical"].toArray());
    list.important = deserializeRecs(obj["important"].toArray());
    list.recommended = deserializeRecs(obj["recommended"].toArray());
    list.optional = deserializeRecs(obj["optional"].toArray());
    return list;
}

// 2026-09-21: Phase 5 - 写操作切 Result
QVariantMap EquipmentService::saveList(const QVariantMap& listMap) {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::saveList";

    QString id = listMap.value("id").toString();
    if (auto e = requireNonEmpty(id, "listMap.id", ctx)) return *e;

    EquipmentList list = loadListFromStorage(id);
    // 2026-09-19: 修复重命名无效 — QML 端 modifyList(name=...) 时旧逻辑
    //   只覆盖 checkedCount/isCompleted, name 字段被静默丢弃 (从磁盘 reload 后
    //   又被原值写回). 这里把 listMap 里的 name (及其他可持久化字段) 透传过来.
    if (listMap.contains("name")) {
        list.name = listMap.value("name").toString();
    }
    list.checkedCount = listMap.value("checkedCount", 0).toInt();
    list.isCompleted = listMap.value("isCompleted", false).toBool();
    saveListToStorage(list);
    emit listModified(id);
    return okVoid();
}

// 2026-09-21: Phase 5 批次 3 - getAllLists 返回 Result. 失败可能是 IO 错误 (目录打不开)
QVariantMap EquipmentService::getAllLists() {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::getAllLists";

    QVariantList result;
    QDir dir(m_storagePath);
    if (!dir.exists()) {
        // 目录不存在不视为错误, 直接返回空列表 (新用户正常情况)
        return toQVariant(Ok(result));
    }
    QStringList files;
    try {
        files = dir.entryList({"*.json"}, QDir::Files);
    } catch (...) {
        return toQVariant(Err<QVariantList>(ServiceErrorCode::IoError,
                                              QStringLiteral("无法读取清单目录: ") + m_storagePath,
                                              ctx));
    }
    for (const QString& f : files) {
        QString id = f.left(f.length() - 5);
        EquipmentList list = loadListFromStorage(id);
        if (list.id.isEmpty()) continue;

        QVariantMap m;
        m["id"] = list.id;
        m["name"] = list.name;
        m["altitudeMax"] = list.params.altitudeMax;
        m["altitudeLevel"] = static_cast<int>(
            getAltitudeLevel(list.params.altitudeMax));
        m["altitudeLevelName"] = getAltitudeLevelName(
            getAltitudeLevel(list.params.altitudeMax));
        m["totalWeightG"] = list.totalWeightG;
        m["checkedCount"] = list.checkedCount;
        m["isCompleted"] = list.isCompleted;
        m["createdAt"] = list.createdAt.toString(Qt::ISODate);
        result.append(m);
    }
    return toQVariant(Ok(result));
}

QVariantMap EquipmentService::getList(const QString& id) {
    QVariantMap result;
    EquipmentList list = loadListFromStorage(id);
    if (list.id.isEmpty()) return result;

    result["id"] = list.id;
    result["name"] = list.name;
    result["altitudeMax"] = list.params.altitudeMax;
    result["altitudeMin"] = list.params.altitudeMin;
    result["altitudeCamp"] = list.params.altitudeCamp;
    result["days"] = list.params.days;
    result["difficulty"] = list.params.difficulty;
    result["totalWeightG"] = list.totalWeightG;
    result["checkedCount"] = list.checkedCount;
    result["isCompleted"] = list.isCompleted;

    QVariantList criticalList, importantList, recommendedList, optionalList;
    for (const auto& r : list.critical) {
        QVariantMap m;
        m["id"] = r.item.id;
        m["name"] = r.item.name;
        m["weightG"] = r.item.weightG;
        m["reasons"] = r.reasons;
        // 2026-09-28: 补 checked 字段 - QML 端 CategorySection 的 _checked 靠它回显,
        //   之前 getList 完全不返回勾选状态 → 重启 App 后所有勾选看似丢失.
        m["checked"] = list.checkedIds.contains(r.item.id);
        criticalList.append(m);
    }
    for (const auto& r : list.important) {
        QVariantMap m;
        m["id"] = r.item.id;
        m["name"] = r.item.name;
        m["weightG"] = r.item.weightG;
        m["reasons"] = r.reasons;
        m["checked"] = list.checkedIds.contains(r.item.id);
        importantList.append(m);
    }
    for (const auto& r : list.recommended) {
        QVariantMap m;
        m["id"] = r.item.id;
        m["name"] = r.item.name;
        m["weightG"] = r.item.weightG;
        m["reasons"] = r.reasons;
        m["checked"] = list.checkedIds.contains(r.item.id);
        recommendedList.append(m);
    }
    for (const auto& r : list.optional) {
        QVariantMap m;
        m["id"] = r.item.id;
        m["name"] = r.item.name;
        m["weightG"] = r.item.weightG;
        m["reasons"] = r.reasons;
        m["checked"] = list.checkedIds.contains(r.item.id);
        optionalList.append(m);
    }
    result["critical"] = criticalList;
    result["important"] = importantList;
    result["recommended"] = recommendedList;
    result["optional"] = optionalList;
    return result;
}

// 2026-09-21: Phase 5 - 写操作切 Result
QVariantMap EquipmentService::deleteList(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::deleteList";

    QFile file(m_storagePath + "/" + id + ".json");
    if (!file.exists()) {
        return fail(ServiceErrorCode::NotFound,
                    QStringLiteral("清单文件不存在: %1").arg(id), ctx);
    }
    if (!file.remove()) {
        const QString err = file.errorString();
        Logger::error(QString("%1: %2").arg(ctx, err));
        return fail(ServiceErrorCode::IoError, err, ctx);
    }
    return okVoid();
}

// 2026-09-21: Phase 5 - modifyList 切 Result (内部调 saveList, 后者已返回 Result)
QVariantMap EquipmentService::modifyList(const QString& id,
                                         const QVariantMap& listMap) {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::modifyList";

    // 校验: listMap 里的 id 必须与传入的 id 一致, 防止误改其他清单
    const QString mapId = listMap.value("id").toString();
    if (mapId.isEmpty()) {
        Logger::warn(QString("%1: listMap has no id").arg(ctx));
        return fail(ServiceErrorCode::InvalidArgument,
                    QStringLiteral("listMap.id 为空"), ctx);
    }
    if (!id.isEmpty() && mapId != id) {
        Logger::warn(QString("%1: id mismatch (path=%2, map=%3)")
                         .arg(ctx).arg(id, mapId));
        return fail(ServiceErrorCode::InvalidArgument,
                    QStringLiteral("id 不匹配: path=%1 map=%2").arg(id, mapId), ctx);
    }
    return saveList(listMap);  // saveList 已是 Result, 直接转发
}

// 2026-09-21: 阶段 L3.8 - addPreference 切 Result<bool>
QVariantMap EquipmentService::addPreference(const QString& equipmentId,
                                             const QString& action,
                                             const QVariantMap& condition) {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::addPreference";

    if (auto e = requireNonEmpty(equipmentId, "equipmentId", ctx)) return *e;

    UserPreference pref;
    pref.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    pref.equipmentId = equipmentId;
    pref.action = action;
    pref.condition = QJsonDocument(QJsonObject::fromVariantMap(condition))
                          .toJson(QJsonDocument::Compact);
    pref.confidence = 100;
    pref.createdAt = QDateTime::currentDateTime();
    m_preferences.append(pref);

    // 持久化
    SettingsStore::beginWriteArray("preferences", m_preferences.size());
    for (int i = 0; i < m_preferences.size(); ++i) {
        SettingsStore::setArrayIndex(i);
        SettingsStore::setValue("id", m_preferences[i].id);
        SettingsStore::setValue("equipmentId", m_preferences[i].equipmentId);
        SettingsStore::setValue("action", m_preferences[i].action);
        SettingsStore::setValue("condition", m_preferences[i].condition);
        SettingsStore::setValue("confidence", m_preferences[i].confidence);
        SettingsStore::setValue("useCount", m_preferences[i].useCount);
    }
    SettingsStore::endArray();

    emit preferenceLearned(pref.id);
    return toQVariant(Ok(true));
}

QVariantList EquipmentService::getPreferences() {
    QVariantList result;
    for (const auto& pref : m_preferences) {
        QVariantMap m;
        m["id"] = pref.id;
        m["equipmentId"] = pref.equipmentId;
        m["action"] = pref.action;
        m["condition"] = pref.condition;
        m["confidence"] = pref.confidence;
        m["useCount"] = pref.useCount;
        result.append(m);
    }
    return result;
}

// 2026-09-21: 阶段 L3.8 - deletePreference 切 Result<bool>
QVariantMap EquipmentService::deletePreference(const QString& id) {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::deletePreference";

    if (auto e = requireNonEmpty(id, "id", ctx)) return *e;

    auto it = std::remove_if(m_preferences.begin(), m_preferences.end(),
        [&](const UserPreference& p) { return p.id == id; });
    const bool removed = (it != m_preferences.end());
    m_preferences.erase(it, m_preferences.end());

    if (!removed) {
        return toQVariant(Err<bool>(ServiceErrorCode::NotFound,
                                      QStringLiteral("preference 不存在: %1").arg(id), ctx));
    }
    return toQVariant(Ok(true));
}

void EquipmentService::clearPreferences() {
    m_preferences.clear();
    SettingsStore::remove("preferences");
    emit dataChanged();
}

QVariantMap EquipmentService::startCheck(const QString& listId) {
    QVariantMap result;
    EquipmentList list = loadListFromStorage(listId);
    if (list.id.isEmpty()) {
        result["error"] = "List not found";
        return result;
    }

    int total = list.critical.size() + list.important.size() +
                list.recommended.size() + list.optional.size();
    result["listId"] = listId;
    result["total"] = total;
    result["checked"] = list.checkedCount;
    result["progress"] = total > 0 ? (list.checkedCount * 100 / total) : 0;
    return result;
}

// 2026-09-21: Phase 5 - checkItem 切 Result. setItemChecked 是 inline alias 调这里.
QVariantMap EquipmentService::checkItem(const QString& listId,
                                       const QString& equipmentId,
                                       bool checked) {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::checkItem";

    // 用 checkedIds 做幂等: 同一个 equipmentId 重复勾选不会让 checkedCount 重复加
    EquipmentList list = loadListFromStorage(listId);
    if (list.id.isEmpty()) {
        return fail(ServiceErrorCode::NotFound,
                    QStringLiteral("清单不存在: %1").arg(listId), ctx);
    }

    const int total = list.critical.size() + list.important.size() +
                      list.recommended.size() + list.optional.size();

    if (checked) {
        if (!list.checkedIds.contains(equipmentId)) {
            list.checkedIds.append(equipmentId);
            list.checkedCount = std::min(total, list.checkedCount + 1);
        }
        // 重复勾选同一 id 不增量(幂等)
    } else {
        if (list.checkedIds.removeAll(equipmentId) > 0) {
            list.checkedCount = std::max(0, list.checkedCount - 1);
        }
        // 重复取消勾选不递减
    }

    list.isCompleted = (total > 0 && list.checkedCount >= total);

    saveListToStorage(list);
    emit listModified(listId);
    if (list.isCompleted) emit listCompleted(listId);
    return okVoid();
}

// 2026-09-21: 阶段 L3.8 - confirmSkip 切 Result<bool>
QVariantMap EquipmentService::confirmSkip(const QString& listId,
                                           const QString& equipmentId,
                                           const QString& reason) {
    using namespace outdoor::internal;
    const char* ctx = "EquipmentService::confirmSkip";

    if (auto e = requireNonEmpty(equipmentId, "equipmentId", ctx)) return *e;

    Logger::info(QString("Skip %1 in list %2: %3")
                     .arg(equipmentId).arg(listId).arg(reason));

    // 记录跳过的偏好（如果是 critical 跳过）
    QVariantMap cond;
    cond["reason"] = reason;
    cond["timestamp"] = QDateTime::currentDateTime().toString(Qt::ISODate);
    const QVariantMap prefRes = addPreference(equipmentId, "skipped_once", cond);
    if (auto e = propagateError<bool>(prefRes, ctx)) return *e;

    return toQVariant(Ok(true));
}

QVariantMap EquipmentService::getCheckProgress(const QString& listId) {
    return startCheck(listId);
}

QString EquipmentService::exportToPdf(const QString& listId,
                                       const QString& filePath) {
    // 简化版：返回文本格式
    EquipmentList list = loadListFromStorage(listId);
    if (list.id.isEmpty()) return "清单不存在";

    QString out;
    out += QString("=== %1 ===\n\n").arg(list.name);
    out += QString("最高海拔: %1 m\n").arg(list.params.altitudeMax);
    out += QString("行程天数: %1 天\n").arg(list.params.days);
    out += QString("难度: %1 星\n\n").arg(list.params.difficulty);
    out += QString("总重量: %1 g\n\n").arg(list.totalWeightG);

    out += "【必带】\n";
    for (const auto& r : list.critical) {
        out += QString("- [ ] %1 (%2 g)\n").arg(r.item.name).arg(r.item.weightG);
    }
    out += "\n【强必带】\n";
    for (const auto& r : list.important) {
        out += QString("- [ ] %1 (%2 g)\n").arg(r.item.name).arg(r.item.weightG);
    }
    out += "\n【推荐】\n";
    for (const auto& r : list.recommended) {
        out += QString("- [ ] %1 (%2 g)\n").arg(r.item.name).arg(r.item.weightG);
    }
    out += "\n【可选】\n";
    for (const auto& r : list.optional) {
        out += QString("- [ ] %1 (%2 g)\n").arg(r.item.name).arg(r.item.weightG);
    }

    QFile file(filePath);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(out.toUtf8());
        file.close();
        return "已导出: " + filePath;
    }
    return "导出失败";
}

} // namespace outdoor
