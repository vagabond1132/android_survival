/**
 * @file Card.qml
 * @brief 通用内容卡片 (2026-10-19 整体改版新建)
 *
 * 高度由内容撑开: 内部 ColumnLayout 用自然高度排版, 卡片 implicitHeight =
 * 内容 + 上下内边距. 这是刻意避开 FieldGuidePage 1.jpg 那个坑 —— 该页筛选卡
 * 同时写了 `Layout.preferredHeight: filterCol.implicitHeight + 24` 和
 * `filterCol.anchors.fill: parent`, 布局高度 ↔ 子项隐式高度互相引用,
 * 真机上卡片高度抖动并把 "共 N 条" 那行盖住.
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

Rectangle {
    id: card

    property int pad: styles.cardPad
    property alias spacing: col.spacing
    // 强调色描边 (危险/救援类卡片), 默认走分隔线灰
    property color borderTone: CommonOptions.colorDivider
    default property alias content: col.data

    Styles { id: styles; visible: false }
    // 注: 上面这行会被 default 别名收进 col (见 PageHeader 头注释说的同一个坑).
    //   这是可接受的: QQuickLayout 跳过 visible:false 的项, 既不占高也不产生
    //   spacing. 若把它改成 visible:true 或删除, 会平白多出 cardGap 的间隙.

    implicitWidth: col.implicitWidth + 2 * pad
    implicitHeight: col.implicitHeight + 2 * pad
    height: implicitHeight
    Layout.preferredHeight: implicitHeight

    color: CommonOptions.colorSurface
    radius: styles.rLg
    border.color: card.borderTone
    border.width: styles.lineHair

    ColumnLayout {
        id: col
        x: card.pad
        y: card.pad
        width: card.width - 2 * card.pad
        spacing: styles.cardGap
    }
}
