/**
 * @file MapRightButtonColumn.qml
 * @brief 右侧浮动按钮列 (标注 / 拍照 / 居中 / 轨迹 / 危险标记)
 *
 * 2026-09-15 改版:
 *   - 图标统一用 Material Icons 字体字符 (main.cpp 已 addApplicationFont 加载)
 *   - 位置贴右"中间" (vertical center, 而非 bottom-200) — 更符合主流地图 App
 *   - 2026-09-15: 移除 ToolTip 附加属性, 避免 QML 加载时 Component not ready
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts

Item {
    id: root

    signal annotateClicked()
    signal captureClicked()
    signal centerClicked()
    signal trackSheetClicked()
    signal dangerMarkClicked()
    signal baseMapClicked()  // 2026-10-09: 底图切换 (地形/路网/卫星)

    // 2026-09-15: 贴右、垂直居中, 不再贴底
    anchors.right: parent ? parent.right : undefined
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    anchors.rightMargin: 12

    width: 56
    height: column.implicitHeight + 16

    // 2026-09-16: 加 z 值, 确保按钮在 Map 之上, TapHandler 拦截事件不被 Map 吃掉
    z: 1000

    Column {
        id: column
        anchors.centerIn: parent
        spacing: 12

        // 标注
        Rectangle {
            id: markBtn
            width: 56
            height: 56
            radius: 28
            color: "#1A237E"
            border.color: "white"
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "\ue55f"  // Material Icons: room
                color: "white"
                font.family: "Material Icons"
                font.pixelSize: 26
            }
            // 2026-09-16: TapHandler + ToolTip 替代 MouseArea, 触屏可靠
            TapHandler {
                id: markTap
                onTapped: root.annotateClicked()
            }
            // 2026-09-17: ToolTip.visible 必须绑 TapHandler.pressed, 不绑 Rectangle.pressed
            // (Rectangle 没有 pressed 属性, 原来"看起来"工作是因为 TapHandler 在 QML6 把
            // pressed 暴露到 children context, 但不可靠. 显式通过 id 引用更稳)
            ToolTip.visible: markTap.pressed
            ToolTip.delay: 500
            ToolTip.text: "标注当前位置"
        }

        // 拍照
        Rectangle {
            id: captureBtn
            width: 56
            height: 56
            radius: 28
            color: "#D32F2F"
            border.color: "white"
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "\ue412"  // Material Icons: photo_camera
                color: "white"
                font.family: "Material Icons"
                font.pixelSize: 26
            }
            TapHandler {
                id: captureTap
                onTapped: root.captureClicked()
            }
            ToolTip.visible: captureTap.pressed
            ToolTip.delay: 500
            ToolTip.text: "拍照并标注"
        }

        // 居中
        Rectangle {
            id: centerBtn
            width: 56
            height: 56
            radius: 28
            color: "#2E7D32"
            border.color: "white"
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "\ue55b"  // Material Icons: my_location
                color: "white"
                font.family: "Material Icons"
                font.pixelSize: 26
            }
            TapHandler {
                id: centerTap
                onTapped: root.centerClicked()
            }
            ToolTip.visible: centerTap.pressed
            ToolTip.delay: 500
            ToolTip.text: "居中到我的位置"
        }

        // 轨迹
        Rectangle {
            id: trackBtn
            width: 56
            height: 56
            radius: 28
            color: "#01579B"
            border.color: "white"
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "\ue566"  // Material Icons: timeline
                color: "white"
                font.family: "Material Icons"
                font.pixelSize: 26
            }
            TapHandler {
                id: trackTap
                onTapped: root.trackSheetClicked()
            }
            ToolTip.visible: trackTap.pressed
            ToolTip.delay: 500
            ToolTip.text: "轨迹记录 / 导航"
        }

        // 危险标记
        Rectangle {
            id: dangerBtn
            width: 56
            height: 56
            radius: 28
            color: "#E65100"
            border.color: "white"
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "\ue002"  // Material Icons: warning
                color: "white"
                font.family: "Material Icons"
                font.pixelSize: 26
            }
            TapHandler {
                id: dangerTap
                onTapped: root.dangerMarkClicked()
            }
            ToolTip.visible: dangerTap.pressed
            ToolTip.delay: 500
            ToolTip.text: "危险物种 / 兴趣点"
        }

        // 底图切换 (2026-10-09: 新增第 6 个按钮, 弹 Menu 选 地形/路网/卫星)
        Rectangle {
            id: baseMapBtn
            width: 56
            height: 56
            radius: 28
            color: "#37474F"
            border.color: "white"
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "\ue1b8"  // Material Icons: layers
                color: "white"
                font.family: "Material Icons"
                font.pixelSize: 26
            }
            TapHandler {
                id: baseMapTap
                onTapped: root.baseMapClicked()
            }
            ToolTip.visible: baseMapTap.pressed
            ToolTip.delay: 500
            ToolTip.text: "切换底图"
        }
    }
}
