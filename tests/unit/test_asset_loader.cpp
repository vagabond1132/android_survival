/**
 * @file test_asset_loader.cpp
 * @brief AssetLoader 与 assets/data 数据完整性
 *
 * 覆盖:
 *   - OUTDOOR_ASSET_ROOT 覆盖 qrc 路径 (测试进程无 qrc)
 *   - 13 份 JSON 全部可解析 + 主数组非空
 *   - 每条记录带主键 (id, 仅 checklists.json 是 scenario) / name (QML 详情页与导航依赖)
 *   - 规则 ↔ 装备库双向对账 (#88): 引用的 id 存在、每件装备有人管、qty 键在 items 里
 *   - 往年天气表形状 (34 省 × 12 月, 六个数组全是数值)
 *   - 文件缺失 / JSON 语法错误 → 返回 nullopt 且写 err
 */
#include <QtTest>
#include <QJsonArray>
#include <QJsonObject>
#include <QHash>
#include <QSet>
#include <QTemporaryDir>
#include <QFile>

#include "src/core/AssetLoader.h"

using namespace outdoor;

namespace {

struct Spec {
    const char* file;
    const char* arrayKey;
    int documentedCount;   // doc/10-需求清单 第 10 节声明的数量
    const char* idKey;     // 记录主键字段名 —— 只有 checklists.json 用 scenario
};

// 主数据文件 → 记录数组字段 → 文档声明条数 → 主键字段
//
// 2026-10-22: checklists.json 的 idKey 是 scenario, 不是数据缺字段。
//   ChecklistService::loadTemplates 里 `list.id = o["scenario"]`, 主键由服务层从
//   scenario 派生; 条目 id 也是派生的 "scenario:序号" (checklist_items.id 是主键,
//   自建清单用 UUID, 两者不会撞)。给数据补 "id" 反而是冗余第二真源。
const QVector<Spec> kSpecs = {
    {"firstaid_entries.json",      "entries",       35, "id"},
    {"danger_species.json",        "species",       33, "id"},
    {"survival_items.json",        "items",         15, "id"},
    {"knots.json",                 "knots",         12, "id"},
    {"routes.json",                "routes",        749, "id"},
    {"travel.json",                "routes",        101, "id"},
    {"checklists.json",            "checklists",      4, "scenario"},
    {"equipment_base.json",        "items",          77, "id"},
    {"equipment_rules.json",       "rules",          75, "id"},
    {"field_guide_plants.json",    "plants",        323, "id"},
    {"field_guide_animals.json",   "animals",       131, "id"},
    {"field_guide_insects.json",   "insects",       107, "id"},
    {"field_guide_mushrooms.json", "mushrooms",      67, "id"},
};

} // namespace

class TestAssetLoader : public QObject {
    Q_OBJECT

private:
    // 部分用例会临时改写 OUTDOOR_ASSET_ROOT, QVERIFY 失败时直接 return,
    // 所以统一在 cleanup() 里恢复, 避免污染后续用例
    QString m_savedRoot;

private slots:
    void initTestCase() {
        m_savedRoot = qEnvironmentVariable("OUTDOOR_ASSET_ROOT");
        QVERIFY2(!m_savedRoot.isEmpty(), "OUTDOOR_ASSET_ROOT 未注入, 测试数据无法加载");
    }

    void cleanup() {
        qputenv("OUTDOOR_ASSET_ROOT", m_savedRoot.toUtf8());
    }

    void test_envRootOverridesQrcPath() {
        // CTest 注入 OUTDOOR_ASSET_ROOT, 该目录必须真实存在
        QCOMPARE(AssetLoader::assetRoot(), m_savedRoot + '/');
        QVERIFY(QFileInfo::exists(AssetLoader::assetRoot()));
    }

    void test_envRootWithoutTrailingSlash() {
        QString bare = m_savedRoot;
        while (bare.endsWith(QLatin1Char('/'))) bare.chop(1);
        qputenv("OUTDOOR_ASSET_ROOT", bare.toUtf8());
        QVERIFY(AssetLoader::assetRoot().endsWith(QLatin1Char('/')));
        QVERIFY(!AssetLoader::loadData(QStringLiteral("knots.json")).isEmpty());
    }

