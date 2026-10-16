/**
 * @file test_asset_loader.cpp
 * @brief AssetLoader 与 assets/data 数据完整性
 *
 * 覆盖:
 *   - OUTDOOR_ASSET_ROOT 覆盖 qrc 路径 (测试进程无 qrc)
 *   - 13 份 JSON 全部可解析 + 主数组非空
 *   - 每条记录带 id / name (QML 详情页与导航依赖)
 *   - 文件缺失 / JSON 语法错误 → 返回 nullopt 且写 err
 */
#include <QtTest>
#include <QJsonArray>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QFile>

#include "src/core/AssetLoader.h"

using namespace outdoor;

namespace {

struct Spec {
    const char* file;
    const char* arrayKey;
    int documentedCount;   // doc/10-需求清单 第 10 节声明的数量
};

// 主数据文件 → 记录数组字段 → 文档声明条数
const QVector<Spec> kSpecs = {
    {"firstaid_entries.json",      "entries",       35},
    {"danger_species.json",        "species",       33},
    {"survival_items.json",        "items",         15},
    {"knots.json",                 "knots",         12},
    {"routes.json",                "routes",        749},
    {"travel.json",                "routes",        101},
    {"checklists.json",            "checklists",     4},
    {"equipment_base.json",        "items",         43},
    {"equipment_rules.json",       "rules",         39},
    {"field_guide_plants.json",    "plants",        339},
    {"field_guide_animals.json",   "animals",       139},
    {"field_guide_insects.json",   "insects",       114},
    {"field_guide_mushrooms.json", "mushrooms",      67},
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
    void test_allDataFilesParse_data() {
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

    // 每条记录带 id (QML getById / 详情页跳转依赖)
    void test_recordsCarryId_data() {
        for (const Spec& s : kSpecs) {
            const auto doc = AssetLoader::loadJson(QString::fromLatin1(s.file));
            QVERIFY(doc.has_value());
            const QJsonArray arr = doc->object().value(QLatin1String(s.arrayKey)).toArray();
            for (int i = 0; i < arr.size(); ++i) {
                const QJsonObject o = arr[i].toObject();
                QVERIFY2(!o.value(QLatin1String("id")).toString().isEmpty(),
                         qPrintable(QStringLiteral("%1[%2] 缺 id").arg(s.file).arg(i)));
            }
        }
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
};

QTEST_MAIN(TestAssetLoader)
#include "test_asset_loader.moc"
