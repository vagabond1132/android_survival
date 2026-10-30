/**
 * @file LineProfile.qml
 * @brief 距离-数值 折线剖面 (海拔 / 速度), Canvas 自绘 (2026-10-26 任务 #121 A25)
 *
 * 为什么自己画而不用 QtCharts: 真机 8 份 crash dump 同一个栈 ——
 *   ChartThemeManager::decorateChart → ChartPresenter::setTitleFont → createTitleItem
 *   → ChartTitle → QGraphicsTextItem → QWidgetTextControl::setCursorWidth → SIGSEGV。
 * QtCharts 的图内标题是 widgets 栈里的 QGraphicsTextItem, 它构造时要 widget style,
 * 而本工程 main.cpp 只跑 QGuiApplication (纯 QML), style 是空的 → 解引用空指针。
 * 这条路径在 QChart 创建时无条件走一遍, 连 title: "" 都躲不过, 所以不是"某个属性
 * 配错了", 是模块与运行时类型不匹配 —— 删掉 Charts 依赖才是修. 注意修的是"主二进制
 * 不再链 Charts/Widgets, 运行时不再加载它们", 不是"APK 变小": build_apk.sh 会把整个
 * Qt kit 的 libQt6*.so 无差别拷进包, 这两个库还在里面 (2026-10-26 拆包核过).
 *
 * 画法与 Dial / CategoryRing / BearingBar / HazardBand 同一套 (站内没有位图资源,
 * 自绘不给 APK 加体积)。样式跟着「地物图例」: 卡面是纸, 网格用 colorRuleSoft 发丝线,
 * 线色由调用方给类别色 (海拔=植被绿 / 速度=水源蓝), 线下只铺一层同色的浅面积。
 *
 * 三条数据规则 (和 TrackDetailPage 的规则 ② 一致):
 *   ① 只画真实采样: distances 与 values 按短的一组截 —— 多出来的点没有配对值,
 *      画出来就是编的。不插值、不平滑、不补首尾。
 *   ② 不足 2 对点就整块留白 (调用方本来也会把标题一起藏掉), 不画空坐标系骗版面。
 *   ③ 刻度是"整数好看档" (1/2/5×10^k), 只用于读数, 不代表数据里存在这些值。
 *
 * 2026-10-29 (用户问题3 + 问题4):
 *   ③' 视窗缩放: 双指捏合缩放 / 单指横向拖动平移 / 双击复位 (viewStart/viewEnd 是
 *      "可见距离区间的归一化窗口", 0..1). 缩放中心跟着捏合中心走, 不跳回中线.
 *   ④' 绘制量按画布宽度抽稀: 一条 1.2 万~2.4 万点的轨迹, 原来每帧把全部点重投影,
 *      点完「分析图」页面要卡好几百毫秒 (问题4). 现在每个 ~2px 宽的桶只留最小值和
 *      最大值两个点 (Envelope 抽稀) —— 峰值不会因为抽稀消失, 而顶点数封在 ~2×画布宽.
 *      统计/读数仍走全量点, 抽稀只影响这根线的形状精度.
 *   ⑤' 纵轴范围按**可见区间**算 (缩放后自动贴到局部起伏), 但仍只输出"整数好看档"
 *      读数, 不会因为缩放编出不存在的刻度.
 *
 * 数字一律走 styles.monoFont (等宽族只有拉丁), 单位写在标题里不进画布
 * —— 见 [[qml-monofont-no-cjk]]。
 */

import QtQuick
import OutdoorSurvival 1.0

