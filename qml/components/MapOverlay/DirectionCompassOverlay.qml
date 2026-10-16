/**
 * @file DirectionCompassOverlay.qml
 * @brief 方向指针 (中央叠加, 旋转随 heading)
 *
 * 用 MapQuickItem 放在地图中心, 内部 Rectangle 旋转.
 * heading 来源: mapService.getCurrentHeading() (MapService 已实现 position source)
 * 0=北, 90=东, 180=南, 270=西. 顺时针.
 */
import QtQuick
import QtQuick.Controls.Material
import QtPositioning
import QtLocation
import OutdoorSurvival 1.0

MapQuickItem {
    id: root

    // 由外层 MapPage 传入
    property real heading: 0.0      // 0-360 度
    property bool hasFix: false      // GPS 是否已定位

    // 钉在地图中心点
    coordinate: map ? map.center : QtPositioning.coordinate(0, 0)
    anchorPoint.x: width / 2
    anchorPoint.y: height / 2

    // 不允许被地图拖动
    visible: hasFix

    sourceItem: Item {
        width: 96
        height: 96

        // 外圈
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#CC1A237E"
            border.color: "white"
            border.width: 2
        }

        // 内部旋转指针
        Item {
            anchors.fill: parent
            rotation: -root.heading   // 地图北朝上, 反向旋转指针朝向"前进方向"

            // 北三角 (红色)
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var cx = width / 2
                    var cy = height / 2
                    var r = width / 2 - 8

                    // 红色北箭头
                    ctx.fillStyle = "#F44336"
                    ctx.beginPath()
                    ctx.moveTo(cx, cy - r)
                    ctx.lineTo(cx - 12, cy)
                    ctx.lineTo(cx + 12, cy)
                    ctx.closePath()
                    ctx.fill()

                    // 灰色南箭头
                    ctx.fillStyle = "#90A4AE"
                    ctx.beginPath()
                    ctx.moveTo(cx, cy + r)
                    ctx.lineTo(cx - 12, cy)
                    ctx.lineTo(cx + 12, cy)
                    ctx.closePath()
                    ctx.fill()

                    // 中心圆点
                    ctx.fillStyle = "white"
                    ctx.beginPath()
                    ctx.arc(cx, cy, 4, 0, Math.PI * 2)
                    ctx.fill()
                }
            }
        }

        // 标题 (固定不旋转)
        Text {
            anchors.centerIn: parent
            text: "N"
            color: "white"
            font.pixelSize: 10
            font.bold: true
            y: parent.height / 2 - 28
        }
    }
}
