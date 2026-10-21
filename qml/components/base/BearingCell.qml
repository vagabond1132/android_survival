/**
 * @file BearingCell.qml
 * @brief 方位列 — 列表行左侧 50px 的"离我多远 / 在哪个方位"列 (2026-10-20 丁骨架)
 *
 * 丁的②资源不是按字母或目录排, 是按"离你多远"排, 所以每行第一位读的是方位不是标题.
 * 这一列宽固定在 styles.bearingColW (50px): 再宽就吃掉标题, 再窄 3 位角度数会挤.
 *
 * 色 = 类别 (绿植被 / 蓝水源 / 橙火 / 红危险 / 紫路线), 由调用方用 tone 传进来,
 * 列本身不自选色 —— 保持"颜色只承载含义"这一条.
 *
 * 角度用等宽: 112° 与 8° 必须右边界对齐, 比例字体下会跳.
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: cell

    Styles { id: styles; visible: false }

    property real bearing: 0          // 度, 正北 0 顺时针
    property real distanceM: -1       // 米; <0 表示不显示距离
    property string icon: ""          // IconLabel 名
    property color tone: CommonOptions.colorTextMuted
    property bool showCompass: false  // ①营地的两格要"山脊/河谷"这类 8 方位汉字
    // ②图鉴里绝大多数物种没有坐标 (数据只有省份分布), 这一列就只剩类别图标.
    // 角度必须能整条关掉 —— 不能靠 bearing=0 骗过去: 0° 在野外是"正北",
    // 一个没有方位的物种顶上写 0° 就是把读数编出来了.
    property bool showBearing: true

    implicitWidth: styles.bearingColW
    implicitHeight: col.implicitHeight
    width: implicitWidth

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: 1

        IconLabel {
            name: cell.icon
            size: styles.icSm
            tintColor: cell.tone
            visible: cell.icon.length > 0
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            visible: cell.showBearing
            text: String(Math.round(((cell.bearing % 360) + 360) % 360)) + "\u00b0"
            font.family: styles.monoFont
            font.pixelSize: styles.fsXs
            color: cell.tone
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            visible: cell.showCompass
            text: CommonOptions.compassLabel(cell.bearing)
            font.pixelSize: styles.fsXs
            color: CommonOptions.colorTextDim
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // 距离不画在这一列里 (50px 装不下 "620 m" + 角度), 交给行右侧
    function distanceText() {
        return cell.distanceM < 0 ? "" : CommonOptions.formatBearingDistance(cell.distanceM)
    }
}
