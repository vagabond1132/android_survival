/**
 * @file CameraPage.qml
 * @brief 拍照页面 (占位实现)
 *
 * 完整实现需要 QtMultimedia 摄像头预览 + OutdoorSurvivalApp 提供的 native photo path.
 * 当前版本返回到 MapPage, 后续接入 Camera QML type (Qt 6.5+ QtMultimedia).
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    id: cameraPage
    title: "拍照"

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 16
        width: parent.width * 0.8

        Text {
            text: "\ue412 相机功能"  // Material Icons: camera_alt
            font.family: "Material Icons"
            font.pixelSize: 24
            color: "white"
            Layout.alignment: Qt.AlignHCenter
        }
        Text {
            text: "当前为占位页\n需要 QtMultimedia 接入 + 拍照路径返回 MapPage"
            color: "#cccccc"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Button {
            text: "返回地图"
            Layout.alignment: Qt.AlignHCenter
            onClicked: cameraPage.ApplicationWindow.window.navBus.back()
        }
    }
}
