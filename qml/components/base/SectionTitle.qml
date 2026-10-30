/**
 * @file SectionTitle.qml
 * @brief 章节标题行 (图标 + 文字), 2026-10-16 整体改版新建
 *
 * 为什么要单独一个组件: 改版前 "图标 + 中文" 有两种写法, 都会踩同一个坑 —
 *   ① Text { text: "\ue564 海拔剖面"; font.family: "Material Icons" }
 *      → 整段文字被强塞 icon 字体, 中文只能靠 Qt 字形回退, 一旦回退失败就整行乱码;
 *   ② emoji 前缀 ("⏱ 速度分析")
 *      → 部分 Android 无该字形, 显示为方框 (run.txt / 3.jpg 报过).
 * 正确形态是图标和文字各一个节点: 图标走 IconLabel (自带字体就绪判断 + 语义名),
 * 文字保持系统 UI 字体. Section / RouteSummaryPanel / 各详情页头统一用它.
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

RowLayout {
    id: sectionTitle

    Styles { id: styles; visible: false }

    property string icon: ""                                  // IconLabel 语义名
    property string text: ""
    // 右侧小字说明 (计数后缀 / "无记录"). 走默认字族: 这里装的是汉字,
    // 汉字加字距或进 monoFont 都是上一版最刺眼的假印刷感.
    property string trailing: ""
    property color titleColor: CommonOptions.colorText
    property color iconColor: CommonOptions.colorAccent
    property real pixelSize: styles.fsLg
    property bool bold: true

    spacing: styles.spXs

    IconLabel {
        visible: sectionTitle.icon.length > 0
        name: sectionTitle.icon
        size: Math.round(sectionTitle.pixelSize)
        tintColor: sectionTitle.iconColor
    }
    Text {
        Layout.fillWidth: true
        text: sectionTitle.text
        color: sectionTitle.titleColor
        font.pixelSize: sectionTitle.pixelSize
        font.bold: sectionTitle.bold
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
    Text {
        visible: sectionTitle.trailing.length > 0
        text: sectionTitle.trailing
        // trailing 现在装的是汉字说明 (原先是 ROUTES/ITEMS 一类拉丁微标签).
        //   不走 monoFont: 那套字体没有中文字形, 真机上回退失败出方框; 字距同理只给拉丁.
        font.pixelSize: styles.fsXs
        color: CommonOptions.colorInk3
        verticalAlignment: Text.AlignVCenter
    }
}
