/**
 * @file Dial.qml
 * @brief 野外方位盘 — 丁骨架的主仪表 (2026-10-20)
 *
 * 与 DirectionCompassOverlay.qml 的分工: 那个是地图上跟着平移缩放的指针环,
 * 这个是页面里的"读数 + 发现"仪表. 两者不要混用.
 *
 * 画法照已评审的 mock: 一切画在 200×200 的归一坐标里, 尺寸只由 width/height 决定,
 * 所以 ①营地 用 styles.dialSize(130) 而⑤求助/地图页展开用 styles.dialSizeLg(200),
 * 不用改任何绘制参数.
 *
 * 三条设计约束 (改动前先读):
 *   ① 盘上的点 (pips) 只作"发现", 不作点击目标. 130px 盘上的点是 6px, 戴手套点不准,
 *      而且它一旦可点, 盘的直径就不能再缩 —— ①营地的整屏预算会崩.
 *      可点的是盘右侧读数栏和下方 4 个方位格, 由调用方自己接 MouseArea.
 *   ② 指针是 heading (设备朝向), 不随用户位置变. 位置变了变的是 sectors 与 pips.
 *   ③ 色 = 类别 (绿植被/蓝水源/橙火/红危险/紫路线), 由 targets 自己带 tone 进来.
 *
 * Canvas 而不是 Shape: 站内海拔剖面已经在用 Canvas, 有先例且真机验证过;
 * Shape/ShapePath 的 dash 要自己分段, 同等效果代码量翻倍.
 */

import QtQuick
import OutdoorSurvival 1.0

