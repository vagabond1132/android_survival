/**
 * @file test_file_scanner.cpp
 * @brief 本机轨迹文件扫描 (#148 轨迹导入搜索)
 *
 * 覆盖:
 *   - 按后缀命中 (.gpx/.kml/.csv, 大小写不敏感), 其它后缀不收
 *   - 关键字子串匹配 (含中文名)
 *   - 整枝剪掉隐藏目录; maxDepth 生效
 *   - diagnostics 逐根如实报告 (存在/可读/扫了多少/命中多少)
 *   - 结果按 mtime 倒序, maxHits 截断
 *   - 反向对照: 目录存在但没匹配 → 0 命中且 scanned>0 (证明过滤器跑过, 不是没扫)
 */
#include <QtTest>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QTemporaryDir>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include "src/platform/FileScanner.h"

using namespace outdoor;

namespace {

bool writeFile(const QString& path, const QByteArray& body)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(body);
    return f.commit();
}

QString nameList(const QVariantList& hits)
{
    QStringList names;
    for (const QVariant& h : hits)
        names << h.toMap().value(QStringLiteral("name")).toString();
    names.sort();
    return names.join(QLatin1Char(','));
}

QVariantMap diagFor(const QVariantList& diagnostics, const QString& root)
{
    for (const QVariant& d : diagnostics) {
        const QVariantMap m = d.toMap();
        if (m.value(QStringLiteral("root")).toString() == root)
            return m;
    }
    return QVariantMap();
}

} // namespace

class TestFileScanner : public QObject {
    Q_OBJECT
private:
    QTemporaryDir m_dir;

private slots:
    void initTestCase() {
        QVERIFY(m_dir.isValid());
        const QString dl = m_dir.path() + QStringLiteral("/Download");
        QVERIFY(writeFile(dl + QStringLiteral("/walk_day.gpx"), "<gpx/>"));
        QVERIFY(writeFile(dl + QStringLiteral("/微信-测试轨迹.kml"), "<kml/>"));
        QVERIFY(writeFile(dl + QStringLiteral("/readme.txt"), "not a track"));
        QVERIFY(writeFile(dl + QStringLiteral("/nested/deep_route.KML"), "<kml/>"));
        QVERIFY(writeFile(dl + QStringLiteral("/nested/points.csv"), "lat,lon\n"));
        QVERIFY(writeFile(dl + QStringLiteral("/.hidden/ghost.gpx"), "<gpx/>"));
        QVERIFY(writeFile(m_dir.path() + QStringLiteral("/Else/other.gpx"), "<gpx/>"));
    }

    void findsOnlyTrackSuffixes() {
        const QStringList roots{m_dir.path() + QStringLiteral("/Download")};
        QVariantList diag;
        const QVariantList hits = FileScanner::search(roots, QString(),
                                                      FileScanner::trackSuffixes(), &diag);
        QCOMPARE(nameList(hits),
                 QStringLiteral("deep_route.KML,points.csv,walk_day.gpx,微信-测试轨迹.kml"));
        QCOMPARE(diag.size(), 1);
        QVERIFY(diagFor(diag, roots.first()).value(QStringLiteral("hits")).toInt() == 4);
    }

    void keywordMatchesCaseInsensitivelyAndInCjk() {
        const QStringList roots{m_dir.path() + QStringLiteral("/Download")};
        QCOMPARE(nameList(FileScanner::search(roots, QStringLiteral("DAY"),
                                              FileScanner::trackSuffixes(), nullptr)),
                 QStringLiteral("walk_day.gpx"));
        QCOMPARE(nameList(FileScanner::search(roots, QStringLiteral("微信"),
                                              FileScanner::trackSuffixes(), nullptr)),
                 QStringLiteral("微信-测试轨迹.kml"));
        // 关键字不该命中的时候要说 0 条, 但不能是"没扫到"造成的 0 条 —— 见下面诊断
        QVariantList diag;
        const QVariantList none = FileScanner::search(roots, QStringLiteral("不存在的名字"),
                                                      FileScanner::trackSuffixes(), &diag);
        QCOMPARE(none.size(), 0);
        QVERIFY(diagFor(diag, roots.first()).value(QStringLiteral("scanned")).toInt() > 0);
    }

    void hiddenDirsArePrunedAndDepthIsHonoured() {
        const QStringList roots{m_dir.path() + QStringLiteral("/Download")};
        const QVariantList all = FileScanner::search(roots, QString(),
                                                    FileScanner::trackSuffixes(), nullptr);
        QVERIFY(!nameList(all).contains(QStringLiteral("ghost")));

        FileScanner::Options shallow;
        shallow.maxDepth = 1;
        const QVariantList top = FileScanner::search(roots, QString(),
                                                     FileScanner::trackSuffixes(), nullptr, shallow);
        QCOMPARE(nameList(top), QStringLiteral("walk_day.gpx,微信-测试轨迹.kml"));
    }

    void resultsSortedByMtimeDescAndCapped() {
        const QStringList roots{m_dir.path() + QStringLiteral("/Download")};
        QVariantList diag;
        const QVariantList hits = FileScanner::search(roots, QString(),
                                                      FileScanner::trackSuffixes(), &diag);
        QVERIFY(hits.size() >= 2);
        qint64 previous = -1;
        for (const QVariant& h : hits) {
            const qint64 ms = h.toMap().value(QStringLiteral("mtimeMs")).toLongLong();
            if (previous >= 0)
                QVERIFY2(ms <= previous, "结果必须按修改时间从新到旧");
            previous = ms;
            // path 必须是能直接交给 importGpx/importKml 的本地绝对路径
            QVERIFY(QFileInfo(h.toMap().value(QStringLiteral("path")).toString()).exists());
        }

        FileScanner::Options cap;
        cap.maxHits = 1;
        QCOMPARE(FileScanner::search(roots, QString(), FileScanner::trackSuffixes(),
                                     nullptr, cap).size(), 1);
    }

    void missingRootReportedHonestly() {
        const QString gone = m_dir.path() + QStringLiteral("/NoWeChatHere/MicroMsg/Download");
        QVariantList diag;
        const QVariantList hits = FileScanner::search({gone}, QString(),
                                                      FileScanner::trackSuffixes(), &diag);
        QCOMPARE(hits.size(), 0);
        const QVariantMap m = diagFor(diag, gone);
        QVERIFY(!m.isEmpty());
        QCOMPARE(m.value(QStringLiteral("exists")).toBool(), false);
        QCOMPARE(m.value(QStringLiteral("scanned")).toInt(), 0);
    }

    void multipleRootsMergeAndSkipBudgetExhaustion() {
        const QStringList roots{m_dir.path() + QStringLiteral("/Download"),
                                m_dir.path() + QStringLiteral("/Else")};
        QVariantList diag;
        const QVariantList hits = FileScanner::search(roots, QString(),
                                                      FileScanner::trackSuffixes(), &diag);
        QCOMPARE(diag.size(), 2);
        QVERIFY(nameList(hits).contains(QStringLiteral("other.gpx")));

        FileScanner::Options starved;
        starved.maxEntries = 0;
        QCOMPARE(FileScanner::search(roots, QString(), FileScanner::trackSuffixes(),
                                     &diag, starved).size(), 0);
    }
};

QTEST_MAIN(TestFileScanner)
#include "test_file_scanner.moc"
