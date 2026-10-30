/**
 * @file FirstAidDecisionPage.qml
 * @brief 手册 · 急救决策树行走页 (2026-10-20 v9, 接 C++ 新 nextIds 契约)
 *
 * 入口: FirstAidDetailPage 底栏「交互式决策」. navBus.push({entryId}).
 * 35 条急救里只有蛇咬伤 (firstaid_snake_bite) 有树, 节点 8 个 (1 根 + 3 问 + 4 结论),
 * 所以这一页大多数时候是空态 —— 空态写得清楚, 不给"点了没反应"的假入口.
 *
 * 为什么改版: 旧页的 _answer() 自己猜下一节点 id ("当前 id + _ + 选项序号"),
 * 而数据里的真实 id 是 snake_bite_step2 这种语义名 → 每一次点击都查不到节点,
 * 立刻掉进 "按关键步骤操作" 的假终态, 整棵树一步都走不下去. 现在 C++
 * getDecisionNode() 按 options 顺序返回 nextIds, 页面只照抄, 不再猜规则.
 * (见 src/lifesaver/FirstAidService.cpp: getDecisionNode)
 *
 * 版式沿用已评审的 F2: --paper-sunk 图版头 + 1px 墨线压底, --card 正文卡,
 * --card-2 底栏. 三条本地规则:
 *   ① 已答的路径留在上面. 救护现场会被打断 (人走开、换手), 回来要能看到
 *      "刚才答了什么", 而不是只剩最后一个问题.
 *   ② next_id 缺失或指向不存在的节点 → 明说"这条路库里没有下一步" (deadEnd),
 *      绝不写成"按关键步骤操作"冒充结论. 库里没有的分支就是不存在的分支.
 *   ③ 拨 120 只在"走到结论"之后出现, 而且是 HoldConfirmRow 长按 2 秒 ——
 *      问题中途不需要电话, 真要到拨号那一步也不许一次误触就出去.
 */