Item {
    id: dial

    Styles { id: styles; visible: false }

    // 归一绘制坐标: 一切按 200×200 设计, 再整体缩到实际边长
    readonly property real k: width / 200

    property real heading: 0            // 设备朝向, 0=北 顺时针
    property bool hasFix: true          // 没定位时盘变灰、指针不画
    // ⑤求助的迷你盘画在墨底仪表里: 描边/刻度/盘心整套色要跟着底色翻面,
    // 否则 paper 底设计的深墨描边压在 #0E1614 上等于看不见.
    property bool onInk: false
    // 盘心三行: 大字读数 / 拉丁微标签 / 状态
    property string hubValue: "--"
    property string hubLabel: "HEADING"
    property string hubSub: ""
    property color hubSubColor: CommonOptions.colorBlaze
    // [{ bearing: 112, tone: "#0C6C9E" }, ...]
    property var targets: []
    // [{ from: 95, to: 130, tone: "#0C6C9E" }, ...]  扇区 = 该方向上确有某类地物
    property var sectors: []

    implicitWidth: styles.dialSize
    implicitHeight: implicitWidth

    // 指针平滑: 朝向是传感器逐帧推的, 不做插值会抖成一片糊
    Behavior on heading {
        RotationAnimator { duration: 260 }
    }

    Canvas {
        id: cx
        anchors.fill: parent
        antialiasing: true

        // 依赖项变了就重画. 注意: heading/targets/sectors 是 dial 的信号, 不是
        // Canvas 自己的属性 —— 写成 onHeadingChanged: 会被当成 "给 Canvas 赋值
        // 一个不存在的属性", QML 加载期直接报错. 只能通过 Connections 监听.
        Connections {
            target: dial
            function onHeadingChanged() { cx.requestPaint() }
            function onTargetsChanged() { cx.requestPaint() }
            function onSectorsChanged() { cx.requestPaint() }
            function onHasFixChanged() { cx.requestPaint() }
            function onOnInkChanged() { cx.requestPaint() }
            function onHubValueChanged() { cx.requestPaint() }
        }

        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        // 200×200 归一坐标里的圆心与半径
        readonly property real cx0: 100 * dial.k
        readonly property real cy0: 100 * dial.k
        readonly property real rOut: 96 * dial.k

        function pt(deg, rad) {
            // 屏幕 y 向下, 所以角度换算时把"北=上"放在 -90°
            const a = (deg - 90) * Math.PI / 180
            return [cx0 + rad * Math.cos(a), cy0 + rad * Math.sin(a)]
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (dial.width <= 0) return

            const ink = dial.onInk ? CommonOptions.css(CommonOptions.colorOnInk)
                                   : CommonOptions.css(CommonOptions.colorText)
            const rule = dial.onInk ? CommonOptions.css(CommonOptions.colorOnInkDim, 0.8)
                                     : CommonOptions.css(CommonOptions.colorRule)
            const ruleSoft = dial.onInk ? CommonOptions.css(CommonOptions.colorOnInkDim, 0.45)
                                         : CommonOptions.css(CommonOptions.colorRuleSoft)
            const dim = dial.onInk ? CommonOptions.css(CommonOptions.colorOnInkDim)
                                    : CommonOptions.css(CommonOptions.colorTextDim)
            // pip 外圈用"卡片底色"描一圈, 墨底时底色就是 inkPanel
            const card = dial.onInk ? CommonOptions.css(CommonOptions.colorInkPanel)
                                     : CommonOptions.css(CommonOptions.colorSurface)

            // === 1. 外环 (印刷 hairline, 不是 Material 描边) ===
            ctx.beginPath()
            ctx.arc(cx0, cy0, rOut, 0, 2 * Math.PI)
            ctx.strokeStyle = rule
            ctx.lineWidth = 1
            ctx.stroke()

            // === 2. 刻度环: 每 5° 一格 (mock 的 stroke-dasharray "1.4 6.8") ===
            for (let d = 0; d < 360; d += 5) {
                const cardinal = (d % 90 === 0)
                const major = (d % 30 === 0)
                const len = cardinal ? 8 * dial.k : (major ? 5 * dial.k : 2.6 * dial.k)
                const p1 = pt(d, rOut)
                const p2 = pt(d, rOut - len)
                ctx.beginPath()
                ctx.moveTo(p1[0], p1[1])
                ctx.lineTo(p2[0], p2[1])
                ctx.strokeStyle = cardinal ? ink : (major ? ink : rule)
                ctx.lineWidth = cardinal ? 1.4 : 1
                ctx.stroke()
            }

            // === 3. 四象限微标签 (拉丁才允许字距感, 这里直接用小号等宽) ===
            ctx.fillStyle = dim
            ctx.font = (7 * dial.k).toFixed(1) + "px " + styles.monoFont
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            const lblR = rOut - 15 * dial.k
            const labels = [["N", 0], ["E", 90], ["S", 180], ["W", 270]]
            for (let i = 0; i < labels.length; ++i) {
                const p = pt(labels[i][1], lblR)
                ctx.fillText(labels[i][0], p[0], p[1])
            }

            // === 4. 扇区 (类别色弧带, 半径带内) ===
            const rSec = rOut - 13 * dial.k
            ctx.lineWidth = 5 * dial.k
            for (let s = 0; s < dial.sectors.length; ++s) {
                const sec = dial.sectors[s]
                ctx.beginPath()
                // Canvas 弧度: 0 = 3 点方向, 所以要 -90° 把"北"搬到 12 点
                ctx.arc(cx0, cy0, rSec,
                        (sec.from - 90) * Math.PI / 180,
                        (sec.to - 90) * Math.PI / 180)
                ctx.strokeStyle = CommonOptions.css(sec.tone, 0.85)
                ctx.stroke()
            }

            // === 5. 目标点: 只作发现, 不作点击 (见文件头 ①) ===
            const rPip = rOut - 30 * dial.k
            const pipR = (dial.width >= 180 ? styles.dialPipLg / 2 : styles.dialPip / 2) * dial.k
            for (let t = 0; t < dial.targets.length; ++t) {
                const tg = dial.targets[t]
                const p = pt(tg.bearing, rPip)
                ctx.beginPath()
                ctx.arc(p[0], p[1], pipR, 0, 2 * Math.PI)
                ctx.fillStyle = CommonOptions.css(tg.tone)
                ctx.fill()
                // 与卡片底色同色的 1px 环: 两个点挨着时不会糊成一个
                ctx.lineWidth = 1
                ctx.strokeStyle = card
                ctx.stroke()
            }

            // === 6. 无定位: 停在"空盘"状态, 不画假指针 ===
            if (!dial.hasFix) {
                ctx.beginPath()
                ctx.arc(cx0, cy0, 20 * dial.k, 0, 2 * Math.PI)
                ctx.strokeStyle = ruleSoft
                ctx.lineWidth = 1
                ctx.stroke()
                return
            }

            // === 7. 指针 (橙红 = 主操作/火 的信号色, 不是"当前位置装饰") ===
            const hp = pt(dial.heading, rOut - 34 * dial.k)
            const tail = pt(dial.heading + 180, 16 * dial.k)
            ctx.beginPath()
            ctx.moveTo(hp[0], hp[1])
            ctx.lineTo(tail[0], tail[1])
            ctx.strokeStyle = CommonOptions.css(CommonOptions.colorBlaze)
            ctx.lineWidth = 2 * dial.k
            ctx.stroke()
            // 针尖: 实心小三角, 远看也知道哪头是前
            const tipL = pt(dial.heading - 4, rOut - 30 * dial.k)
            const tipR = pt(dial.heading + 4, rOut - 30 * dial.k)
            ctx.beginPath()
            ctx.moveTo(hp[0], hp[1])
            ctx.lineTo(tipL[0], tipL[1])
            ctx.lineTo(tipR[0], tipR[1])
            ctx.closePath()
            ctx.fillStyle = CommonOptions.css(CommonOptions.colorBlaze)
            ctx.fill()
        }
    }

    // === 盘心: QML 叠层 (文字必须 crisp, 画进 Canvas 会在 2x 屏上发虚) ===
    Rectangle {
        id: hub
        anchors.centerIn: parent
        // 墨底迷你盘 (74px) 不画盘心圆: mock 里读数直接落在墨底上, 画个圆反而把
        // 刻度环吃掉. 尺寸档: 大盘 92 / ①营地 58 / 迷你 0.72×直径.
        width: dial.onInk ? Math.round(dial.width * 0.72)
                         : (dial.width >= 180 ? styles.dialHubLg : styles.dialHub)
        height: width
        radius: width / 2
        color: dial.onInk ? "transparent" : CommonOptions.colorSurface
        border.color: dial.onInk ? "transparent" : CommonOptions.colorText
        border.width: dial.onInk ? 0 : styles.lineHair

        Column {
            anchors.centerIn: parent
            spacing: 1
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.hubValue
                font.family: styles.monoFont
                font.pixelSize: (dial.width >= 180 ? 23 : (dial.onInk ? 13 : 15))
                color: dial.onInk ? CommonOptions.colorOnInk : CommonOptions.colorText
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.hubLabel
                font.family: styles.monoFont
                font.pixelSize: (dial.width >= 180 ? 7.5 : (dial.onInk ? 7 : 5.5))
                font.letterSpacing: (dial.width >= 180 ? 1.5 : 0.8)
                color: dial.onInk ? CommonOptions.colorOnInkDim : CommonOptions.colorTextDim
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: dial.hubSub.length > 0
                text: dial.hubSub
                // 汉字不走等宽: monoFont 下中文靠字形回退, 真机上见过方框.
                // 上面两行是 "HDG / 184°" 这类拉丁+数字才用等宽对齐.
                font.pixelSize: (dial.width >= 180 ? 8 : 6)
                color: dial.hubSubColor
            }
        }
    }
}
