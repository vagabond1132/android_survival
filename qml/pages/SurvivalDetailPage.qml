/**
 * @file SurvivalDetailPage.qml
 * @brief 手册 · 野外生活详情 (2026-10-20 v9 F2 同款, 丁骨架二级页)
 *
 * 入口: SurvivalPage 目录行点击 / navBus.push({itemId}).
 *
 * 版式逐块对应已评审的 mock (review-v9-screens.html 「V9 · 2」绳结详情):
 *   图版头 150px: --paper-sunk 底 + 1px 墨线压底; 左上类目 chip, 右上 26px 方角返回,
 *           中间是"预计时长 + 难度梯"的读数块, 底下 编号 + 类目 + 名称 (21px 800).
 *   读数带  4 格 (材料 / 步骤 / 警告 / 贴士), 数字全部是数组长度, 不编.
 *   正文    一句话说明 → 所需材料 → 操作步骤 (两位序号) → 安全警告 (斜纹卡) → 小贴士 → 来源.
 *   底栏    1px 墨线 + --card-2 底; 左 88px 空心「回目录」, 右实心「下一步 N ›」.
 *
 * 四条不能破的规则:
 *   ① 不编读数. 材料/步骤/警告/贴士的条数来自 survivalService.getById; 时长与难度也是
 *      字段本身. 库里没有"成功率""适用气温"这类字段, 所以这一屏只有那 4 格.
 *   ② 不假装有图. survival_items.json 的 video_url 15 条全有值, 但包里没有任何对应
 *      素材 (与绳结 knot_*.mp4 同一回事) → 不放播放入口, 并在读数带右侧坦白
 *      "本库无技能图示".
 *   ③ 汉字不进等宽. 时长格拆成两个 Text: 数字走 monoFont, "分钟"走默认字体
 *      (见 [[qml-monofont-no-cjk]]).
 *   ④ 数据正文里的 "1. " 与 "⚠️ " 前缀一律走 CommonOptions.stripEntryMarker 剥掉 ——
 *      序号由页面自己排, emoji 在设备字体里是方框 (见 #27/#58 的口径: 不动 json,
 *      只在渲染层剥).
 */