Canvas {
    id: prof

    Styles { id: styles; visible: false }

    // 横轴: 累计距离 (米, 与 mapService.getTrackProfile 的 distances 同单位)
    property var distances: []
    // 纵轴: 原始数值 (海拔 m / 速度 m·s⁻¹), 显示前乘 displayScale
    property var values: []
    property real displayScale: 1
    property int decimals: 0
    property color tone: CommonOptions.colorForest

    // 可见窗口 (归一化距离区间). 1/1 = 全览; 缩放只改这两个数, 不动数据.
    property real viewStart: 0
    property real viewEnd: 1
    // 最窄窗口: 1/40 全程. 再窄就只剩几个真实采样点, 折线会变成乱窜的折角.
    readonly property real minSpan: 0.025

    // 左竖排留出的读数宽度 / 底部横轴读数高度
    readonly property real _padL: 34
    readonly property real _padR: 6
    readonly property real _padT: 8
    readonly property real _padB: 16

    antialiasing: true

    onDistancesChanged: {
        // 换了一条轨迹: 旧的窗口对新数据没有意义 → 回全览
        prof.resetView()
        requestPaint()
    }
    onValuesChanged: requestPaint()
    onToneChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onViewStartChanged: requestPaint()
    onViewEndChanged: requestPaint()
    Component.onCompleted: requestPaint()

    function resetView() {
        prof.viewStart = 0
        prof.viewEnd = 1
    }

    // 双击复位: 缩放/平移到别处之后, 回到"整条轨迹"只有一个手势的出口.
    TapHandler {
        onDoubleTapped: prof.resetView()
    }

    // 捏合缩放. target: null —— 处理器自己不动任何 item, 只把 scale 交给画布窗口.
    PinchHandler {
        id: pinch
        target: null
        property real start0: 0
        property real start1: 1
        property real startCx: 0.5
        onActiveChanged: {
            if (!active) return
            start0 = prof.viewStart
            start1 = prof.viewEnd
            var plotW = prof.width - prof._padL - prof._padR
            startCx = plotW > 0
                ? Math.max(0, Math.min(1, (centroid.position.x - prof._padL) / plotW))
                : 0.5
        }
        onScaleChanged: {
            if (!active) return
            var span = start1 - start0
            var newSpan = Math.max(prof.minSpan, Math.min(1, span / Math.max(0.001, scale)))
            var pivot = start0 + span * startCx
            var v0 = pivot - newSpan * startCx
            var v1 = v0 + newSpan
            if (v0 < 0) { v0 = 0; v1 = newSpan }
            if (v1 > 1) { v1 = 1; v0 = 1 - newSpan }
            prof.viewStart = v0
            prof.viewEnd = v1
        }
    }

    // 单指横向平移. 只开 x 轴: 竖直拖动留给外面的 ScrollView, 否则在图上往下拖时
    //   页面滚不动 (图占了大半屏, 用户一定会这么试一次).
    DragHandler {
        id: pan
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        property real start0: 0
        property real start1: 1
        onActiveChanged: {
            if (!active) return
            start0 = prof.viewStart
            start1 = prof.viewEnd
        }
        onTranslationChanged: (delta) => {
            if (!active) return
            var plotW = prof.width - prof._padL - prof._padR
            if (plotW <= 0) return
            var span = start1 - start0
            // translation 是"从按下那一刻起的累计位移"(与 MapPage 手势层同一读法)
            var d = -delta.x / plotW * span
            var v0 = start0 + d
            var v1 = start1 + d
            if (v0 < 0) { v0 = 0; v1 = span }
            if (v1 > 1) { v1 = 1; v0 = 1 - span }
            prof.viewStart = v0
            prof.viewEnd = v1
        }
    }

    // 1/2/5 × 10^k 的"好看档", 目标 3~4 条横线
    function _niceStep(range) {
        var raw = range / 3.5
        if (!(raw > 0)) return 1
        var mag = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10))
        var norm = raw / mag
        return (norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10) * mag
    }

    function fmt(v) { return v.toFixed(prof.decimals) }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        var d = (prof.distances && prof.distances.length !== undefined) ? prof.distances : []
        var v = (prof.values && prof.values.length !== undefined) ? prof.values : []
        var n = Math.min(d.length, v.length)
        if (n < 2) return                       // 规则 ②: 没有真数据就不画坐标系

        var plotW = width - prof._padL - prof._padR
        var plotH = height - prof._padT - prof._padB
        if (plotW < 20 || plotH < 20) return     // 卡还没布局出尺寸, 别画半截

        // 可见索引区间: 归一路口 [viewStart, viewEnd] → [i0, i1].
        //   取整只影响"多看到半个采样", 不影响数据本身.
        var vStart = Math.max(0, Math.min(1, prof.viewStart))
        var vEnd = Math.max(vStart, Math.min(1, prof.viewEnd))
        var i0 = Math.floor(vStart * (n - 1))
        var i1 = Math.ceil(vEnd * (n - 1))
        if (i0 < 0) i0 = 0
        if (i1 > n - 1) i1 = n - 1
        if (i1 <= i0) i1 = Math.min(n - 1, i0 + 1)
        var vis = i1 - i0 + 1
        if (vis < 2) return                      // 窗口里凑不出两个点: 不画线段

        // 显示单位下的真实范围 (只统计可见区间 —— 放大后纵轴贴局部起伏)
        var lo = Infinity, hi = -Infinity, maxD = 0, i
        function dy(k) { return Number(v[k]) * prof.displayScale }
        for (i = i0; i <= i1; ++i) {
            var y0 = dy(i)
            if (y0 < lo) lo = y0
            if (y0 > hi) hi = y0
            if (Number(d[i]) > maxD) maxD = Number(d[i])
        }
        var dMin = Number(d[i0])          // 窗口左端的真实距离 (米)
        if (!(maxD > dMin)) return
        if (hi === lo) { hi += 1; lo -= 1 }      // 全程一个值: 给一档余量, 不成 0 高

        var step = prof._niceStep(hi - lo)
        var axisLo = Math.floor(lo / step) * step
        var axisHi = Math.ceil(hi / step) * step
        if (axisHi === axisLo) axisHi = axisLo + step

        function px(metres) {
            return prof._padL + ((Number(metres) - dMin) / (maxD - dMin)) * plotW
        }
        function py(val) {
            return prof._padT + (1 - (val - axisLo) / (axisHi - axisLo)) * plotH
        }

        // Envelope 抽稀: 每 ~2px 一个桶, 桶内只留最小/最大两个索引 (按 x 顺序).
        //   24k 点 → 封在 ~2×plotW 个顶点; 峰值仍落在线上, 不会画出一条"平掉的山".
        var target = Math.max(64, Math.floor(plotW * 2))
        var bucket = Math.max(1, Math.ceil(vis / target))
        var idx = []
        idx.push(i0)
        for (var b = i0; b <= i1; b += bucket) {
            var bEnd = Math.min(i1, b + bucket - 1)
            var imin = b, imax = b
            for (var k = b + 1; k <= bEnd; ++k) {
                if (dy(k) < dy(imin)) imin = k
                if (dy(k) > dy(imax)) imax = k
            }
            if (imin > imax) { var tswap = imin; imin = imax; imax = tswap }
            idx.push(imin)
            if (imax !== imin) idx.push(imax)
        }
        if (idx[idx.length - 1] !== i1) idx.push(i1)

        var labelFont = styles.fsXs + "px " + styles.monoFont

        // ① 横向网格 + 纵轴读数 (发丝线, 不抢曲线)
        ctx.lineWidth = styles.lineHair
        ctx.font = labelFont
        ctx.textAlign = "right"
        ctx.textBaseline = "middle"
        for (var g = axisLo; g <= axisHi + step * 0.001; g += step) {
            var gy = Math.round(py(g)) + 0.5     // 半像素偏移: 1px 线才不糊成 2px
            ctx.strokeStyle = CommonOptions.css(g === axisLo
                                                ? CommonOptions.colorRule
                                                : CommonOptions.colorRuleSoft)
            ctx.beginPath()
            ctx.moveTo(prof._padL, gy)
            ctx.lineTo(prof._padL + plotW, gy)
            ctx.stroke()
            ctx.fillStyle = CommonOptions.css(CommonOptions.colorInk3)
            ctx.fillText(prof.fmt(g), prof._padL - 5, gy)
        }

        // ② 线下浅面积 (同色渐变, 上实下虚) —— 用抽稀后的顶点, 与折线同一条
        ctx.beginPath()
        ctx.moveTo(px(d[idx[0]]), py(dy(idx[0])))
        for (i = 1; i < idx.length; ++i)
            ctx.lineTo(px(d[idx[i]]), py(dy(idx[i])))
        ctx.lineTo(px(d[idx[idx.length - 1]]), py(axisLo))
        ctx.lineTo(px(d[idx[0]]), py(axisLo))
        ctx.closePath()
        var grad = ctx.createLinearGradient(0, prof._padT, 0, py(axisLo))
        grad.addColorStop(0, CommonOptions.css(prof.tone, 0.24))
        grad.addColorStop(1, CommonOptions.css(prof.tone, 0.04))
        ctx.fillStyle = grad
        ctx.fill()

        // ③ 折线本体: 只连真实采样点 (抽稀后的顶点全是真采样, 没有插值点)
        ctx.beginPath()
        for (i = 0; i < idx.length; ++i) {
            var lx = px(d[idx[i]]), ly = py(dy(idx[i]))
            if (i === 0) ctx.moveTo(lx, ly)
            else ctx.lineTo(lx, ly)
        }
        ctx.strokeStyle = CommonOptions.css(prof.tone)
        ctx.lineWidth = 2
        // Canvas 的 2D 上下文只认 CSS 字符串; 写 Qt.RoundJoin 这类枚举值会被静默忽略,
        // 折角就还是默认的 miter (采样密时尖角会甩出线外)。
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.stroke()

        // ④ 峰值点: 可见区间里最高的那个 (缩放后就是"这一段里的最高点")
        var peak = i0
        for (i = i0 + 1; i <= i1; ++i)
            if (dy(i) > dy(peak)) peak = i
        var pkx = px(d[peak]), pky = py(dy(peak))
        ctx.fillStyle = CommonOptions.css(prof.tone)
        ctx.beginPath()
        ctx.arc(pkx, pky, 2.5, 0, Math.PI * 2)
        ctx.fill()
        ctx.textAlign = pkx > prof._padL + plotW - 40 ? "right" : "left"
        ctx.textBaseline = pky < prof._padT + 12 ? "top" : "bottom"
        ctx.fillText(prof.fmt(dy(peak)),
                     pkx + (ctx.textAlign === "right" ? -5 : 5),
                     pky + (ctx.textBaseline === "top" ? 4 : -4))

        // ⑤ 横轴: 窗口左端 / 中点 / 右端的公里数 (缩放后跟着窗口走, 不再写死 0)
        ctx.textAlign = "center"
        ctx.textBaseline = "top"
        ctx.fillStyle = CommonOptions.css(CommonOptions.colorInk3)
        var yLabel = prof._padT + plotH + 4
        var dMid = (dMin + maxD) / 2
        ctx.fillText((dMin / 1000).toFixed(1), prof._padL, yLabel)
        ctx.fillText((dMid / 1000).toFixed(1), prof._padL + plotW / 2, yLabel)
        ctx.textAlign = "right"
        ctx.fillText((maxD / 1000).toFixed(1), prof._padL + plotW, yLabel)
    }
}
