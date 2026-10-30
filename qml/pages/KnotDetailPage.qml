/**
 * @file KnotDetailPage.qml
 * @brief 绳结详情 (2026-10-20 v9 F2, 丁骨架: 图版头 + 四格读数 + 步骤 + 错误 + 底栏)
 *
 * 版式逐块对应已评审的 mock (review-v9-screens.html 「V9 · 2」):
 *   图版头   150px 沉底图版区 (--paper-sunk → colorSurfaceDim) + 左上"类目·难度"chip
 *            + 右上 26px 方角返回 + 底部 编号/中文名/学名·用途. 中间画的是单线绳图.
 *   读数带   四格: DIFFICULTY / STEPS / RELATED / MISTAKES, 全是 getById 的字段长度.
 *   步骤     blaze 色两位序号 (mono) + 正文 (默认字体). 序号由本页排, 数据里手写的
 *            "1. " 走 CommonOptions.stripEntryMarker 剥掉, 否则真机是 "01 1. 绳头…".
 *   常见错误 amber 描边卡 + 左侧 6px 斜纹 (HazardBand). 每条前的 "⚠️" 同样剥掉 ——
 *            Material Icons 与 Android 默认字体都没有这个字形, 不剥就是方框.
 *   底栏     上边 1px 墨线 + card-2 底: 左 OutlineButton(学会) 右 PrimaryButton(下一步).
 *            返回走图版头右上角, 所以底栏只放两个前进动作, 不再重复"返回目录".
 *
 * 四条不能破的规则:
 *   ① 不编读数. 四格全部由 getById 的数组长度与 difficulty 得出. 数据里没有"强度/
 *      承重/适用绳径", 所以那一排只有四格, 不补第五格.
 *   ② 不假装有图. assets/data 里没有绳结形态图, knots.json 的 video_url 是
 *      "knot_single.mp4" 这种裸文件名而仓库里一个 mp4 都没有, animation_url 也空.
 *      所以图版头中间是**通用**两股单线绳示意 (绳头/主绳), 不是这个结的实际形状,
 *      读数带右上角把这句话写出来. 早期版本这里画的是 8 字结专用图, 换成别的结
 *      就是假读数. 也不放"观看视频"按钮.
 *   ③ 汉字不进等宽 (见 [[qml-monofont-no-cjk]]). 只有 KN 编号、四格读数、两位步骤
 *      序号、"N 步" 这类拉丁/数字走 monoFont; "下一步 02" 这种混排走默认字体.
 *   ④ 写操作返回 Result 信封 {ok,value,error}, 直接 `if (res)` 恒真 → 走 _ok(res).
 *      另外 KnotService 只有 markLearned/resetProgress, 没有"取消已学会" —— 所以
 *      已学过的条目这颗按钮是禁用态的"已学会", 不做假 toggle.
 *
 * 相关结: related 里 4 个 id 在库里不存在 (double_overhand / portuguese_bowline /
 * bachar / autoblock). 点不进去的降级成灰胶囊, 不弹错也不跳空页.
 *
 * 2026-10-19 那版用的 Hero + StatTile + Section 全部撤掉: 渐变 hero 在强光下最糊,
 * "★".repeat(difficulty) 的星号既占宽又没有语义, Section 的 "• " 前缀也和这里的
 * 编号步骤冲突.
 */