// delegate 里要读 survivalDetail 的方法, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: survivalDetail

    Styles { id: styles; visible: false }

    title: entity.name || "野外生活详情"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property string itemId: ""
    property var entity: ({})
    // 全目录顺序 (类目序 + 编号序), 底栏"下一步"按它走
    property var _seq: []

    readonly property var topicOrder: [0, 1, 2, 3, 4, 5, 6, 7]

    function topicLabel(t) {
        if (t === 0) return "取火"
        if (t === 1) return "庇护所"
        if (t === 2) return "净水"
        if (t === 3) return "食物"
        if (t === 4) return "求救信号"
        if (t === 5) return "导航定向"
        if (t === 6) return "天气"
        if (t === 7) return "工具"
        return "技能"
    }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    // 数组归一化: service 返回的可能是 QVariantList 包装, 也可能字段缺失
    function _toArr(v) { return (v && v.length !== undefined) ? v : [] }

    function _load() {
        if (!itemId || !survivalService) return
        entity = survivalService.getById(itemId)
        _buildSequence()
    }

    // getByTopic 走 QHash, 遍历序不稳 → 组内按编号排; 组间按类目枚举序.
    // 这样"下一步"的次序与目录页看到的次序一致 (目录页同规则, 见 SurvivalPage.reload).
    function _buildSequence() {
        var src = []
        for (var i = 0; i < topicOrder.length; ++i) {
            var t = topicOrder[i]
            var items = survivalService ? survivalService.getByTopic(t) : []
            for (var k = 0; k < items.length; ++k) {
                src.push({
                    id: items[k].id,
                    order: i,
                    plate: CommonOptions.plateCode("SV", items[k].id)
                })
            }
        }
        src.sort(function (a, b) {
            if (a.order !== b.order) return a.order - b.order
            return a.plate < b.plate ? -1 : (a.plate > b.plate ? 1 : 0)
        })
        _seq = src
    }

    onItemIdChanged: survivalDetail._load()
    // StackView 的 initialProperties 是一条条赋的: itemId 先落地时 service 可能还没就绪,
    // 补一次首帧兜底 (空 itemId 会在 _load 里直接 return, 不会多跑一次空查表).
    Component.onCompleted: survivalDetail._load()

    // === 派生字段 ==========================================================
    readonly property var _materials: _toArr(entity.materials)
    readonly property var _steps: _toArr(entity.steps)
    readonly property var _warnings: _toArr(entity.warnings)
    readonly property var _tips: _toArr(entity.tips)
    readonly property int _difficulty: Number(entity.difficulty) || 0
    readonly property int _minutes: Number(entity.estimatedTimeMin) || 0

    // 下一条 (整个手册是一个圈, 不是走到头就断)
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

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- ① 图版头 (150px) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            color: CommonOptions.colorSurfaceDim

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            // 中间: 时长 + 难度梯. 库里没有图示, 所以这块放读数而不是假图 (规则 ②).
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: styles.spLg
                spacing: 5

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4
                    Text {
                        anchors.bottom: parent.bottom
                        text: survivalDetail._minutes > 0 ? String(survivalDetail._minutes) : "—"
                        font.family: styles.monoFont
                        font.pixelSize: 34
                        color: CommonOptions.colorText
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        visible: survivalDetail._minutes > 0
                        text: "分钟"
                        font.pixelSize: styles.fsMd
                        color: CommonOptions.colorTextMuted
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: styles.spSm
                    Ladder {
                        anchors.verticalCenter: parent.verticalCenter
                        value: survivalDetail._difficulty
                        tone: CommonOptions.difficultyColor(survivalDetail._difficulty)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: CommonOptions.difficultyLabel(survivalDetail._difficulty)
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
            }

            // 左上: 类目 + 难度档 (一格话, 让页面第一眼就知道这是哪一类)
            Chip {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
                visible: (survivalDetail.entity.id || "").length > 0
                text: (entity.category || "") + " · 难度 " + survivalDetail._difficulty
                accent: CommonOptions.colorInk3
                checked: true
                textSize: styles.fsXs
            }

            // 右上: 返回方角 26px, 热区向外扩 9px 到 44 (戴手套)
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
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
                    onClicked: survivalDetail.goBack()
                }
            }

            // 底部: 编号 + 类目 (左) / 名称
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
                        code: "PLATE " + CommonOptions.plateCode("SV", entity.id || "")
                        tone: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: survivalDetail.topicLabel(Number(entity.topic))
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: entity.name || "野外生活详情"
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
                        text: "SKILL READOUT"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.4
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    // 规则 ② 的坦白: 时长与难度是数据, 图示没有
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "本库无技能图示"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: [
                            { k: "MATERIALS", v: String(survivalDetail._materials.length) },
                            { k: "STEPS", v: String(survivalDetail._steps.length) },
                            { k: "WARNINGS", v: String(survivalDetail._warnings.length) },
                            { k: "TIPS", v: String(survivalDetail._tips.length) }
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
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
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsXs
                                    font.letterSpacing: 1.2
                                    color: CommonOptions.colorInk3
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.v
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsSm
                                    color: CommonOptions.colorText
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
            contentWidth: width
            clip: true
            visible: (survivalDetail.entity.id || "").length > 0

            ColumnLayout {
                width: parent.width
                spacing: styles.spMd

                // 一句话说明
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    Layout.topMargin: styles.spMd
                    visible: (survivalDetail.entity.description || "").length > 0
                    text: survivalDetail.entity.description || ""
                    font.pixelSize: styles.fsMd
                    color: CommonOptions.colorTextMuted
                    wrapMode: Text.WordWrap
                }

                // 所需材料
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: survivalDetail._materials.length > 0
                    Text {
                        Layout.fillWidth: true
                        text: "所需材料"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: survivalDetail._materials.length + " ITEMS"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.4
                        color: CommonOptions.colorInk3
                    }
                }
                Repeater {
                    model: survivalDetail._materials
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        spacing: styles.spSm
                        // 材料是不记名的清单, 用 1px 短横而不是序号 (序号留给步骤)
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 9
                            Layout.preferredHeight: styles.lineHair
                            color: CommonOptions.colorInk3
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

                // 操作步骤
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: survivalDetail._steps.length > 0
                    Text {
                        Layout.fillWidth: true
                        text: "操作步骤"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: survivalDetail._steps.length + " STEPS"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.4
                        color: CommonOptions.colorInk3
                    }
                }
                Repeater {
                    model: survivalDetail._steps
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

                // 安全警告: 斜纹 + amber 描边卡 (hazard 红只给文字与条纹)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: survivalDetail._warnings.length > 0
                    Layout.preferredHeight: warnRow.implicitHeight + 2 * styles.cardPad
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
                        id: warnRow
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
                                text: "安全警告 · " + survivalDetail._warnings.length + " 条"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorHazard
                            }
                            Repeater {
                                model: survivalDetail._warnings
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

                // 小贴士
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: survivalDetail._tips.length > 0
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
                            text: "小贴士 · " + survivalDetail._tips.length + " 条"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                        }
                        Repeater {
                            model: survivalDetail._tips
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

                // 来源 (数据里只有两种: 怀斯曼生存手册 / + 中国登山协会)
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: (survivalDetail.entity.source || "").length > 0
                    text: "来源 · " + (survivalDetail.entity.source || "")
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spMd }
            }
        }

        // 取不到条目 (id 打错 / service 还没载入) → 空态, 不是一张只有骨架的页
        EmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: styles.spXl * 2
            visible: (survivalDetail.entity.id || "").length === 0
            iconName: "shelter"
            text: "这项技能没有取到"
            hint: "itemId=" + survivalDetail.itemId + " 不在野外生活库里"
            actionText: "返回目录"
            onActionTriggered: survivalDetail.goBack()
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
                    text: "回目录"
                    tone: CommonOptions.colorTextMuted
                    textSize: styles.fsSm
                    onClicked: survivalDetail.goBack()
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    visible: survivalDetail._nextEntry !== null
                    text: (survivalDetail._wrapped ? "回到第一条"
                                                   : "下一步 " + survivalDetail._nextIndexLabel + " ›")
                    tone: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: {
                        if (survivalDetail._nextEntry)
                            survivalDetail.navigateTo("SurvivalDetailPage",
                                                      { itemId: survivalDetail._nextEntry.id })
                    }
                }
            }
        }
    }
}