    // 13 份 JSON 必须全部解析成功, 主数组条数不低于文档声明值
    void test_allDataFilesParse() {  // 2026-10-22: 去掉 _data 后缀 (无配对 _test 时 QTest 静默跳过, 这条断言从没跑过)
        for (const Spec& s : kSpecs) {
            QString err;
            const auto doc = AssetLoader::loadJson(QString::fromLatin1(s.file), &err);
            QVERIFY2(doc.has_value(), qPrintable(QStringLiteral("%1: %2").arg(s.file, err)));
            const QJsonArray arr = doc->object().value(QLatin1String(s.arrayKey)).toArray();
            QVERIFY2(!arr.isEmpty(), qPrintable(QStringLiteral("%1: %2 数组为空").arg(s.file, s.arrayKey)));
            QVERIFY2(arr.size() >= s.documentedCount,
                     qPrintable(QStringLiteral("%1: %2 条数 %3 < 文档声明 %4, 文档需同步或数据回退")
                                    .arg(s.file, s.arrayKey).arg(arr.size()).arg(s.documentedCount)));
        }
    }

    // 每条记录带主键 (QML getById / 详情页跳转依赖)
    void test_recordsCarryId() {
        for (const Spec& s : kSpecs) {
            const auto doc = AssetLoader::loadJson(QString::fromLatin1(s.file));
            QVERIFY(doc.has_value());
            const QJsonArray arr = doc->object().value(QLatin1String(s.arrayKey)).toArray();
            for (int i = 0; i < arr.size(); ++i) {
                const QJsonObject o = arr[i].toObject();
                QVERIFY2(!o.value(QLatin1String(s.idKey)).toString().isEmpty(),
                         qPrintable(QStringLiteral("%1[%2] 缺 %3")
                                        .arg(s.file).arg(i).arg(s.idKey)));
            }
        }
    }

    /**
     * A35 图鉴同名重复 (2026-10-28; 由 scripts/dedupe_field_guide.py 合并, 这里当回归门禁)
     *
     * 为什么必须钉住: 历次 add_plants_*.js / add_animals_*.js 按不同 id 把同一物种写了
     * 两遍, 界内出现"同一个中文名 + 同一个学名"的两条记录, 图鉴列表就是两行同名.
     * 更要命的是 FieldGuideIndex::loadAll() 对旧 danger_species.json 是**按 id** 跳重
     * (src/species/FieldGuideIndex.cpp:68): 同名不同 id 在它眼里是两个物种, 谁也不会被
     * 跳过 —— 所以这类重复只能从数据侧消掉, 不能指望运行时去重.
     *   ① 界内 (common_name, scientific_name) 唯一
     *   ② 同一个中文名不许横跨两个界 (灵芝原来在植物界和菌物界各一条)
     *   ③ 同一个中文名不许对应两个学名 (山蛭 / 毒芹 / 白条草蜥 原来一名两指, 已按正名分开)
     *   ④ look_alike 里写了 id 就必须查得到条目 —— 点"易混"跳空白详情页就是假链接
     */
    void test_fieldGuideNoDuplicateSpecies() {
        QHash<QString, QJsonArray> byFile;   // arrayKey -> 记录数组
        QSet<QString> allIds;
        QHash<QString, QSet<QString>> nameKingdoms;   // 中文名 -> 出现它的界
        QHash<QString, QSet<QString>> nameSci;        // 中文名 -> 出现它的学名
        QStringList problems;

        // 第一遍: 把四份文件的 id 收齐 (易混可以指向后面的条目, 不能边读边判)
        for (const Spec& s : kSpecs) {
            const QString file = QString::fromLatin1(s.file);
            if (!file.startsWith(QLatin1String("field_guide_"))) continue;
            const auto doc = AssetLoader::loadJson(file);
            QVERIFY(doc.has_value());
            const QJsonArray arr = doc->object().value(QLatin1String(s.arrayKey)).toArray();
            byFile.insert(file + '|' + s.arrayKey, arr);
            for (const auto& v : arr) allIds.insert(v.toObject()["id"].toString());
        }
        QVERIFY2(allIds.size() == 628,
                 qPrintable(QStringLiteral("图鉴条目数 %1 != 628 (A35 合并后), 数据被改过就同步脚本与期望值")
                                .arg(allIds.size())));

        // 第二遍: 逐条判 ①②③④
        for (auto it = byFile.constBegin(); it != byFile.constEnd(); ++it) {
            const QString file = it.key().section('|', 0, 0);
            const QString arrayKey = it.key().section('|', 1);
            QSet<QString> within;
            const QJsonArray arr = it.value();
            for (const auto& v : arr) {
                const QJsonObject o = v.toObject();
                const QString id = o["id"].toString();
                const QString cn = o["common_name"].toString();
                const QString sci = o["scientific_name"].toString();
                const QString key = cn + QLatin1Char('\x1f') + sci;
                if (within.contains(key))
                    problems << (file + ": 界内重名 " + cn + " / " + sci);
                within.insert(key);
                nameKingdoms[cn].insert(arrayKey);
                nameSci[cn].insert(sci);
                const QJsonArray la = o["look_alike"].toArray();
                for (const auto& lv : la) {
                    const QJsonObject e = lv.toObject();
                    const QString ref = e["id"].toString();
                    if (!ref.isEmpty() && !allIds.contains(ref))
                        problems << (file + "/" + id + ": 易混指向不存在的条目 " + ref
                                     + " (" + e["name"].toString() + ")");
                }
            }
        }
        // ②③ 要等四份文件全读完才能判, 所以放在循环外
        auto joined = [](const QSet<QString>& in) {
            QStringList out;
            for (const QString& x : in) out << x;
            out.sort();
            return out.join(",");
        };
        for (auto nit = nameKingdoms.constBegin(); nit != nameKingdoms.constEnd(); ++nit)
            if (nit.value().size() > 1)
                problems << ("跨界同名 " + nit.key() + ": " + joined(nit.value()));
        for (auto nit = nameSci.constBegin(); nit != nameSci.constEnd(); ++nit)
            if (nit.value().size() > 1)
                problems << ("同名两学 " + nit.key() + ": " + joined(nit.value()));

        QVERIFY2(problems.isEmpty(),
                 qPrintable(QStringLiteral("A35 图鉴同名重复未收口 (%1 处):\n%2")
                                .arg(problems.size()).arg(problems.join("\n"))));
    }