// delegate/Repeater 里要读 knotDetail 的属性与方法, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: knotDetail

    Styles { id: styles; visible: false }

    property string knotId: ""
    property var entity: ({})

    title: entity.nameCn || "绳结详情"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 取数 ==============================================================
    // QStringList 到 QML 端不一定是 JS Array, 要用 filter/join 就先归一化
    function _toArr(v) {
        if (!v) return []
        if (Array.isArray(v)) return v
        var out = []
        try {
            for (var i = 0; i < v.length; ++i) out.push(v[i])
        } catch (e) { return [] }
        return out
    }

    function _ok(res) { return !!(res && res.ok) }

    // 单一触发点 (与改版前一致): StackView push 的 properties 在 onCompleted 之前
    // 就赋好了, 双触发会让 addRecord 这类副作用跑两遍.
    onKnotIdChanged: {
        if (!knotId) return
        if (!knotService) {
            console.warn("[knot detail] knotService 不可用, knotId=" + knotId)
            return
        }
        entity = knotService.getById(knotId)
        _buildSequence()
    }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    // 目录顺序 = 类目概念序 (基础→接绳→环形→锚定) + 组内编号序, 与 KnotPage 同一套.
    // "下一步"必须跟着用户刚 scroll 过的那条线走, 不能按 QHash 遍历序随机跳.
    readonly property var categoryOrder: ["基础", "接绳", "环形", "锚定"]
    property var _seq: []          // [{id, plate, nameCn}]

    function _orderOf(cat) {
        var i = knotDetail.categoryOrder.indexOf(cat)
        return i < 0 ? knotDetail.categoryOrder.length : i
    }

    // 局部变量名避开 list / raw / m: 这三个是别的文件里的 QML id,
    // _scratch_debug/crossfile_id_check.js 会把它们报成跨文件引用.
    function _buildSequence() {
        var src = knotService ? knotService.getAll() : []
        var ordered = []
        for (var i = 0; i < src.length; ++i) {
            ordered.push({
                id: src[i].id,
                plate: CommonOptions.plateCode("KN", src[i].id),
                order: _orderOf(src[i].category || "")
            })
        }
        ordered.sort(function (a, b) {
            if (a.order !== b.order) return a.order - b.order
            return a.plate < b.plate ? -1 : (a.plate > b.plate ? 1 : 0)
        })
        knotDetail._seq = ordered
    }

    // 下一条 (到末条就回到第一条 —— 练整套绳结是一个圈, 不是走到头就断)
    readonly property int _selfIndex: {
        for (var i = 0; i < _seq.length; ++i)
            if (_seq[i].id === entity.id) return i
        return -1
    }
    readonly property bool _wrapped: _selfIndex >= 0 && _seq.length > 1
                                     && _selfIndex === _seq.length - 1
    readonly property var _nextEntry: {
        if (_seq.length < 2 || _selfIndex < 0) return null
        return _wrapped ? _seq[0] : _seq[_selfIndex + 1]
    }
    // 底栏写"下一步 04", 编号用目录里的位次 (1 起), 补零到两位
    readonly property string _nextIndexLabel: {
        if (_selfIndex < 0) return ""
        var n = _wrapped ? 1 : (_selfIndex + 2)
        return (n < 10 ? "0" : "") + n
    }

    // === 派生字段 ==========================================================
    readonly property var _steps: _toArr(entity.steps)
    readonly property var _mistakes: _toArr(entity.commonMistakes)
    readonly property var _uses: _toArr(entity.useCases)
    readonly property var _relatedIds: _toArr(entity.related)

    // 相关结: 库里查不到的也列出来但点不动 (灰), 查得到的给名字并压成新页
    readonly property var _related: {
        var out = []
        for (var i = 0; i < _relatedIds.length; ++i) {
            var rid = _relatedIds[i]
            var hit = knotService ? knotService.getById(rid) : ({})
            var resolved = !!(hit && Object.keys(hit).length > 0)
            out.push({
                id: rid,
                name: resolved ? (hit.nameCn || rid) : rid,
                enabled: resolved
            })
        }
        return out
    }

    readonly property color _tone: {
        var c = entity.category || ""
        if (c === "基础") return CommonOptions.colorForest
        if (c === "接绳") return CommonOptions.colorPlum
        if (c === "环形") return CommonOptions.colorWater
        if (c === "锚定") return CommonOptions.colorLegendAmber
        return CommonOptions.colorTextMuted
    }
    readonly property string _usesLine: _uses.join(" · ")
    readonly property string _difficultyReadout: (entity.difficulty || 0) + " / 3"

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- ① 图版头 150px ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            color: CommonOptions.colorSurfaceDim

            // 底边 1px 墨线: 图版区与正文靠描边分界, 不靠阴影
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            // 通用两股单线绳示意 (规则 ②: 这不是本结的结形)
            Item {
                id: ropeBox
                width: 120
                height: 112
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 6

                Canvas {
                    id: ropeCanvas
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.lineCap = "round"
                        ctx.lineWidth = 2.2
                        ctx.strokeStyle = CommonOptions.css(CommonOptions.colorText)
                        // 主绳: 从右上往下走的 S; 绳头: 镜像的另一条. 交叠处下面用断口压.
                        ctx.beginPath()
                        ctx.moveTo(74, 10)
                        ctx.bezierCurveTo(74, 26, 46, 26, 46, 42)
                        ctx.bezierCurveTo(46, 58, 74, 58, 74, 74)
                        ctx.bezierCurveTo(74, 90, 46, 90, 46, 106)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(46, 14)
                        ctx.bezierCurveTo(46, 30, 74, 30, 74, 46)
                        ctx.bezierCurveTo(74, 62, 46, 62, 46, 78)
                        ctx.bezierCurveTo(46, 94, 74, 94, 74, 110)
                        ctx.stroke()
                        // 上下压: 交叠点刷一段底色, 线就"断"成有先后的两股
                        ctx.strokeStyle = CommonOptions.css(CommonOptions.colorSurfaceDim)
                        ctx.lineWidth = 5.4
                        var cuts = [[60, 21.5], [60, 53.5], [60, 69.5], [60, 86.5]]
                        for (var i = 0; i < cuts.length; ++i) {
                            ctx.beginPath()
                            ctx.moveTo(cuts[i][0], cuts[i][1])
                            ctx.lineTo(cuts[i][0], cuts[i][1] + 4)
                            ctx.stroke()
                        }
                        // 引出线 (虚线) 把两个标注接到绳上
                        ctx.strokeStyle = CommonOptions.css(CommonOptions.colorInk3)
                        ctx.lineWidth = 1
                        ctx.setLineDash([2, 2])
                        ctx.beginPath(); ctx.moveTo(74, 10); ctx.lineTo(96, 6); ctx.stroke()
                        ctx.beginPath(); ctx.moveTo(46, 106); ctx.lineTo(20, 112); ctx.stroke()
                        ctx.setLineDash([])
                    }
                }
                // 标注是汉字 → 独立 Text 走默认字体, 不进 Canvas 的 ctx.font
                Text {
                    x: 98; y: 0
                    text: "绳头"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                }
                Text {
                    x: 0; y: ropeBox.height - styles.fsXs - 4
                    text: "主绳"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                }
            }

            // 左上: 类目 chip.
            // 2026-10-22 #96(d): 原来这里写的是「类目 · 难度 N / 3」, 而难度在别处是
            //   档位梯 —— 同一个数值两种配色, 用户问过一次"哪个才是难度". 现在 chip
            //   只说类目 (它确实是类目色), 难度收进下方读数带那一格: 数字 + 梯并排、
            //   同取 difficultyColor, 一眼看得出是同一件事.
            Chip {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
                checked: true
                accent: knotDetail._tone
                text: entity.category || "绳结"
                textSize: styles.fsSm
            }

            // 右上: 返回 (26px 方角, 热区向外扩 9px 到 44 —— 戴手套)
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: styles.cardPad
                anchors.topMargin: styles.cardPad
                width: 26
                height: 26
                color: CommonOptions.colorSurface
                border.color: CommonOptions.colorText
                border.width: styles.lineHair
                IconLabel {
                    anchors.centerIn: parent
                    name: "back"
                    size: styles.icSm
                    tintColor: CommonOptions.colorText
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -9
                    cursorShape: Qt.PointingHandCursor
                    onClicked: knotDetail.goBack()
                }
            }

            // 底部: 编号 + 中文名 (左) / 学名 + 用途 (右)
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                anchors.bottomMargin: styles.spSm
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Plate {
                        Layout.alignment: Qt.AlignVCenter
                        code: CommonOptions.plateCode("KN", entity.id || "")
                        tone: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignBottom
                        spacing: 1
                        Text {
                            Layout.alignment: Qt.AlignRight
                            visible: (entity.nameEn || "").length > 0
                            text: entity.nameEn || ""
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorTextMuted
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            visible: knotDetail._usesLine.length > 0
                            text: knotDetail._usesLine
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                            elide: Text.ElideRight
                            // 用途最多两栏, 挤了宁可截断也不要把中文名顶下移
                            Layout.maximumWidth: 130
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: entity.nameCn || "绳结详情"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
            }
        }

        // --- ② 四格读数带 ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: readoutCol.implicitHeight + 2 * styles.spSm
            color: CommonOptions.colorSurface

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorRule
            }

            ColumnLayout {
                id: readoutCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                spacing: styles.spSm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "绳结读数"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    // 规则 ② 的坦白: 中间那张图不是这个结的形状
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "示意图 · 单线画法 · 本库无结形图"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        // 四格同形状 (都有 ladder), 只在难度格给非 0 值: delegate 是
                        // 一份, 隐藏分支的绑定照样求值, 缺字段就是 undefined 参与比较
                        model: [
                            { k: "难度", v: knotDetail._difficultyReadout,
                              ladder: entity.difficulty || 0 },
                            { k: "步骤", v: String(knotDetail._steps.length), ladder: 0 },
                            { k: "相关", v: String(knotDetail._related.length), ladder: 0 },
                            { k: "易错", v: String(knotDetail._mistakes.length), ladder: 0 }
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            // 四格必须等宽. 难度格多了个档位梯, implicitWidth 比另三格大
                            // 约 36px, RowLayout 按隐式尺寸分剩余空间 → 实测 228/48/48/48
                            // (2026-10-22 host offscreen 量出来的). 锁一个公共 preferredWidth,
                            // 四格就回到 93/93/93/93.
                            Layout.preferredWidth: 60
                            spacing: 0
                            // 1px 竖线只在格之间画, 首格前不留
                            Rectangle {
                                visible: index > 0
                                Layout.preferredWidth: styles.lineHair
                                Layout.fillHeight: true
                                color: CommonOptions.colorRuleSoft
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.k
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorInk3
                                    elide: Text.ElideRight
                                }
                                // 数字 + 档位梯同一色来源 (difficultyColor), 读作一件事:
                                // "2 / 3" 是这条记录的字段, 三格实心是它的图形化 (2026-10-22 #96(d))
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: styles.spXs
                                    Text {
                                        text: modelData.v
                                        font.family: styles.monoFont
                                        font.pixelSize: styles.fsSm
                                        color: modelData.ladder > 0
                                               ? CommonOptions.difficultyColor(modelData.ladder)
                                               : CommonOptions.colorText
                                    }
                                    Ladder {
                                        visible: modelData.ladder > 0
                                        cells: 3
                                        value: modelData.ladder
                                        tone: CommonOptions.difficultyColor(modelData.ladder)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- ③ 正文 ---
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: styles.bottomClearance   // A41: 末行给下面的吸底条让位
            contentWidth: width
            clip: true
            visible: (entity.id || "").length > 0

            ColumnLayout {
                width: parent.width
                spacing: styles.spMd

                // 一句话说明 (数据里的 description)
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    Layout.topMargin: styles.spMd
                    visible: (knotDetail.entity.description || "").length > 0
                    text: knotDetail.entity.description || ""
                    font.pixelSize: styles.fsMd
                    color: CommonOptions.colorTextMuted
                    wrapMode: Text.WordWrap
                }

                // 打结步骤
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    Text {
                        Layout.fillWidth: true
                        text: "打结步骤"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: knotDetail._steps.length + " 个步骤"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Repeater {
                    model: knotDetail._steps
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        spacing: styles.spSm
                        // 序号自己排 (blaze 两位, 等宽); 数据里手写的 "1. " 剥掉
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: (index < 9 ? "0" : "") + (index + 1)
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsSm
                            color: CommonOptions.colorBlaze
                        }
                        Text {
                            Layout.fillWidth: true
                            text: CommonOptions.stripEntryMarker(modelData)
                            font.pixelSize: styles.fsMd
                            color: CommonOptions.colorText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // 常见错误: 斜纹 + amber 描边卡 (hazard 红只给文字与条纹)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: knotDetail._mistakes.length > 0
                    Layout.preferredHeight: mistakeRow.implicitHeight + 2 * styles.cardPad
                    color: CommonOptions.colorSurface
                    border.color: CommonOptions.colorLegendAmber
                    border.width: styles.lineHair

                    HazardBand {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        stripe: CommonOptions.colorHazard
                    }

                    RowLayout {
                        id: mistakeRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: styles.hazardBandW + styles.cardPad
                        anchors.rightMargin: styles.cardPad
                        spacing: styles.spSm

                        IconLabel {
                            Layout.alignment: Qt.AlignTop
                            name: "alert"
                            size: styles.icMd
                            tintColor: CommonOptions.colorHazard
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: "常见错误 · " + knotDetail._mistakes.length + " 条"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorHazard
                            }
                            Repeater {
                                model: knotDetail._mistakes
                                delegate: Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: CommonOptions.stripEntryMarker(modelData)
                                    font.pixelSize: styles.fsMd
                                    color: CommonOptions.colorText
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                // 练习提示
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: (knotDetail.entity.practiceTip || "").length > 0
                    Layout.preferredHeight: tipCol.implicitHeight + 2 * styles.cardPad
                    color: CommonOptions.colorSurface
                    border.color: CommonOptions.colorRule
                    border.width: styles.lineHair

                    ColumnLayout {
                        id: tipCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: styles.cardPad
                        anchors.rightMargin: styles.cardPad
                        spacing: 3
                        Text {
                            Layout.fillWidth: true
                            text: "练习提示"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                        }
                        Text {
                            Layout.fillWidth: true
                            text: knotDetail.entity.practiceTip || ""
                            font.pixelSize: styles.fsMd
                            color: CommonOptions.colorText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // 相关结
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: knotDetail._related.length > 0
                    spacing: styles.spXs
                    Repeater {
                        model: knotDetail._related
                        delegate: Chip {
                            required property var modelData
                            text: (modelData.enabled ? "相关 · " : "库里没有 · ") + modelData.name
                            textSize: styles.fsSm
                            // 未命中的 id 不弹错也不跳空页: 禁用 + 半透明, 读起来是"目录里没这条"
                            enabled: modelData.enabled
                            opacity: modelData.enabled ? 1.0 : 0.5
                            onClicked: knotDetail.navigateTo("KnotDetailPage",
                                                             { knotId: modelData.id })
                        }
                    }
                }

                Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spMd }
            }
        }

        // 取不到条目 (id 打错 / service 还没载入) → 空态, 不是一张只有骨架的页
        EmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: styles.spXl * 2
            visible: (knotDetail.entity.id || "").length === 0
            iconName: "knot"
            text: "这条绳结没有取到"
            hint: "knotId=" + knotDetail.knotId + " 不在绳结库里"
            actionText: "返回目录"
            onActionTriggered: knotDetail.goBack()
        }

        // --- ④ 底栏 ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: bottomRow.implicitHeight + 2 * styles.spSm
            color: CommonOptions.colorSurfaceAlt

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            RowLayout {
                id: bottomRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.spLg
                anchors.rightMargin: styles.spLg
                spacing: styles.spMd

                OutlineButton {
                    Layout.preferredWidth: 88
                    Layout.alignment: Qt.AlignVCenter
                    // 没有"取消已学会"的 API, 所以已学过就是禁用态的确认, 不是假 toggle
                    text: entity.learned ? "已学会" : "标记已学会"
                    tone: CommonOptions.colorForest
                    enabled: !entity.learned && knotService !== null
                    textSize: styles.fsSm
                    onClicked: {
                        var res = knotService.markLearned(knotDetail.knotId)
                        if (!knotDetail._ok(res))
                            console.warn("[knot detail] markLearned 返回非 ok 信封")
                        entity = knotService.getById(knotDetail.knotId)
                    }
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    visible: knotDetail._nextEntry !== null
                    text: (knotDetail._wrapped ? "回到第一条" : "下一步 " + knotDetail._nextIndexLabel + " ›")
                    tone: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: knotDetail.navigateTo("KnotDetailPage",
                                                     { knotId: knotDetail._nextEntry.id })
                }
            }
        }
    }
}
