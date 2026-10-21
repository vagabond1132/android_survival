/**
 * @file BearingBar.qml
 * @brief 方位条 — 把一个 0..360° 的方位摊到一条横向刻度带上 (2026-10-20 丁骨架 ③)
 *
 * 为什么不是盘: 详情页要说的是"这个物种在你哪个方向、多远", 一条带子能同时放下
 * 角度、8 方位汉字和距离, 而且不需要用户理解罗盘刻度. 盘留给①⑤的"我在朝哪看".
 *
 * 三条规则:
 *   ① `hasBearing` 为 false 时菱形不画, 带子退回成一把没有读数的尺 —— 没有标注位置
 *      就没有方位, 拿 0° 顶替等于在野外指一个假方向.
 *   ② 刻度标签 "0°/90°/180°/270°/360°" 是纯数字 + 度数符号, 可以绑 monoFont;
 *      汉字方位 (西北/左前方) 由调用方另起 Text. 见 [[qml-monofont-no-cjk]].
 *   ③ 高度 = 14 带子 + 3 空隙 + 一行刻度字, 由 implicitHeight 交出去,
 *      调用方放进 ColumnLayout 即可, 不要给 preferredHeight.
 *
 * Canvas 而不是 Shape: 站内 Dial/海拔剖面/类目环都走 Canvas, 真机验证过.
 */

// 2026-10-20: 刻度 delegate 读了外层 id (tickRow / styles), 静态编译下必须有
// Bound 语义, 否则真机静默 ReferenceError —— 见 [[qml-delegate-outer-id-pragma]].
pragma ComponentBehavior: Bound
import QtQuick
import OutdoorSurvival 1.0

Item {
    id: bar

    Styles { id: styles; visible: false }

    property real bearing: 0          // 度, 正北 0 顺时针
    property bool hasBearing: false   // false = 数据里没有方位, 只画尺不画指针
    property color tone: CommonOptions.colorWater
    // 读数那一行 ("112° · 西北 · 620 m") 由调用方在卡片里自己拼 ——
    // 这里只管尺, 免得组件再拆一套 mono/汉字混排的约束出来.

    implicitWidth: 240
    implicitHeight: strip.height + 3 + tickRow.height

    // 刻度带本体
    Rectangle {
        id: strip
        width: parent.width
        height: 14
        color: CommonOptions.colorSurfaceAlt
        border.color: CommonOptions.colorRuleSoft
        border.width: styles.lineHair

        Canvas {
            id: stripCanvas
            anchors.fill: parent
            antialiasing: true

            Connections {
                target: bar
                function onHasBearingChanged() { stripCanvas.requestPaint() }
                function onBearingChanged() { stripCanvas.requestPaint() }
                function onToneChanged() { stripCanvas.requestPaint() }
            }
            Component.onCompleted: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                if (width <= 0) return
                const mid = height / 2

                // 中线
                ctx.beginPath()
                ctx.moveTo(0, mid)
                ctx.lineTo(width, mid)
                ctx.strokeStyle = CommonOptions.css(CommonOptions.colorText, 0.16)
                ctx.lineWidth = 1
                ctx.stroke()

                // 刻度: 每 30° 一格, 整 90° 加长
                for (let d = 0; d <= 360; d += 30) {
                    const x = (d / 360) * (width - 1)
                    const major = (d % 90 === 0)
                    const half = major ? 4 : 2.5
                    ctx.beginPath()
                    ctx.moveTo(x + 0.5, mid - half)
                    ctx.lineTo(x + 0.5, mid + half)
                    ctx.strokeStyle = major
                                    ? CommonOptions.css(CommonOptions.colorText, 0.55)
                                    : CommonOptions.css(CommonOptions.colorText, 0.22)
                    ctx.lineWidth = 1
                    ctx.stroke()
                }

                if (!bar.hasBearing) return
                // 菱形游标: 旋转 45°, 描一圈卡片底色让它在任何段上都分得清
                const bx = (Math.min(Math.max(((bar.bearing % 360) + 360) % 360, 0), 360)
                            / 360) * (width - 1)
                const s = 4.5
                ctx.save()
                ctx.translate(bx, mid)
                ctx.rotate(Math.PI / 4)
                ctx.beginPath()
                ctx.rect(-s, -s, 2 * s, 2 * s)
                ctx.fillStyle = CommonOptions.css(bar.tone)
                ctx.fill()
                ctx.lineWidth = 1.5
                ctx.strokeStyle = CommonOptions.css(CommonOptions.colorSurface)
                ctx.stroke()
                ctx.restore()
                // 游标所在处补一根贯通线, 远看也知道对的是哪个刻度
                ctx.beginPath()
                ctx.moveTo(bx + 0.5, 0)
                ctx.lineTo(bx + 0.5, height)
                ctx.strokeStyle = CommonOptions.css(bar.tone, 0.45)
                ctx.lineWidth = 1
                ctx.stroke()
            }
        }
    }

    // 0/90/180/270/360 五个标记: 等宽数字 (纯拉丁数字 + °, 没有汉字)
    Row {
        id: tickRow
        anchors.top: strip.bottom
        anchors.topMargin: 3
        width: parent.width
        Repeater {
            model: ["0\u00b0", "90\u00b0", "180\u00b0", "270\u00b0", "360\u00b0"]
            delegate: Text {
                required property var modelData
                required property int index
                width: tickRow.width / 5
                horizontalAlignment: index === 0 ? Text.AlignLeft
                                              : (index === 4 ? Text.AlignRight : Text.AlignHCenter)
                text: modelData
                font.family: styles.monoFont
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorInk3
            }
        }
    }
}
