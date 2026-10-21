/**
 * @file ListRow.qml
 * @brief 通用列表行: 图标底板 + 标题/副标题 + 右侧值/箭头 (2026-10-19 整体改版新建)
 *
 * 6.jpg 首页 "动植物图鉴" 那行副标题溢出到屏幕外、箭头被压住, 根因是各页自己
 * 抄的行布局里 Text 没绑 Layout.fillWidth 也没 elide. 本组件把标题/副标题/值
 * 三段全部约束在 RowLayout 内并 elide, 页面只需要传文案.
 */

import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

Rectangle {
    id: row

    property string title: ""
    property string subtitle: ""
    property string value: ""          // 右侧值 (如 "1.2km" / "已完成")
    property string detail: ""         // 右侧值下方的辅助说明
    property string iconName: ""
    property string badgeText: ""      // 左侧文字胶囊 (无对应图标字形时用)
    property color accent: CommonOptions.colorAccent
    property color titleColor: CommonOptions.colorText
    property color subtitleColor: CommonOptions.colorTextMuted
    property bool showChevron: true
    property bool dense: false
    property color bg: CommonOptions.colorSurface

    signal clicked()

    Styles { id: styles; visible: false }

    implicitHeight: dense ? styles.rowH : styles.rowHTall
    height: implicitHeight
    Layout.preferredHeight: implicitHeight
    radius: styles.rLg
    color: bg
    border.color: CommonOptions.colorDivider
    border.width: styles.lineHair

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: styles.spMd
        anchors.rightMargin: styles.spMd
        anchors.topMargin: styles.spSm
        anchors.bottomMargin: styles.spSm
        spacing: styles.spMd

        Rectangle {
            visible: row.iconName.length > 0
            Layout.preferredWidth: row.dense ? styles.icBoxSm : styles.icBoxLg
            Layout.preferredHeight: row.dense ? styles.icBoxSm : styles.icBoxLg
            Layout.alignment: Qt.AlignVCenter
            radius: styles.rMd
            color: CommonOptions.withAlpha(row.accent, 0.16)
            IconLabel {
                anchors.centerIn: parent
                name: row.iconName
                size: row.dense ? styles.icSm : styles.icMd
                tintColor: row.accent
            }
        }

        Rectangle {
            id: badgeBox
            visible: row.badgeText.length > 0
            // 2026-10-19 真机: Rectangle 的 implicitWidth 默认 0, 而 RowLayout 在没有
            //   Layout.preferredWidth 时按 implicitWidth 分配宽度 → 胶囊宽 0, 里面的
            //   Text 靠 anchors.centerIn 溢出绘制, 直接压在标题上 (急救手册"危急"、
            //   危险物种"蛇类"全部串位)。宽度必须由标签自身撑出来。
            Layout.preferredWidth: badgeLabel.implicitWidth
            Layout.maximumWidth: 76
            Layout.preferredHeight: styles.chipH
            Layout.alignment: Qt.AlignVCenter
            radius: styles.rPill
            color: CommonOptions.withAlpha(row.accent, 0.16)
            Text {
                id: badgeLabel
                anchors.centerIn: parent
                text: row.badgeText
                color: row.accent
                font.pixelSize: styles.fsSm
                font.bold: true
                elide: Text.ElideRight
                leftPadding: styles.spSm
                rightPadding: styles.spSm
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: styles.spXs
            Text {
                Layout.fillWidth: true
                text: row.title
                color: row.titleColor
                font.pixelSize: styles.fsLg
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: row.subtitle.length > 0
                text: row.subtitle
                color: row.dense ? CommonOptions.colorTextDim : row.subtitleColor
                font.pixelSize: styles.fsSm
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            visible: row.value.length > 0 || row.detail.length > 0
            spacing: 0
            Text {
                text: row.value
                color: row.accent
                font.pixelSize: styles.fsMd
                font.bold: true
                elide: Text.ElideRight
                Layout.maximumWidth: 110
            }
            Text {
                visible: row.detail.length > 0
                text: row.detail
                color: CommonOptions.colorTextDim
                font.pixelSize: styles.fsXs
                elide: Text.ElideRight
                Layout.maximumWidth: 110
            }
        }

        IconLabel {
            visible: row.showChevron
            name: "chevron_right"
            size: styles.icMd
            Layout.alignment: Qt.AlignVCenter
            tintColor: CommonOptions.colorTextDisabled
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: row.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
