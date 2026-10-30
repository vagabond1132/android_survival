/**
 * @file test_common_options.cpp
 * @brief CommonOptions 展示层 helper 单元测试 (2026-10-20 Wave C3)
 *
 * 只测不依赖设备/数据库的纯函数:
 *   - stripEntryMarker: 剥数据正文前缀的 emoji 与手写序号 (任务 #27/#58)
 *   - plateCode: 图鉴编号, 要求"跨启动稳定 + 同前缀不撞号"
 *   - metersPerPixel / fitBounds: 地图比例尺与自动视野 (任务 #82),
 *     两个函数必须互相对得上, 所以断言写成"fit 出来的档位 × 比例尺 = 视野真实宽度"
 *   - dangerLevelLabel: 危险档文案 (任务 #122), 越界必须空串 = "不给假读数"
 * 另有两条从真 QQmlEngine 里调 C++ 的用例: Q_INVOKABLE 的返回值/默认实参在 QML
 * 侧是什么形态, 光看 C++ 签名猜不出来 (plateCode 的 width、地图轨迹的点列表).
 * 2026-10-26 A31: 原先这里写着"颜色 token 没有逻辑, 不测" —— 作废. 日/夜翻档就是一种
 *   会静默失效的逻辑: 白天对、夜晚浅底压浅字, 编译与 qmllint 都不报, 只有对比度断言
 *   抓得住 (见 fill_pair_contrast_holds_in_both_tones, 带一条负样本对照).
 */
#include <QtTest>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlExpression>
#include <cmath>
#include <algorithm>   // std::swap (contrastRatio)

#include "src/core/CommonOptions.h"

namespace {
// 前缀符号用 QChar 码位写, 不把 emoji 直接抄进源文件 —— 那是本仓库踩过两次的坑
// (源码里的 emoji 会被编辑器/字体链改写成变体, 测试就会测到别的字符).
QString mark(ushort first, ushort second = 0) {
    QString s = QString(QChar(first));
    if (second) s += QChar(second);
    return s + QLatin1Char(' ');
}

// "从 QML 侧调 C++" 的入口. QQmlEngine::evaluate 走的是 JS 全局对象, 那里看不见
// setContextProperty (只有 QML 组件的上下文作用链才有), 首版就是这么写的, 结果
// 测到的是 ReferenceError: opts is not defined. 挂在 rootContext 上要用
// QQmlExpression —— 而且下面每个用例都先跑一条 `1+1` 证明这条通道本身是通的,
// 免得"机制没打通"被读成"功能没问题".
QVariant evalInQml(QQmlEngine& engine, const QString& program, QString* err = nullptr) {
    QQmlExpression expr(engine.rootContext(), nullptr, QStringLiteral("<unit-test>"));
    expr.setExpression(program);
    bool isUndefined = false;
    const QVariant v = expr.evaluate(&isUndefined);
    if (err) *err = expr.hasError() ? expr.error().description() : QString();
    return v;
}
// WCAG 2.1 相对亮度与对比度. 用来测"底与字成对翻档"这条不变量 (A31).
double contrastRatio(const QColor& a, const QColor& b) {
    auto lin = [](double c) {
        return c <= 0.03928 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4);
    };
    auto lum = [&](const QColor& c) {
        return 0.2126 * lin(c.redF()) + 0.7152 * lin(c.greenF()) + 0.0722 * lin(c.blueF());
    };
    double l1 = lum(a), l2 = lum(b);
    if (l1 < l2) std::swap(l1, l2);
    return (l1 + 0.05) / (l2 + 0.05);
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

