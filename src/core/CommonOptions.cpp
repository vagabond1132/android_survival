/**
 * @file CommonOptions.cpp
 * @brief 通用下拉选项 + 格式化函数实现
 */
#include "CommonOptions.h"

// 构造函数在头文件内联定义 (CommonOptions.h:28)

QVariantList CommonOptions::difficultyOptions() const {
    return QVariantList{
        QVariantMap{{"value", 1}, {"label", "1 入门"}},
        QVariantMap{{"value", 2}, {"label", "2 简单"}},
        QVariantMap{{"value", 3}, {"label", "3 中等"}},
        QVariantMap{{"value", 4}, {"label", "4 困难"}},
        QVariantMap{{"value", 5}, {"label", "5 极难"}}
    };
}

QVariantList CommonOptions::daysOptions() const {
    return QVariantList{
        QVariantMap{{"value", 0}, {"label", "全部"}},
        QVariantMap{{"value", 2}, {"label", "1-2 天"}, {"minDays", 1}, {"maxDays", 2}},
        QVariantMap{{"value", 3}, {"label", "3-5 天"}, {"minDays", 3}, {"maxDays", 5}},
        QVariantMap{{"value", 4}, {"label", "6-10 天"}, {"minDays", 6}, {"maxDays", 10}},
        QVariantMap{{"value", 5}, {"label", "10+ 天"}, {"minDays", 11}, {"maxDays", 99}}
    };
}

QVariantList CommonOptions::distanceOptions() const {
    return QVariantList{
        QVariantMap{{"value", 0}, {"label", "全部"}},
        QVariantMap{{"value", 1}, {"label", "< 500 km"}, {"minKm", 0.0}, {"maxKm", 500.0}},
        QVariantMap{{"value", 2}, {"label", "500-1000 km"}, {"minKm", 500.0}, {"maxKm", 1000.0}},
        QVariantMap{{"value", 3}, {"label", "1000-2000 km"}, {"minKm", 1000.0}, {"maxKm", 2000.0}},
        QVariantMap{{"value", 4}, {"label", "> 2000 km"}, {"minKm", 2000.0}, {"maxKm", 99999.0}}
    };
}

QVariantList CommonOptions::monthOptions() const {
    QVariantList list;
    list.append(QVariantMap{{"value", 0}, {"label", "全部"}});
    // 2026-09-14: 修复"月份下拉框只有全部"bug, 加上 1-12 月
    for (int m = 1; m <= 12; ++m) {
        list.append(QVariantMap{{"value", m}, {"label", QString::number(m) + "月"}});
    }
    return list;
}

QVariantList CommonOptions::kingdomOptions() const {
    // 2026-10-08: 修 - 之前用 emoji (🌿/🐍/🐝/🍄) 作图标, Android 默认字体无
    //   彩色 emoji 字形 → 真机显示为方框. 改用 Material Icons PUA 码位, 与
    //   FieldGuidePage / FieldGuideImagePickPage 的本地 kingdomOptions 保持一致
    //   (码位均已确认包含在 assets/fonts/MaterialIcons-Regular.ttf 中).
    //   消费方需把下拉框 font.family 设为 "Material Icons" 才能出图.
    return QVariantList{
        QVariantMap{{"value", 0}, {"label", "\ue406 植物"}},  // nature (叶子)
        QVariantMap{{"value", 1}, {"label", "\ue91a 动物"}},
        QVariantMap{{"value", 2}, {"label", "\ue1b9 昆虫"}},
        QVariantMap{{"value", 3}, {"label", "\ue239 蘑菇"}}   // emoji_nature
    };
}

QVariantList CommonOptions::routeNatureOptions() const {
    return QVariantList{
        QVariantMap{{"value", ""}, {"label", "全部"}},
        QVariantMap{{"value", "穿越"}, {"label", "穿越"}},
        QVariantMap{{"value", "环线"}, {"label", "环线"}},
        QVariantMap{{"value", "单程"}, {"label", "单程"}}
    };
}

QString CommonOptions::formatDistance(double km) const {
    if (km < 1.0) return QString::number(km * 1000.0, 'f', 0) + " m";
    return QString::number(km, 'f', 1) + " km";
}

QString CommonOptions::formatElevation(double m) const {
    return QString::number(m, 'f', 0) + " m";
}

QString CommonOptions::formatDuration(qint64 sec) const {
    if (sec < 60) return QString::number(sec) + " 秒";
    if (sec < 3600) return QString::number(sec / 60) + " 分";
    return QString::number(sec / 3600) + " 小时";
}

QString CommonOptions::difficultyLabel(int level) const {
    static const QStringList labels = {"入门", "简单", "中等", "困难", "极难"};
    if (level < 1 || level > 5) return "";
    return labels[level - 1];
}

QString CommonOptions::routeNatureLabel(const QString& key) const {
    if (key.isEmpty()) return "全部";
    return key;
}
