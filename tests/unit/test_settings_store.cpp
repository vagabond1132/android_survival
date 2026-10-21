/**
 * @file test_settings_store.cpp
 * @brief SettingsStore (阶段 L5.1 QSettings 封装) 单元测试
 *
 * 覆盖:
 *   - 单值读写 + 缺省值
 *   - Result 风格返回值 (isOk / isErr)
 *   - remove / clear
 *   - beginGroup 嵌套 + childGroups 遍历 (EquipmentService user_items 用的形状)
 *   - beginWriteArray / setArrayIndex / endArray / beginReadArray 配对
 */
#include <QtTest>
#include <QCoreApplication>
#include <QSettings>
#include <QStandardPaths>
#include <QTemporaryDir>

#include "src/common/SettingsStore.h"

using namespace outdoor;

class TestSettingsStore : public QObject {
    Q_OBJECT

private:
    QTemporaryDir m_dir;

private slots:
    void initTestCase() {
        QVERIFY(m_dir.isValid());
        // 把 QSettings 落到临时目录, 不污染真实配置
        QStandardPaths::setTestModeEnabled(true);
        QCoreApplication::setOrganizationName(QStringLiteral("OutdoorTest"));
        QCoreApplication::setApplicationName(QStringLiteral("SettingsStoreTest"));
        QSettings::setDefaultFormat(QSettings::IniFormat);
    }

    void init() { SettingsStore::clear(); }

    void test_stringRoundTrip() {
        QVERIFY(SettingsStore::setValue("prefs/theme", QStringLiteral("dark")).isOk());
        QCOMPARE(SettingsStore::getString("prefs/theme"), QStringLiteral("dark"));
    }

    void test_missingKeyFallsBackToDefault() {
        QVERIFY(SettingsStore::getString("prefs/absent", QStringLiteral("light")) == "light");
        QCOMPARE(SettingsStore::getInt("prefs/absent", 7), 7);
        QCOMPARE(SettingsStore::getDouble("prefs/absent", 1.5), 1.5);
        QVERIFY(SettingsStore::getBool("prefs/absent", true));
        QVERIFY(!SettingsStore::getValue("prefs/absent").isValid());
    }

    void test_typedValues() {
        QVERIFY(SettingsStore::setValue("n/count", 42).isOk());
        QVERIFY(SettingsStore::setValue("n/ratio", 0.25).isOk());
        QVERIFY(SettingsStore::setValue("n/on", true).isOk());
        QCOMPARE(SettingsStore::getInt("n/count"), 42);
        QCOMPARE(SettingsStore::getDouble("n/ratio"), 0.25);
        QVERIFY(SettingsStore::getBool("n/on"));
        // QVariant::toInt() 对数值型走截断 (0.25 → 0), 不算转换失败, 所以不会落到默认值.
        // 真正触发 fallback 的是非数值字符串, 下面单独验.
        QCOMPARE(SettingsStore::getInt("n/ratio", -1), 0);
        QVERIFY(SettingsStore::setValue("n/text", QStringLiteral("abc")).isOk());
        QCOMPARE(SettingsStore::getInt("n/text", -1), -1);
        QCOMPARE(SettingsStore::getBool("n/absent", false), false);
    }

    void test_removeKey() {
        QVERIFY(SettingsStore::setValue("tmp/a", 1).isOk());
        QVERIFY(SettingsStore::remove("tmp/a").isOk());
        QCOMPARE(SettingsStore::getInt("tmp/a", -1), -1);
        // 删不存在的 key 不应失败
        QVERIFY(SettingsStore::remove("tmp/never_existed").isOk());
    }

    // EquipmentService::addUserItem 用的嵌套 group 形状
    void test_nestedGroupAndChildGroups() {
        struct Row { QString id, name; int weightG; };
        const QVector<Row> rows = {{"user_1", "头灯", 90}, {"user_2", "防潮垫", 420}};

        SettingsStore::beginGroup("user_items");
        for (const Row& r : rows) {
            SettingsStore::beginGroup(r.id);
            SettingsStore::setValue("id", r.id);
            SettingsStore::setValue("name", r.name);
            SettingsStore::setValue("weightG", r.weightG);
            SettingsStore::endGroup();
        }
        SettingsStore::endGroup();

        SettingsStore::beginGroup("user_items");
        const QStringList groups = SettingsStore::childGroups();
        QCOMPARE(groups.size(), 2);
        QVERIFY(groups.contains("user_1"));
        SettingsStore::beginGroup("user_1");
        QCOMPARE(SettingsStore::getString("name"), QStringLiteral("头灯"));
        QCOMPARE(SettingsStore::getInt("weightG"), 90);
        SettingsStore::endGroup();
        SettingsStore::endGroup();

        // 组外读写不能命中组内的键
        QVERIFY(SettingsStore::getString("name").isEmpty());
    }

    void test_removeInsideGroup() {
        SettingsStore::beginGroup("user_items");
        SettingsStore::beginGroup("user_1");
        SettingsStore::setValue("name", QStringLiteral("头灯"));
        SettingsStore::endGroup();
        SettingsStore::endGroup();

        SettingsStore::beginGroup("user_items");
        QVERIFY(SettingsStore::remove("user_1").isOk());
        QVERIFY(!SettingsStore::childGroups().contains("user_1"));
        SettingsStore::endGroup();
    }

    void test_writeArrayRoundTrip() {
        const QStringList ids = {"a", "b", "c"};
        QVERIFY(SettingsStore::beginWriteArray("prefs/list", ids.size()).isOk());
        for (int i = 0; i < ids.size(); ++i) {
            SettingsStore::setArrayIndex(i);
            SettingsStore::setValue("v", ids[i]);
        }
        SettingsStore::endArray();

        QCOMPARE(SettingsStore::beginReadArray("prefs/list"), 3);
        for (int i = 0; i < 3; ++i) {
            SettingsStore::setArrayIndex(i);
            QCOMPARE(SettingsStore::getString("v"), ids[i]);
        }
        SettingsStore::endArray();
    }

    void test_clearWipesEverything() {
        QVERIFY(SettingsStore::setValue("a/b", 1).isOk());
        QVERIFY(SettingsStore::sync().isOk());
        QVERIFY(SettingsStore::clear().isOk());
        QCOMPARE(SettingsStore::getInt("a/b", -1), -1);
    }
};

QTEST_GUILESS_MAIN(TestSettingsStore)
#include "test_settings_store.moc"