    // C++ 的默认实参不进 moc 签名, 所以 QML 少传参数时到底拿没拿到 width=3 是个
    // 未验证问题: 全站 20 处都只写 plateCode(前缀, id) 两个参数. 从 QML 侧调一次,
    // 让"补零"这件事有证据, 而不是从 C++ 侧看签名里有 = 3 就当真.
    void plate_from_qml_still_pads() {
        CommonOptions c;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty(QStringLiteral("opts"), &c);
        QString err;
        // 先证明通道本身通 (否则 ReferenceError 会被读成"默认参数没问题")
        QCOMPARE(evalInQml(engine, QStringLiteral("1 + 1"), &err).toInt(), 2);
        QVERIFY(err.isEmpty());

        const QVariant twoArgs = evalInQml(engine, QStringLiteral("opts.plateCode('SP','7')"), &err);
        QVERIFY2(err.isEmpty(), qPrintable(QStringLiteral("2 参调用出错: %1").arg(err)));
        QCOMPARE(twoArgs.toString(), QStringLiteral("SP-007"));
        // 对照组: 显式传 3 必须与上面一致
        const QVariant threeArgs = evalInQml(engine, QStringLiteral("opts.plateCode('SP','7',3)"), &err);
        QVERIFY2(err.isEmpty(), qPrintable(QStringLiteral("3 参调用出错: %1").arg(err)));
        QCOMPARE(threeArgs.toString(), twoArgs.toString());
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

    // ===== 地图视野 (2026-10-22 任务 #82) =====
    // MapPage 的 fitBoundsToRoutes 原来用"经验公式 z = round(9 - log2(km))",
    // 而同一页的比例尺用 web-mercator 156543.03·cos(lat)/2^z. 两套口径差约 7 档,
    // 于是 1 km 的轨迹被放到约 200 km 宽的视野里 → 用户看到的是"选了不画线"
    // 和"多选后比例尺跳到 200km". 现在两边共用这里的实现, 所以必须有测试.
    void mpp_is_web_mercator_scale() {
        CommonOptions c;
        // z0 赤道: 40075016.686 m 的mercator世界摊在 256 px 上
        QVERIFY2(qAbs(c.metersPerPixel(0.0, 0.0) - 156543.03392) < 1e-3,
                 qPrintable(QString::number(c.metersPerPixel(0.0, 0.0))));
        // 涨一档缩一半
        QVERIFY2(qAbs(c.metersPerPixel(0.0, 1.0) - 78271.51696) < 1e-3, "每档 ×2");
        // 纬度只按 cos 缩 (60° 是赤道的一半)
        QVERIFY2(qAbs(c.metersPerPixel(60.0, 0.0) - 78271.51696) < 1.0, "cos(lat)");
    }

    void fit_one_km_track_is_z15_not_z9() {
        CommonOptions c;
        // 约 1×1.2 km 的框 (泰山一带), 手机屏 360×640, 底栏抽屉占掉下面 240 px
        const double lat0 = 36.250, lon0 = 117.100;
        const QVariantMap f = c.fitBounds(lat0, lat0 + 0.009, lon0, lon0 + 0.010,
                                          360, 640, 24, 24, 360 - 48, 640 - 240 - 48,
                                          3, 18);
        QVERIFY2(!f.isEmpty(), "fit 结果不能为空 (地图尺寸合法)");
        const double z = f.value("zoom").toDouble();
        QVERIFY2(z >= 14.0 && z <= 16.5,
                 qPrintable(QStringLiteral("1 km 应该到 z15 上下, 实得 %1").arg(z)));
        // 反向对照 (门禁的"已知命中负样本"): 旧的"经验公式"落在同一格上给 z≈9.
        //   不写这一条, 上面那个区间断言换成 round(9-log2(km)) 也照样"通过".
        const double oldZ = std::round(9.0 - std::log2(1.24));
        QVERIFY2(z - oldZ >= 4.0,
                 qPrintable(QStringLiteral("新 %1 与旧 %2 没拉开").arg(z).arg(oldZ)));
    }

    void fit_matches_the_scale_bar() {
        CommonOptions c;
        // 核心不变量: fit 出来的档位 × 比例尺公式 = 视野真实宽度.
        //   这条断言同时管住两个函数 —— 只改一个口径就会被它抓住.
        const double lat0 = 30.0, lon0 = 120.0;
        const double w = 300.0;
        const QVariantMap f = c.fitBounds(lat0, lat0 + 0.009, lon0, lon0 + 0.010,
                                          360, 640, 0, 0, w, 600, 3, 18);
        const double z = f.value("zoom").toDouble();
        const double viewMetres = w * c.metersPerPixel(f.value("centerLat").toDouble(), z);
        // 0.01° 经度在 30°N 的地面宽 ≈ 962 m (cos(30)·111.32·0.01)
        QVERIFY2(qAbs(viewMetres - 962.0) / 962.0 < 0.06,
                 qPrintable(QStringLiteral("视野宽 %1 m, 应≈962 m").arg(viewMetres)));
    }

    void fit_avoids_the_bottom_sheet() {
        CommonOptions c;
        const double lat0 = 36.25, lon0 = 117.10;
        // 整块居中 vs 只看上半屏: 后者必须把中心往南推, 让线画到抽屉上方
        const QVariantMap full = c.fitBounds(lat0, lat0 + 0.05, lon0, lon0 + 0.05,
                                             360, 640, 0, 0, 360, 640, 3, 18);
        const QVariantMap upper = c.fitBounds(lat0, lat0 + 0.05, lon0, lon0 + 0.05,
                                              360, 640, 0, 0, 360, 320, 3, 18);
        QVERIFY(upper.value("centerLat").toDouble()
                < full.value("centerLat").toDouble() - 0.005);
        // 上半屏更窄 → 档位更低一档, 线才装得进去
        QVERIFY(upper.value("zoom").toDouble() < full.value("zoom").toDouble());
    }

    // QML 调用形态: MapPage 传 12 个 double, 再按 f.zoom / f.centerLat 读回来.
    //   moc 签名里少一个参数、或 QVariantMap 在 QML 侧不是普通对象, 断言都会在这里炸,
    //   而不是等 38 分钟的 arm64 构建 + 真机点开轨迹 Tab.
    void fit_called_from_qml_reads_like_js_object() {
        CommonOptions c;
        QQmlEngine engine;
        engine.rootContext()->setContextProperty(QStringLiteral("opts"), &c);
        QString err;
        QCOMPARE(evalInQml(engine, QStringLiteral("1 + 1"), &err).toInt(), 2);
        QVERIFY(err.isEmpty());
        const QVariant r = evalInQml(engine, QStringLiteral(
            "(function () {"
            "  var f = opts.fitBounds(36.250, 36.259, 117.100, 117.110,"
            "                    360, 640, 24, 24, 312, 352, 3, 18);"
            "  if (!f) return 'null';"
            "  if (typeof f.zoom !== 'number') return 'noZoom:' + typeof f.zoom;"
            "  if (typeof f.centerLat !== 'number') return 'noCenterLat';"
            "  return Math.round(f.zoom * 100) / 100 + '@'"
            "       + (Math.round(f.centerLat * 10000) / 10000).toFixed(4);"
            "})()"), &err);
        QVERIFY2(err.isEmpty(), qPrintable(QStringLiteral("QML 调用报错: %1").arg(err)));
        // 36.250..36.259 / 117.100..117.110 的框 → z≈15.42, 纬度中心被抽屉推南
        QCOMPARE(r.toString(), QStringLiteral("15.42@36.2514"));
    }

    void fit_edges_clamp_and_refuse() {
        CommonOptions c;
        // 单点: 顶到调用方给的上限, 且点要落在**可视子矩形**中心 (不是整块 Map 中心):
        //   可视区 y=[24, 376] 的中心 200 比 Map 中心 320 高 120 px, 所以中心必须
        //   往南偏 120·mpp 的地面距离, 点才会画到抽屉上方.
        const QVariantMap p = c.fitBounds(36.25, 36.25, 117.10, 117.10,
                                          360, 640, 24, 24, 312, 352, 3, 16);
        QCOMPARE(p.value("zoom").toDouble(), 16.0);
        const double wantShift = 120.0 * c.metersPerPixel(36.25, 16.0);   // ≈231 m
        const double gotShift = c.distanceMeters(p.value("centerLat").toDouble(),
                                                 p.value("centerLon").toDouble(),
                                                 36.25, 117.10);
        QVERIFY2(qAbs(gotShift - wantShift) < wantShift * 0.05 + 1.0,
                 qPrintable(QStringLiteral("偏移 %1 m, 应≈%2 m").arg(gotShift).arg(wantShift)));
        QVERIFY2(c.bearingDegrees(p.value("centerLat").toDouble(),
                                  p.value("centerLon").toDouble(), 36.25, 117.10) < 1.0,
                 "点应在中心正北 (只补了竖向, 没补横向)");
        // 跨半球的大框: 收到下限, 不许出负档位
        const QVariantMap world = c.fitBounds(-40, 40, 100, 200,
                                              360, 640, 0, 0, 360, 640, 3, 18);
        QCOMPARE(world.value("zoom").toDouble(), 3.0);
        // 尺寸非法 (Map 还没布局出宽高) → 空 map, 调用方不动视野.
        //   这条必须能"失败": 上面两条非空断言就是它的负样本对照.
        QVERIFY(c.fitBounds(36.25, 36.26, 117.1, 117.11, 0, 0,
                            0, 0, 0, 0, 3, 18).isEmpty());
        // 坐标非法 (NaN) 同样拒绝
        QVERIFY(c.fitBounds(std::nan(""), 36.26, 117.1, 117.11, 360, 640,
                            0, 0, 360, 640, 3, 18).isEmpty());
    }

    // ===== 日/夜成对翻档 (2026-10-26 A31 真机) =====
    // 现象: 夜晚配色打开后, 底部导航选中格的中文「我」看不见, 拉丁代号 ME 还在.
    // 因: 选中格的"底"用的是会翻档的实心色 (colorAccent: 日 #131A17 / 夜 #E4E9E6),
    //   而"字"配的是永久浅色的 on-ink 族 —— 那族是给 colorInkPanel (两档都深底) 用的.
    //   白天浅字压深底成立, 夜晚浅字压浅底就成了 1.05:1.
    // 所以这里测的不是某个具体色值, 而是"底和字必须一起翻"这条不变量.
    void fill_pair_contrast_holds_in_both_tones() {
        CommonOptions c;
        const bool wasNight = c.nightMode();
        for (bool night : {false, true}) {
            c.setNightMode(night);
            const QColor fill = c.colorAccent();
            const QString tag = night ? "夜晚档" : "白天档";
            const double zh = contrastRatio(fill, c.colorTextOnAccent());
            const double code = contrastRatio(fill, c.colorBlazeOnFill());
            QVERIFY2(zh >= 4.5, qPrintable(QStringLiteral("%1 块上中文 %2:1").arg(tag).arg(zh)));
            QVERIFY2(code >= 4.5, qPrintable(QStringLiteral("%1 块上代号 %2:1")
                                             .arg(tag).arg(code)));
        }
        // 负样本对照 (没有这两条, 上面的断言换成"永远返回高对比"的假实现也能通过):
        //   老写法 colorOnInk 配实心块, 白天是好的、夜晚必须炸 —— 证明 bug 真的可测.
        c.setNightMode(false);
        QVERIFY(contrastRatio(c.colorAccent(), c.colorOnInk()) >= 4.5);
        c.setNightMode(true);
        QVERIFY2(contrastRatio(c.colorAccent(), c.colorOnInk()) < 4.5,
                 "夜晚档下 on-ink 配实心块居然还可读? 那说明翻档逻辑没生效, 测试要重看");
        c.setNightMode(wasNight);   // setNightMode 会落 QSettings, 别把开发机档位改掉
    }

    void ink_pair_still_contrasts_in_both_tones() {
        CommonOptions c;
        const bool wasNight = c.nightMode();
        // colorOnInk 的合法搭档是 colorInkPanel —— 两档都是深底, 所以它才允许是 CONSTANT.
        for (bool night : {false, true}) {
            c.setNightMode(night);
            QVERIFY2(contrastRatio(c.colorInkPanel(), c.colorOnInk()) >= 4.5,
                     qPrintable(QStringLiteral("%1 墨底仪表对比不足")
                                .arg(night ? "夜晚" : "白天")));
        }
        c.setNightMode(wasNight);
    }

    // ===== 危险档文案 (2026-10-26 任务 #122 A27 的弹层那一半) =====
    // 这套档位文案原先只存在于 FieldGuideDetailPage 的四段三元里, 地图标注弹层想报
    // 危险度要么重抄一遍要么干脆不说 (真机就是"只剩经纬度"). 收口到 CommonOptions 之后
    // 必须有测试: 越界一律空串 = "不给假读数"那条铁律, 一旦有人把它改成回 0 档,
    // 毒蛇的点位会在危险档还没查到时被写成"基本无害".
    void danger_label_maps_each_tier() {
        CommonOptions c;
        QCOMPARE(c.dangerLevelLabel(5), QStringLiteral("危险/致命"));
        QCOMPARE(c.dangerLevelLabel(4), QStringLiteral("危险/致命"));
        QCOMPARE(c.dangerLevelLabel(3), QStringLiteral("中毒/有害"));
        QCOMPARE(c.dangerLevelLabel(2), QStringLiteral("慎用/微毒"));
        QCOMPARE(c.dangerLevelLabel(1), QStringLiteral("慎用/微毒"));
        QCOMPARE(c.dangerLevelLabel(0), QStringLiteral("基本无害"));
        // 四档语义互不相同, 不然配色与文字会指向不同档位却看不出矛盾
        QSet<QString> distinct { c.dangerLevelLabel(0), c.dangerLevelLabel(1),
                                 c.dangerLevelLabel(3), c.dangerLevelLabel(4) };
        QCOMPARE(distinct.size(), 4);
    }

    void danger_label_says_nothing_when_unknown() {
        CommonOptions c;
        // -1 = MapPage.dangerLevelOf() 的"缓存未就绪"; 6 = 数据越界. 两者都不许出字.
        QVERIFY(c.dangerLevelLabel(-1).isEmpty());
        QVERIFY(c.dangerLevelLabel(6).isEmpty());
        // 反向对照: 上面两条若是因为"全部返回空串"而通过, danger_label_maps_each_tier
        // 会炸; 这里再钉一次 0 档确实有字, 免得把"未知"与"基本无害"混成一类.
        QVERIFY(!c.dangerLevelLabel(0).isEmpty());
    }

    // === 端点坐标可信度读数 (2026-10-27 #131) ================================
    // 地图已选清单的读数条、路线详情、自驾详情读同一个口径: 库里 753 条的量化误差
    // 从 ±10 米 (实测 GPS) 一直铺到 ±56 公里 (整数度坐标), 单位换算错了就会把
    // "一片县" 报成 "一个路口"。
    void coord_precision_label_scales_units() {
        CommonOptions c;
        QCOMPARE(c.coordPrecisionLabel(10), QStringLiteral("±10 米"));
        QCOMPARE(c.coordPrecisionLabel(560), QStringLiteral("±560 米"));
        QCOMPARE(c.coordPrecisionLabel(1100), QStringLiteral("±1.1 公里"));
        QCOMPARE(c.coordPrecisionLabel(5600), QStringLiteral("±5.6 公里"));
        QCOMPARE(c.coordPrecisionLabel(56000), QStringLiteral("±56 公里"));
    }

    void coord_label_says_nothing_when_unknown() {
        CommonOptions c;
        // 0 = 库里没标, 负数 = 数据坏了: 都不许编一个读数出来。
        QVERIFY(c.coordPrecisionLabel(0).isEmpty());
        QVERIFY(c.coordPrecisionLabel(-5).isEmpty());
        // 反向对照: 不是因为"全部返回空串"才通过
        QVERIFY(!c.coordPrecisionLabel(10).isEmpty());

        QCOMPARE(c.coordSourceLabel(QStringLiteral("city_center")), QStringLiteral("城区中心点"));
        QCOMPARE(c.coordSourceLabel(QStringLiteral("gps_track_2bulu")), QStringLiteral("GPS 实测轨迹"));
        QCOMPARE(c.coordSourceLabel(QStringLiteral("editorial_estimate")), QStringLiteral("编者估计位置"));
        // 没见过的来源键不贴标签 —— 猜一个来源就是给数据编来历
        QVERIFY(c.coordSourceLabel(QString()).isEmpty());
        QVERIFY(c.coordSourceLabel(QStringLiteral("made_up_source")).isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestCommonOptions)
#include "test_common_options.moc"
