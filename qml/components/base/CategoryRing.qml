/**
 * @file CategoryRing.qml
 * @brief 类目占比环 — ②图鉴页的"这一类里各占多少"仪表 (2026-10-20 丁骨架)
 *
 * 为什么要有它: 图鉴有 4 个界门 × 每界十几种类目, 光看筛选器不知道"点进去有多少条".
 * 环把当前筛选结果按类目拆开, 中心是总数 —— 一眼知道"这一屏 384 条里野菜占 168",
 * 决定要不要再筛. 选中的类目画实色, 其余压到 0.32 透明度, 所以环和下面那排 chip
 * 是同一个状态的两个视图, 不另存一份"环上选中".
 *
 * 环本身不可点 (与 Dial 的 pips 同一条规则: 盘上的色块是"发现"不是按钮,
 * 64px 环上的弧戴手套点不准). 筛选走 chip, 环只跟着变.
 *
 * Canvas 而不是 Shape: 站内自绘环/Dial/海拔剖面都走 Canvas, 真机验证过.
 * 中心两行是 QML Text 叠层 —— 文字画进 Canvas 在 2x 屏上会发虚.
 */

import QtQuick
import OutdoorSurvival 1.0

Item {
    id: ring

    Styles { id: styles; visible: false }

    // [{ value: 168, tone: CommonOptions.colorForest, active: true }, ...]
    // value 只许是数字; active 缺省当作 true
    property var segments: []
    // 有类目被选中时才把其余弧压淡; 没选中(全部)时整环都是实色
    property bool hasSelection: false
    property string centerValue: ""   // 等宽: 只装数字与拉丁
    property string centerLabel: ""   // 默认字族, 装汉字 ("总计")
    property real diameter: 64
    property color trackColor: CommonOptions.colorRuleSoft

    implicitWidth: diameter
    implicitHeight: diameter

    Canvas {
        id: ringCanvas
        anchors.fill: parent
        antialiasing: true

        // segments/hasSelection 是 ring 上的信号, 不是 Canvas 自己的属性 ——
        // 只能经 Connections 转发 requestPaint (写成 onSegmentsChanged: 到 Canvas 里
        // 就是给不存在的属性赋值, 加载期报错).
        Connections {
            target: ring
            function onSegmentsChanged() { ringCanvas.requestPaint() }
            function onHasSelectionChanged() { ringCanvas.requestPaint() }
            function onDiameterChanged() { ringCanvas.requestPaint() }
            function onTrackColorChanged() { ringCanvas.requestPaint() }
        }

        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (width <= 0 || height <= 0) return

            const lw = Math.max(6, Math.round(ring.diameter * 0.14))
            const r = (Math.min(width, height) - lw) / 2
            const cx0 = width / 2
            const cy0 = height / 2

            // 底环: 总数为 0 时剩下的就是它 —— 空环 ≠ 没有这个部件
            ctx.beginPath()
            ctx.arc(cx0, cy0, r, 0, 2 * Math.PI)
            ctx.strokeStyle = CommonOptions.css(ring.trackColor)
            ctx.lineWidth = lw
            ctx.stroke()

            let total = 0
            for (let i = 0; i < ring.segments.length; ++i)
                total += Number(ring.segments[i].value) || 0
            if (total <= 0) return

            // 段间留一道空白: 五段挨着画会糊成一圈, 分不出哪段是哪类
            const gap = ring.segments.length > 1 ? 0.05 : 0
            let angle = -Math.PI / 2      // 12 点起, 顺时针 (与 Dial 同一起点)
            for (let s = 0; s < ring.segments.length; ++s) {
                const seg = ring.segments[s]
                const v = Number(seg.value) || 0
                const span = (v / total) * 2 * Math.PI
                if (v > 0) {
                    const from = angle + gap / 2
                    const to = angle + span - gap / 2
                    if (to > from) {
                        const dim = (ring.hasSelection && seg.active === false)
                        ctx.beginPath()
                        ctx.arc(cx0, cy0, r, from, to)
                        ctx.strokeStyle = CommonOptions.css(seg.tone, dim ? 0.32 : 1.0)
                        ctx.lineWidth = lw
                        ctx.stroke()
                    }
                }
                angle += span
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: ring.centerValue.length > 0
            text: ring.centerValue
            font.family: styles.monoFont
            font.pixelSize: Math.max(10, Math.round(ring.diameter * 0.19))
            color: CommonOptions.colorText
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: ring.centerLabel.length > 0
            text: ring.centerLabel
            // 中心名是汉字 (总计/条目), 走 monoFont 就是方框; 字距同理只给拉丁
            font.pixelSize: styles.fsXs
            color: CommonOptions.colorTextDim
        }
    }
}
