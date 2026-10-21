/**
 * @file test_common_options.cpp
 * @brief CommonOptions 展示层 helper 单元测试 (2026-10-20 Wave C3)
 *
 * 只测不依赖设备/数据库的两个纯函数:
 *   - stripEntryMarker: 剥数据正文前缀的 emoji 与手写序号 (任务 #27/#58)
 *   - plateCode: 图鉴编号, 要求"跨启动稳定 + 同前缀不撞号"
 * 颜色 token 没有逻辑, 不测.
 */
#include <QtTest>

#include "src/core/CommonOptions.h"

namespace {
// 前缀符号用 QChar 码位写, 不把 emoji 直接抄进源文件 —— 那是本仓库踩过两次的坑
// (源码里的 emoji 会被编辑器/字体链改写成变体, 测试就会测到别的字符).
QString mark(ushort first, ushort second = 0) {
    QString s = QString(QChar(first));
    if (second) s += QChar(second);
    return s + QLatin1Char(' ');
}
} // namespace

class TestCommonOptions : public QObject {
    Q_OBJECT

private slots:
    // ===== stripEntryMarker =====
    void strip_removes_warning_emoji_prefix() {
        CommonOptions c;
        // knots.json 的 19 条 common_mistakes 全是这个形态
        QCOMPARE(c.stripEntryMarker(mark(0x26A0, 0xFE0F) + QStringLiteral("拉得不紧会松脱")),
                 QStringLiteral("拉得不紧会松脱"));
    }

    void strip_removes_check_and_star_plane_prefix() {
        CommonOptions c;
        // survival_items.json tips 的 ✅ (45 处)
        QCOMPARE(c.stripEntryMarker(mark(0x2705) + QStringLiteral("携带 2 个打火机")),
                 QStringLiteral("携带 2 个打火机"));
        // 星平面 emoji (🆘 U+1F198) 在 QString 里是一对代理
        QCOMPARE(c.stripEntryMarker(QString(QChar(0xD83C)) + QChar(0xDD98) + QStringLiteral(" 伤口处理")),
                 QStringLiteral("伤口处理"));
    }

    void strip_removes_hand_numbering_but_not_decimals() {
        CommonOptions c;
        // knots.json 的 53 条 steps 手写序号; 详情页自己排 01/02, 留着会重复
        QCOMPARE(c.stripEntryMarker(QStringLiteral("1. 绳头绕主绳一圈")),
                 QStringLiteral("绳头绕主绳一圈"));
        QCOMPARE(c.stripEntryMarker(QStringLiteral("12、拉紧")), QStringLiteral("拉紧"));
        QCOMPARE(c.stripEntryMarker(QStringLiteral("2.5 米")), QStringLiteral("2.5 米"));
    }

    void strip_keeps_cjk_punctuation_and_handles_edges() {
        CommonOptions c;
        // firstaid_entries 的 description 有 2 条以中文书名号起手, 那是正文不是前缀
        QCOMPARE(c.stripEntryMarker(QStringLiteral("「上火」是中医证候")),
                 QStringLiteral("「上火」是中医证候"));
        QCOMPARE(c.stripEntryMarker(QString()), QString());
        QCOMPARE(c.stripEntryMarker(QStringLiteral("   ")), QString());
        QCOMPARE(c.stripEntryMarker(QString(QChar(0x26A0))), QString());
    }

    // ===== plateCode =====
    void plate_is_stable_for_non_numeric_id() {
        CommonOptions c;
        // KnotService::m_knots 是 QHash, 遍历序每次启动都可能不同 →
        // 编号只能由 id 决定, 不能由"它是第几条"决定, 否则目录页和详情页对不上号.
        QCOMPARE(c.plateCode("KN", "bowline"), c.plateCode("KN", "bowline"));
        QCOMPARE(c.plateCode("KN", QStringLiteral("外科结")).length(), 6);   // KN-xxx
    }

    void plate_pads_numeric_id() {
        CommonOptions c;
        QCOMPARE(c.plateCode("SP", "7"), QStringLiteral("SP-007"));
        QCOMPARE(c.plateCode("", "7"), QStringLiteral("007"));
    }

    void plate_unique_within_12_knots() {
        CommonOptions c;
        static const char* const ids[] = { "single", "figure_eight", "square", "double_fisherman",
                                           "figure_eight_bend", "round_lumber", "truckers", "bowline",
                                           "double_bowline", "prussik", "外科结", "clove_hitch" };
        QSet<QString> seen;
        for (const char* id : ids)
            seen.insert(c.plateCode("KN", QString::fromUtf8(id)));
        // 同号会被读成同一条结, 12 条必须两两不同
        QCOMPARE(seen.size(), 12);
    }
};

QTEST_GUILESS_MAIN(TestCommonOptions)
#include "test_common_options.moc"
