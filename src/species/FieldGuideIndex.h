/**
 * @file FieldGuideIndex.h
 * @brief 图鉴数据索引 + 4 大类共享查询
 *
 * 替代原 SpeciesService 的核心职能,但拆分成植物/动物/昆虫/蘑菇 4 个独立集合。
 * 4 个 Service(PlantService/AnimalService/InsectService/MushroomService)共享此索引。
 *
 * 2026-08-27 V2 重构:
 * - 砍掉 NCNN,改为图鉴检索
 * - 蘑菇/昆虫独立成模块
 * - 现有 SpeciesService 保留为旧 API 入口(内部走此索引)
 */

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QHash>
#include <QList>
#include <QVariantMap>

namespace outdoor {

/**
 * @struct FieldGuideLookAlike
 * @brief 易混种条目(仅作展示/可选跳转, 不等于图鉴内某条)
 *
 * 2026-10-08: 旧实现用 QPair<id, distinction> 且丢弃 id 为空的项 —
 *   与 JSON schema {id, name, distinction, fatality} 不符, 导致 QML 端
 *   name 永远为空(显示"未知")、fatality 永远丢失、外部提及物种(无 id)整条消失.
 *   改为完整结构体: id 可空(空=纯文案不可跳转), name/distinction/fatality 保留.
 */
struct FieldGuideLookAlike {
    QString id;            // 可为空: 空 = 图鉴外的"外部提及", 不可跳转
    QString name;          // 易混种名称(展示用)
    QString distinction;   // 与当前条目的区别
    QString fatality;      // 致死性(如"高"/"中"/"有毒")
};

/**
 * @struct FieldGuideEntity
 * @brief 统一图鉴条目(植物/动物/昆虫/蘑菇)
 */
struct FieldGuideEntity {
    QString id;
    QString kingdom;              // plantae / animalia / insecta / fungi
    QString commonName;
    QString scientificName;
    QStringList alias;
    QString category;             // wild_vegetable / venomous_snake / tick / deadly_mushroom ...
    int dangerLevel = 0;          // 0=无害可食,5=致命
    QStringList features;         // 识别特征
    QStringList distribution;     // 分布省份
    int minElevation = 0;
    int maxElevation = 5000;
    QStringList habitats;
    QStringList activeMonths;     // 1-12 月份字符串
    QString description;
    QString source;
    QString reviewer;

    // 植物特有
    QStringList ediblePart;       // leaf/stem/root/flower/fruit/seed
    QStringList edibleMonths;
    QStringList edibleMethod;     // raw/blanch/cooked/pickled
    bool rawEdible = false;
    bool mustCook = false;
    QString taste;
    QString harvestTips;
    QString nutrition;

    // 动物特有
    QString venomType;            // blood_toxin / neuro_toxin / mixed / none
    QString venomLocation;        // 上颌管牙 / 蜂刺 / 蝎尾 等
    int attackDistanceCm = 0;
    QString activeTime;           // 日间 / 晨昏 / 夜间
    QStringList hibernationMonths;
    QString protectionLevel;      // 国家 I/II 级保护 / 无

    // 蘑菇特有
    QString poisoningType;        // 肝损害 / 肾损害 / 神经毒素 / 胃肠炎
    int latencyHours = 0;
    QString mortalityRate;        // 高/中/低

    // 通用扩展
    QStringList symptoms;         // 中毒症状
    QString firstAidId;           // 关联急救条目
    QStringList protectiveGear;
    QStringList photos;           // 图片路径(占位)
    QList<FieldGuideLookAlike> lookAlike;  // [{id?, name, distinction, fatality}]

    QVariantMap firstAidLinks;    // {"scenario": "action_id"}
    QList<QPair<QString, QStringList>> routeAssociations;  // [{route_id, [months]}]
    QVariantMap representativeColor;  // HSV {h, s, v}
    QStringList images;           // 角度列表
};

/**
 * @class FieldGuideIndex
 * @brief 图鉴数据共享索引
 *
 * 负责:
 * - 从 JSON 加载 4 类数据
 * - 内存索引(按 id/kingdom/category/dangerLevel/region/month)
 * - 提供基础查询
 * - 不做具体业务逻辑,由 4 个 Service 调用
 */
class FieldGuideIndex {
public:
    FieldGuideIndex();

    bool loadAll(const QString& dataDir);
    void clear();

    // 4 大类独立访问
    const QList<FieldGuideEntity>& plants() const { return m_plants; }
    const QList<FieldGuideEntity>& animals() const { return m_animals; }
    const QList<FieldGuideEntity>& insects() const { return m_insects; }
    const QList<FieldGuideEntity>& mushrooms() const { return m_mushrooms; }

    // 全量
    const QList<FieldGuideEntity>& all() const { return m_all; }
    const FieldGuideEntity* getById(const QString& id) const;

    // 通用 entity → QVariantMap(4 个 Service 共享)
    static QVariantMap toMap(const FieldGuideEntity& e);

    // 2026-09-24: 省份匹配 (4 个 Service 共享)
    //   分布数据是自由文本, 形如 "山东(鲁中)" / "河南(豫西伏牛、太行)" / "全国广布",
    //   精确相等 (e.distribution.contains(province)) 会漏掉绝大多数条目 → 下拉框选了
    //   省份后列表骤减甚至为空. 改为包含式匹配 + "全国*" 通配.
    static bool matchProvince(const QStringList& distribution, const QString& province);

    // 2026-09-24: 从自由文本 distribution 里归一化出规范省名 (下拉框用).
    //   "山东(鲁中)" → 山东; "陕西/河南/山东" → 陕西, 河南, 山东; "北方" 等区域词忽略.
    static QStringList canonicalProvinces(const QStringList& distribution);

    // 计数
    int plantCount() const { return m_plants.size(); }
    int animalCount() const { return m_animals.size(); }
    int insectCount() const { return m_insects.size(); }
    int mushroomCount() const { return m_mushrooms.size(); }
    int totalCount() const { return m_all.size(); }
    int dangerousCount() const;  // 4-5 级

    // 索引构建
    void rebuildIndices();

private:
    bool loadPlants(const QString& path);
    bool loadAnimals(const QString& path);
    bool loadInsects(const QString& path);
    bool loadMushrooms(const QString& path);

    static FieldGuideEntity parseEntity(const QVariantMap& m,
                                          const QString& kingdom,
                                          const QString& defaultCategory);

    QList<FieldGuideEntity> m_all;
    QList<FieldGuideEntity> m_plants;
    QList<FieldGuideEntity> m_animals;
    QList<FieldGuideEntity> m_insects;
    QList<FieldGuideEntity> m_mushrooms;

    QHash<QString, int> m_idIndex;  // id -> m_all 索引
};

} // namespace outdoor