// delegate 里要读 decisionPage 的函数与属性, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: decisionPage

    Styles { id: styles; visible: false }

    title: "急救决策"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property string entryId: ""
    property var entry: ({})
    property var currentNode: ({})
    // 已答路径: [{ q, label, node }] —— 用 concat 换新数组, 保证 Repeater 收到 changed
    property var _path: []
    property bool reachedTerminal: false
    property bool deadEnd: false
    property string terminalAction: ""

    readonly property bool hasTree: (currentNode.id || "").length > 0 || _path.length > 0
    readonly property bool ended: reachedTerminal || deadEnd

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    function _toArr(v) { return (v && v.length !== undefined) ? v : [] }

    function _load() {
        _path = []
        reachedTerminal = false
        deadEnd = false
        terminalAction = ""
        currentNode = ({})
        if (!entryId || !firstAidService) return
        entry = firstAidService.getById(entryId)
        // 局部变量刻意不叫 root: 跨文件 id 自检把 "root" 当成别的组件的 id 报过 noise
        var rootNode = firstAidService.getDecisionRoot(entryId)
        if (!rootNode || !rootNode.id) return
        currentNode = rootNode
        // 数据异常兜底: 根节点自己就是终态 → 这棵树其实只有一个结论, 直接摊开
        if (rootNode.isTerminal === true) {
            reachedTerminal = true
            terminalAction = String(rootNode.terminalAction || "")
        }
    }

    function _restart() {
        decisionPage._load()
    }

    // 选项下标 → 下一节点 (照抄 nextIds, 不猜 id 规则)
    function _answer(index) {
        if (!firstAidService || !currentNode || !currentNode.id) return
        var labels = decisionPage._toArr(currentNode.options)
        var nextIds = decisionPage._toArr(currentNode.nextIds)
        if (index >= labels.length) return

        decisionPage._path = decisionPage._path.concat([{
            q: String(currentNode.question || ""),
            label: String(labels[index]),
            node: String(currentNode.id || "")
        }])

        var nextId = index < nextIds.length ? String(nextIds[index]) : ""
        if (nextId.length === 0) {
            decisionPage.deadEnd = true
            return
        }
        var n = firstAidService.getDecisionNode(nextId)
        if (!n || !n.id) {
            // next_id 写了但库里没有这个节点 —— 数据断链, 同样如实说
            decisionPage.deadEnd = true
            return
        }
        decisionPage.currentNode = n
        if (n.isTerminal === true) {
            decisionPage.reachedTerminal = true
            decisionPage.terminalAction = String(n.terminalAction || "")
        }
    }

    onEntryIdChanged: decisionPage._load()
    // StackView 的 initialProperties 一条条落地, entryId 先到时 service 可能还没就绪,
    // 补一次首帧兜底 (空 entryId 会在 _load 里直接 return).
    Component.onCompleted: decisionPage._load()

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- ① 图版头 (决策页是三级页, 压到 86px: 问题与选项要吃掉尽量多的竖向空间) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 86
            color: CommonOptions.colorSurfaceDim

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorText
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
                    onClicked: decisionPage.goBack()
                }
            }

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: styles.pageMargin
                // 别让标题压在返回方块底下
                anchors.rightMargin: styles.pageMargin + 34
                anchors.bottomMargin: styles.spSm
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: "决策走法"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: decisionPage.entry.title || "急救决策"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    // 只报页面自己数得出来的东西: 答了几问 / 现在第几问 / 是否已到结论
                    text: {
                        if (!decisionPage.hasTree) return "这条没有决策树 · 库里 0 个节点"
                        if (decisionPage.reachedTerminal)
                            return "已答 " + decisionPage._path.length + " 问 · 已到结论"
                        if (decisionPage.deadEnd)
                            return "已答 " + decisionPage._path.length + " 问 · 这条路库里断了"
                        return "已答 " + decisionPage._path.length + " 问 · 当前第 "
                             + (decisionPage._path.length + 1) + " 问"
                    }
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    elide: Text.ElideRight
                }
            }
        }

        // --- ② 正文 ---
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: styles.bottomClearance   // A41: 末行给下面的吸底条让位
            contentWidth: width
            clip: true
            visible: decisionPage.hasTree

            ColumnLayout {
                width: parent.width
                spacing: styles.spMd

                // 已答路径 (答过的问题原样留在上面, 现场被打断后能接上)
                Repeater {
                    model: decisionPage._path
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        Layout.preferredHeight: pathRow.implicitHeight + 2 * styles.cardPad
                        color: CommonOptions.colorSurfaceAlt
                        border.color: CommonOptions.colorRule
                        border.width: styles.lineHair

                        RowLayout {
                            id: pathRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: styles.cardPad
                            anchors.rightMargin: styles.cardPad
                            spacing: styles.spSm

                            Text {
                                Layout.alignment: Qt.AlignTop
                                text: (index < 9 ? "0" : "") + (index + 1)
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsSm
                                color: CommonOptions.colorInk3
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.q
                                    font.pixelSize: styles.fsSm
                                    color: CommonOptions.colorTextMuted
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "答 · " + modelData.label
                                    font.pixelSize: styles.fsMd
                                    font.bold: true
                                    color: CommonOptions.colorForest
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                // 当前问题 + 选项
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: !decisionPage.ended
                             && (decisionPage.currentNode.id || "").length > 0
                    Layout.preferredHeight: qCol.implicitHeight + 2 * styles.cardPad
                    color: CommonOptions.colorSurface
                    border.color: CommonOptions.colorText
                    border.width: styles.lineHair

                    ColumnLayout {
                        id: qCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: styles.cardPad
                        spacing: styles.spSm

                        Text {
                            Layout.fillWidth: true
                            // Qt 的 QML JS 不保证有 padStart (ES2017), 两位补零自己写
                            text: "第 " + ((decisionPage._path.length + 1) < 10
                                           ? "0" + (decisionPage._path.length + 1)
                                           : String(decisionPage._path.length + 1))
                                  + " 问"
                            // 内部节点 id 不再上界面 (10-22 巡检 H3); 汉字也不走等宽
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: decisionPage.currentNode.question || "请回答以下问题"
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            color: CommonOptions.colorText
                            wrapMode: Text.WordWrap
                        }
                        // 判断要点: 数据里挂在节点的 text 上 (根节点写了牙痕怎么看)
                        Text {
                            Layout.fillWidth: true
                            visible: String(decisionPage.currentNode.text || "").length > 0
                            text: decisionPage.currentNode.text || ""
                            font.pixelSize: styles.fsSm
                            color: CommonOptions.colorTextMuted
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: styles.lineHair
                            Layout.topMargin: 2
                            Layout.bottomMargin: 2
                            color: CommonOptions.colorRuleSoft
                        }

                        Repeater {
                            model: decisionPage._toArr(decisionPage.currentNode.options)
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(styles.touchMin,
                                                                 optRow.implicitHeight + 2 * styles.spSm)
                                color: optionArea.pressed ? CommonOptions.colorSurfaceAlt
                                                          : CommonOptions.colorSurface
                                border.color: optionArea.pressed
                                              ? CommonOptions.colorText : CommonOptions.colorRule
                                border.width: styles.lineHair

                                RowLayout {
                                    id: optRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: styles.cardPad
                                    anchors.rightMargin: styles.cardPad
                                    spacing: styles.spSm

                                    // 选项字母走等宽: A/B/C 是拉丁, 库里汉字一律不进 monoFont
                                    Text {
                                        Layout.alignment: Qt.AlignTop
                                        text: String.fromCharCode(65 + index)
                                        font.family: styles.monoFont
                                        font.pixelSize: styles.fsMd
                                        font.bold: true
                                        color: CommonOptions.colorBlaze
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData
                                        font.pixelSize: styles.fsMd
                                        color: CommonOptions.colorText
                                        wrapMode: Text.WordWrap
                                    }
                                    IconLabel {
                                        Layout.alignment: Qt.AlignVCenter
                                        name: "chevron_right"
                                        size: styles.icSm
                                        tintColor: CommonOptions.colorInk3
                                    }
                                }

                                MouseArea {
                                    id: optionArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: decisionPage._answer(index)
                                }
                            }
                        }
                    }
                }

                // 结论 (真终态): 这是全页唯一一处实心墨底 —— 走完树要看的就这一句
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: decisionPage.reachedTerminal
                    Layout.preferredHeight: endCol.implicitHeight + 2 * styles.cardPad
                    // 2026-10-26 A31: 实心块底必须配 colorTextOnAccent. 原来底是 colorText
                    //   (夜晚翻近白) 而字是 colorOnInk (写死的浅色) → 夜晚档整张「结论」卡
                    //   浅底浅字读不出. 底跟着改成同值的 colorAccent, 语义上才是"实心块".
                    color: CommonOptions.colorAccent

                    ColumnLayout {
                        id: endCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: styles.cardPad
                        spacing: styles.spXs

                        Text {
                            Layout.fillWidth: true
                            text: "结论"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorTextOnAccent
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: decisionPage.terminalAction.length > 0
                                  ? decisionPage.terminalAction
                                  : "这个结论节点在库里没有写处理动作"
                            font.pixelSize: styles.fsMd
                            color: CommonOptions.colorTextOnAccent
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // 数据断链: 明确说"库里没有下一步", 不冒充结论 (规则 ②)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: decisionPage.deadEnd
                    Layout.preferredHeight: deadCol.implicitHeight + 2 * styles.cardPad
                    color: CommonOptions.colorSurface
                    border.color: CommonOptions.colorLegendAmber
                    border.width: styles.lineHair

                    HazardBand {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        stripe: CommonOptions.colorBlaze
                    }

                    ColumnLayout {
                        id: deadCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: styles.hazardBandW + styles.cardPad
                        anchors.rightMargin: styles.cardPad
                        anchors.topMargin: styles.cardPad
                        anchors.bottomMargin: styles.cardPad
                        spacing: styles.spXs

                        Text {
                            Layout.fillWidth: true
                            text: "这条路库里没有下一步"
                            font.pixelSize: styles.fsMd
                            font.bold: true
                            color: CommonOptions.colorHazard
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "急救详情页的步骤与「不要做」覆盖全部情况, 按那边操作即可。"
                            font.pixelSize: styles.fsSm
                            color: CommonOptions.colorTextMuted
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // 走到结论才给拨号门 (规则 ③), 长按 2 秒
                HoldConfirmRow {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: decisionPage.reachedTerminal
                    code: "120"
                    title: "拨打 120"
                    subtitle: "不会自动拨号 · 长按进度条 2 秒确认"
                    onConfirmed: {
                        if (!emergencyService) {
                            console.warn("[decision] emergencyService 不可用")
                            return
                        }
                        emergencyService.call120()
                    }
                }

                // 答过至少一问才谈"重来": 一问没答的根节点, 重按一次是空动作
                PrimaryButton {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: decisionPage._path.length > 0
                    text: "重新开始"
                    iconName: "refresh"
                    tone: CommonOptions.colorText
                    filled: false
                    textSize: styles.fsSm
                    onClicked: decisionPage._restart()
                }

                Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spLg }
            }
        }

        // 取不到树 (entryId 打错 / 这条本来就没有) → 空态说清楚, 不是一张只有骨架的页
        EmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: styles.spXl * 2
            visible: !decisionPage.hasTree
            iconName: "firstaid"
            text: "这条急救没有决策树"
            hint: "entryId=" + decisionPage.entryId + " 在 firstaid_decision_nodes 里没有节点"
            actionText: "返回急救详情"
            onActionTriggered: decisionPage.goBack()
        }

        // --- ③ 底栏 ---
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
                    text: "回详情"
                    tone: CommonOptions.colorTextMuted
                    textSize: styles.fsSm
                    onClicked: decisionPage.goBack()
                }
                Text {
                    Layout.fillWidth: true
                    visible: (decisionPage.entry.id || "").length > 0
                    text: "决策只帮判断, 不替代现场处置 · 拿不准就拨 120"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
