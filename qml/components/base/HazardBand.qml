/**
 * @file HazardBand.qml
 * @brief 危险斜纹带 — 卡片左侧 6px 的 45° 斑马纹 (2026-10-20 「地物图例」v9)
 *
 * 为什么只有 6px: 「地物图例」的铁律是 "文字永远压在干净卡面上". 改版前危险提示
 * 用整块 rgba 红底, 强光下红底上的红字最先糊成一团; 斜纹只当"这是危险条目"的
 * 印刷边记, 语义仍由 hazard 红 (#B4290E, 全站只给 SOS 与真危险) 承担.
 *
 * 为什么自绘而不是图片: 站内没有位图资源, 打包一张 png 会为一条 6px 的边记
 * 增加 APK 体积; Canvas 与 Dial / CategoryRing / BearingBar 同一套画法.
 *
 * 高度: 本组件只给 implicitWidth (6px), 不给 implicitHeight —— 那条会绑到
 * parent.height, 而 parent 的高度又来自布局→implicitHeight, 形成绑定环.
 * 调用方锚住上下 (详情页的错项卡就是 anchors.top/bottom).
 */

import QtQuick
import OutdoorSurvival 1.0

Rectangle {
    id: band

    Styles { id: styles; visible: false }

    property color stripe: CommonOptions.colorHazard
    property real stripeAlpha: 0.42
    // 斜纹周期与线宽 (mock 的 repeating-linear-gradient: 3px 实 / 7px 一周期)
    property int period: 7
    property int thickness: 3

    implicitWidth: styles.hazardBandW
    color: CommonOptions.colorSurface

    Canvas {
        id: canvas
        anchors.fill: parent
        // Item 没有 sizeChanged 这个信号 (只有 widthChanged/heightChanged),
        // 写 onSizeChanged 是 qmllint 报 "no matching signal" 的死 handler.
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = CommonOptions.css(band.color)
            ctx.fillRect(0, 0, width, height)
            ctx.strokeStyle = CommonOptions.css(band.stripe, band.stripeAlpha)
            ctx.lineWidth = band.thickness
            // 45°: 从左下角往右上画, 起点向左多扫一个高度, 保证顶角也覆盖到
            for (var x = -band.period; x < width + height; x += band.period) {
                ctx.beginPath()
                ctx.moveTo(x, height)
                ctx.lineTo(x + height, 0)
                ctx.stroke()
            }
        }
        Component.onCompleted: requestPaint()
    }
}