    void test_missingFileReturnsNullopt() {
        QString err;
        const auto doc = AssetLoader::loadJson(QStringLiteral("no_such_file.json"), &err);
        QVERIFY(!doc.has_value());
        QVERIFY(!err.isEmpty());
    }

    void test_malformedJsonReportsOffset() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile f(dir.path() + "/broken.json");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(R"({"entries": [ {"id": "a", })");   // 截断的 JSON
        f.close();

        qputenv("OUTDOOR_ASSET_ROOT", dir.path().toUtf8());
        QString err;
        const auto doc = AssetLoader::loadJson(QStringLiteral("broken.json"), &err);
        QVERIFY(!doc.has_value());
        QVERIFY(err.contains(QStringLiteral("parse error")));
    }

    void test_emptyFileIsNotLoadedAsJson() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile f(dir.path() + "/empty.json");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.close();

        const QString saved = qEnvironmentVariable("OUTDOOR_ASSET_ROOT");
        qputenv("OUTDOOR_ASSET_ROOT", dir.path().toUtf8());
        QVERIFY(AssetLoader::loadData(QStringLiteral("empty.json")).isEmpty());
        QVERIFY(!AssetLoader::loadJson(QStringLiteral("empty.json")).has_value());
        qputenv("OUTDOOR_ASSET_ROOT", saved.toUtf8());
    }

    /**
     * 规则 ↔ 装备库的引用完整性 (2026-10-22 #88)
     *
     * 为什么要单独钉: 分档不生效有三个成因, 其中最难查的一个就是"规则引用了库里
     * 不存在的 item id" —— applyRules 静默跳过, 清单照常生成, 看上去"规则没生效",
     * 其实是这条规则永远不会命中. 方向要双向查:
     *   ① rule.items 里每个 id 都得在 equipment_base.json 里 (引用悬空 = 死规则)
     *   ② 库里每件装备至少被一条规则引用 (没人引用 = 只能落进兜底 Optional)
     *   ③ rule.qty 的键必须是该条 items 里的 id (给没在这条规则里的东西定量 = 白写)
     *   ④ priority 只能是引擎认的四个桶名 (写错的名字会被当 Optional 丢掉)
     */
    void test_equipmentRuleRefsResolve() {
        const auto rulesDoc = AssetLoader::loadJson(QStringLiteral("equipment_rules.json"));
        const auto baseDoc = AssetLoader::loadJson(QStringLiteral("equipment_base.json"));
        QVERIFY(rulesDoc.has_value());
        QVERIFY(baseDoc.has_value());

        const QJsonArray rules = rulesDoc->object()["rules"].toArray();
        const QJsonArray items = baseDoc->object()["items"].toArray();
        QCOMPARE(rules.size(), 75);
        QCOMPARE(items.size(), 77);

        QSet<QString> lib;
        for (const auto& v : items) lib.insert(v.toObject()["id"].toString());
        QVERIFY2(!lib.isEmpty(), "装备库读不出 id, 下面的对账没有意义");

        static const QSet<QString> kBuckets = {
            QStringLiteral("critical"), QStringLiteral("important"),
            QStringLiteral("recommended"), QStringLiteral("optional")
        };
        QSet<QString> referenced;
        for (int i = 0; i < rules.size(); ++i) {
            const QJsonObject r = rules[i].toObject();
            const QString where = QStringLiteral("规则 %1[%2]").arg(r["id"].toString()).arg(i);
            QVERIFY2(kBuckets.contains(r["priority"].toString()),
                     qPrintable(where + QStringLiteral(" priority 不是四个桶名之一: ")
                                + r["priority"].toString()));
            const QJsonArray ids = r["items"].toArray();
            QVERIFY2(!ids.isEmpty(), qPrintable(where + " items 为空"));
            QSet<QString> inRule;
            for (const auto& v : ids) {
                const QString id = v.toString();
                QVERIFY2(lib.contains(id),
                         qPrintable(where + QStringLiteral(" 引用了库里没有的装备: ") + id));
                inRule.insert(id);
                referenced.insert(id);
            }
            const QJsonObject qty = r["qty"].toObject();
            for (auto it = qty.constBegin(); it != qty.constEnd(); ++it) {
                QVERIFY2(inRule.contains(it.key()),
                         qPrintable(where + QStringLiteral(" 给 %1 定量, 但 %1 不在这条规则的"
                                                           " items 里 —— 白写").arg(it.key())));
                QVERIFY2(it.value().toInt() >= 1, qPrintable(where + " qty 要 ≥ 1"));
            }
        }
        // 反向: 库里每件都必须有规则管着 (兜底那条只管"没命中", 不该是大多数装备的归宿)
        for (const QString& id : lib)
            QVERIFY2(referenced.contains(id),
                     qPrintable(QStringLiteral("库里这件没人引用: ") + id));
    }

    // 2026-10-22: 往年天气表不进 kSpecs —— 那边每条记录都要有 id (QML getById
    //   依赖), 省级气候记录只有 name, 没有详情页. 这里单独验形状.
    void test_climateNormalsShape() {
        const auto doc = AssetLoader::loadJson(QStringLiteral("climate_normals.json"));
        QVERIFY(doc.has_value());
        const QJsonObject root = doc->object();
        const QJsonArray provinces = root["provinces"].toArray();
        QCOMPARE(provinces.size(), 34);
        QVERIFY(root["lapse_rate_c_per_1000m"].toDouble() < 0.0);
        QVERIFY(root["uv_per_1000m"].toDouble() > 0.0);

        static const char* kArrays[] = {
            "tempAvg", "tempMin", "precipMm", "uvIndex", "windMs", "diurnalRange"
        };
        for (int i = 0; i < provinces.size(); ++i) {
            const QJsonObject o = provinces[i].toObject();
            const QString where = QStringLiteral("provinces[%1]").arg(i);
            QVERIFY2(!o["name"].toString().isEmpty(), qPrintable(where + " 缺 name"));
            QVERIFY2(o["refAltitudeM"].toDouble() >= 0.0, qPrintable(where + " refAltitudeM 非法"));
            // 2026-11-03 (#45): 经纬度是"定位反查省份"的唯一依据, 缺 lon 的那条会被
            //   EquipmentService::nearestClimateProvince 整条跳过 —— 表少一个省, 边界处
            //   就常年把用户填进隔壁省。这里按中国疆域卡范围, 卡住"键不存在→0"这种假值。
            const double lat = o["lat"].toDouble();
            const double lon = o["lon"].toDouble();
            QVERIFY2(o["lat"].isDouble(), qPrintable(where + " 缺 lat"));
            QVERIFY2(o["lon"].isDouble(), qPrintable(where + " 缺 lon (定位反查不到这一省)"));
            QVERIFY2(lat >= 17.0 && lat <= 54.0,
                     qPrintable(where + QStringLiteral(" lat=%1 不在中国范围内").arg(lat)));
            QVERIFY2(lon >= 73.0 && lon <= 136.0,
                     qPrintable(where + QStringLiteral(" lon=%1 不在中国范围内").arg(lon)));
            for (const char* key : kArrays) {
                const QJsonArray arr = o[key].toArray();
                QVERIFY2(arr.size() == 12,
                         qPrintable(where + QStringLiteral(" %1 不是 12 个月").arg(key)));
                // 装备引擎拿这些值做阈值比较, NaN/字符串混进来会静默不触发
                for (const auto& v : arr)
                    QVERIFY2(v.isDouble(),
                             qPrintable(where + QStringLiteral(" %1 有非数值项").arg(key)));
            }
            // 夜里最低不该高于日均 ( climate 生成模型 tempMin = avg - diurnal/2 )
            const QJsonArray avg = o["tempAvg"].toArray();
            const QJsonArray mn = o["tempMin"].toArray();
            for (int m = 0; m < 12; ++m)
                QVERIFY2(mn[m].toDouble() <= avg[m].toDouble(),
                         qPrintable(where + QStringLiteral(" %1月 tempMin > tempAvg").arg(m + 1)));
        }
    }
};

QTEST_MAIN(TestAssetLoader)
#include "test_asset_loader.moc"
