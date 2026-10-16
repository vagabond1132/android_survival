/**
 * @file Styles.qml
 * @brief 设计 token - 间距 / 字号 / 圆角 (2026-09-14 UI 改版)
 *
 * CommonOptions 装颜色, Styles 装布局尺寸.
 * 不是一个 QML 单例 (避免上次 qmlcachegen 静态编译 + pragma Singleton 的坑),
 * 而是普通 Item. 在 Page 顶部 `Styles { id: S }` 实例化, 然后 S.spLg 用.
 *
 * 所有属性 readonly, 多实例不会冲突, 也不会有运行时开销.
 */

import QtQuick

Item {
    id: styleRoot

    // === 间距 (8 倍数) ===
    readonly property int spXs: 4    // 极小, 标签内边距
    readonly property int spSm: 8    // 小, 卡片内边距 / 控件间距
    readonly property int spMd: 12   // 中, 行间距
    readonly property int spLg: 16   // 大, 区块外边距
    readonly property int spXl: 24   // 超大, section 分隔

    // === 字号 ===
    readonly property int fsXs: 10   // 极小提示
    readonly property int fsSm: 12   // 标签 / 副标题
    readonly property int fsMd: 14   // 正文
    readonly property int fsLg: 16   // 卡片标题
    readonly property int fsXl: 18   // 区块标题
    readonly property int fs2xl: 22  // 页面 hero
    readonly property int fs3xl: 28  // 统计数字

    // === 圆角 ===
    readonly property int rSm: 4     // 小, 标签 / chip
    readonly property int rMd: 8     // 中, 卡片
    readonly property int rLg: 12    // 大, 弹窗
    readonly property int rXl: 16    // 超大, hero 卡片
}
