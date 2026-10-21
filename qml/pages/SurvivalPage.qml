/**
 * @file SurvivalPage.qml
 * @brief 手册 · 野外生活目录 (2026-10-20 v9 F1 同款, 丁骨架二级页)
 *
 * 入口在「我」第一行的手册 → 本页; 底部 build/shelter 方位带也直接进这里.
 * 二级页压在 stackView 里, 所以没有导航带, 返回走标题条右上角的方角.
 *
 * 版式逐块对应已评审的 mock (review-v9-screens.html 「V9 · 1」绳结目录):
 *   标题条   左三段 (MANUAL / FIELD CRAFT 微标签 / 页名 / 读数行), 右上 26px 方角返回.
 *   chip 行  全部 + 有货的类目, 带条数; 再点一次取消筛选.
 *   分组     取火 → 庇护所 → 净水 → 工具 (SurvivalService::Topic 的枚举序).
 *   行       3px 类目条 + 46px 编号列 + 名称/类别·预计时长 + 5 格难度梯 + 人字纹.
 *
 * 三条不能破的规则:
 *   ① 不编数字. 条数/分组数/难度档全部来自 survivalService (totalCount / getByTopic),
 *      页面不写死. survival_items.json 顶层 description 里的概括说法一律不显示.
 *   ② 类目不许多. Topic 枚举有 8 个 (食物/求救信号/导航定向/天气 也定义了), 但库里只有
 *      4 个有货 (取火 6 / 庇护所 4 / 净水 2 / 工具 3, 共 15). 空类目不占 chip,
 *      否则用户点了看空态, 以为数据坏了.
 *   ③ 汉字不进等宽. 编号走 Plate(monoFont + letterSpacing), 名称/类别/时长走默认字体
 *      (见 [[qml-monofont-no-cjk]]).
 *
 * 2026-10-20 改版顺带修掉的两个旧 bug:
 *   - 上一版是 TabBar 三页签 + StackLayout 套 4 个 SurvivalList, 第 3 个页签写着
 *     "工具" 而 SurvivalList 的 topic 传的是 model.index=2, 那是枚举里的 净水(2) 而不是
 *     工具(7) → 点"工具"看到的是净水那两条, 而 topic 3 (食物) 空列表永远点不到.
 *     现在目录只认 topicOrder + 真实条数, 标签与内容不可能再错位.
 *   - SurvivalList 的行标题用 colorTextOnAccent (主色底上的白字) 压在浅色卡面上 →
 *     方案A 浅底之下等于看不见; 且 onClicked 里写 stackView.push(...) 引的是 Main.qml 的
 *     id, qmlcachegen 编译下是 ReferenceError (见 [[qml-delegate-outer-id-pragma]]).
 *     SurvivalList.qml 随本次改版删除, 跳转统一走 navBus.
 */

// delegate 里要读 survivalPage 的方法, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: survivalPage

    Styles { id: styles; visible: false }

    title: "野外生活"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property int currentTopic: -1      // -1 = 全部
    property var rows: []              // 目录行 (head / item 混合)
    property var topicCounts: ({})     // topic -> 条数
    property int diffMin: 0
    property int diffMax: 0

    // service 在 teardown 或未注册时为 null, 读法统一兜底
    readonly property int totalItems: survivalService ? survivalService.totalCount : 0

    // SurvivalService::Topic 的枚举序. 不自排"求生优先级"—— 3 小时失温 / 3 天缺水
    // 那套是口径概括, 数据里没有这个字段, 拿它当排序依据就是编.
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
        return "技能 " + t
    }

    // 类目 → 图例色 (hazard 红留给 SOS 与真危险, 这一页一律不碰):
    //   取火 blaze   CommonOptions 里 blaze 的注释就写着 "火"
    //   庇护所 forest 植被搭的遮体, 与"植被/可食/安全"同绿
    //   净水 water    水源本尊
    //   工具 amber    刀/绳/容器, 用推荐与警示那档, 不是危险
    function topicTone(t) {
        if (t === 0) return CommonOptions.colorBlaze
        if (t === 1) return CommonOptions.colorForest
        if (t === 2) return CommonOptions.colorWater
        if (t === 7) return CommonOptions.colorLegendAmber
        return CommonOptions.colorTextMuted
    }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    function topicCount(t) {
        return topicCounts[t] || 0
    }

    // getByTopic() 遍历的是 QHash, 顺序每次启动都可能变 → 组内按编号排, 目录才稳.
    // 空 topic 直接跳过 (规则 ②).
    function reload() {
        var counts = ({})
        var ordered = []
        var lo = 0
        var hi = 0
        for (var i = 0; i < topicOrder.length; ++i) {
            var t = topicOrder[i]
            var src = survivalService ? survivalService.getByTopic(t) : []
            if (src.length === 0) continue
            counts[t] = (counts[t] || 0) + src.length
            for (var k = 0; k < src.length; ++k) {
                var it = src[k]
                var d = Number(it.difficulty) || 0
                if (lo === 0 || d < lo) lo = d
                if (d > hi) hi = d
                ordered.push({
                    kind: "item",
                    topic: t,
                    id: it.id || "",
                    name: it.name || "",
                    category: it.category || "",
                    difficulty: d,
                    minutes: Number(it.estimatedTimeMin) || 0,
                    plate: CommonOptions.plateCode("SV", it.id || ""),
                    tone: topicTone(t),
                    label: "", count: 0
                })
            }
        }
        ordered.sort(function (a, b) { return a.plate < b.plate ? -1 : (a.plate > b.plate ? 1 : 0) })

        var out = []
        for (var c = 0; c < topicOrder.length; ++c) {
            var t2 = topicOrder[c]
            if (!counts[t2]) continue
            if (currentTopic !== -1 && t2 !== currentTopic) continue
            var members = ordered.filter(function (x) { return x.topic === t2 })
            // 两类行必须同键: delegate 里的绑定一律求值 (`visible: false` 不拦绑定),
            // 少一个键真机上就是 "Unable to assign [undefined] to QString/bool/int"。
            out.push({
                kind: "head",
                topic: t2,
                label: topicLabel(t2),
                count: members.length,
                tone: topicTone(t2),
                id: "", name: "", category: "", difficulty: 1, minutes: 0, plate: ""
            })
            for (var m = 0; m < members.length; ++m) out.push(members[m])
        }
        topicCounts = counts
        diffMin = lo
        diffMax = hi
        rows = out
    }

    // 读数行: "15 项 · 取火 6 庇护所 4 净水 2 工具 3 · 难度 1~5"
    readonly property string statusLine: {
        if (totalItems === 0) return "野外生活数据尚未载入"
        var t = totalItems + " 项"
        for (var i = 0; i < topicOrder.length; ++i) {
            var c = topicOrder[i]
            if (topicCounts[c]) t += " · " + topicLabel(c) + " " + topicCounts[c]
        }
        return diffMax > 0 ? t + " · 难度 " + diffMin + "~" + diffMax : t
    }

    Component.onCompleted: reload()
    Connections {
        target: survivalService
        function onDataChanged() { survivalPage.reload() }
    }

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- 标题条 (54px: 微标签 / 页名 / 读数行, 右上 26px 方角返回) ---
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                // 给右上角的方角让位, 否则读数行从它底下穿过
                anchors.rightMargin: 40
                spacing: 3
                Text {
                    text: "MANUAL / FIELD CRAFT"
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    font.letterSpacing: 1.8
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: "野外生活"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: survivalPage.statusLine
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: styles.spXs
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
                    onClicked: survivalPage.goBack()
                }
            }
        }

        // --- 类目 chip (全部 + 有货的类目) ---
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            spacing: styles.spXs

            Repeater {
                model: [-1].concat(survivalPage.topicOrder.filter(function (t) {
                    return survivalPage.topicCount(t) > 0
                }))
                delegate: Chip {
                    required property var modelData
                    text: (modelData === -1 ? "全部 " : survivalPage.topicLabel(modelData) + " ")
                          + (modelData === -1 ? survivalPage.totalItems
                                              : survivalPage.topicCount(modelData))
                    // 选中态是墨底, 不是类目色 —— 这一行只表"在看哪一组"
                    checked: survivalPage.currentTopic === modelData
                    accent: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: survivalPage.currentTopic =
                               (survivalPage.currentTopic === modelData) ? -1 : modelData
                }
            }
        }

        // --- 目录 ---
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: styles.spSm
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin

            ListView {
                id: lifeList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: survivalPage.rows

                delegate: Item {
                    required property var modelData
                    width: lifeList.width
                    height: modelData.kind === "head" ? 30 : styles.touchMin

                    // 分组标题
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: styles.spSm
                        visible: modelData.kind === "head"

                        Rectangle {
                            Layout.preferredWidth: styles.lineAccent
                            Layout.fillHeight: true
                            Layout.topMargin: 9
                            Layout.bottomMargin: 9
                            color: modelData.tone
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        // 拉丁微标签才加字距, 中文不加 (样式铁律)
                        Text {
                            text: modelData.count + " SKILLS"
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsXs
                            font.letterSpacing: 1.4
                            color: CommonOptions.colorInk3
                        }
                    }

                    // 条目行
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: 9
                        visible: modelData.kind === "item"

                        Rectangle {
                            Layout.fillHeight: true
                            Layout.preferredWidth: styles.lineAccent
                            color: modelData.tone
                        }
                        Plate {
                            Layout.preferredWidth: styles.plateW
                            Layout.alignment: Qt.AlignVCenter
                            code: modelData.plate
                            tone: CommonOptions.colorInk3
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsMd
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.category
                                      + (modelData.minutes > 0 ? " · 约 " + modelData.minutes + " 分钟" : "")
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                                elide: Text.ElideRight
                            }
                        }
                        // 难度梯 5 格: 格数 = 档位上限, 实心格 = 该条难度.
                        // 用 difficultyColor 同族色 (C++ 侧注释已说明 4/5 档允许进红族).
                        Ladder {
                            Layout.alignment: Qt.AlignVCenter
                            value: modelData.difficulty
                            tone: CommonOptions.difficultyColor(modelData.difficulty)
                        }
                        IconLabel {
                            Layout.alignment: Qt.AlignVCenter
                            name: "chevron_right"
                            size: 14
                            tintColor: CommonOptions.colorInk3
                        }
                    }

                    // 组标题下不留描边 (分组靠空白分级), 条目行才有 1px 组线
                    Rectangle {
                        visible: modelData.kind === "item"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: styles.lineHair
                        color: CommonOptions.colorRuleSoft
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: modelData.kind === "item"
                        cursorShape: Qt.PointingHandCursor
                        onClicked: survivalPage.navigateTo("SurvivalDetailPage",
                                                            { itemId: modelData.id })
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: survivalPage.rows.length === 0
                iconName: "shelter"
                text: survivalPage.totalItems === 0 ? "野外生活库没有载入" : "这一类没有条目"
                hint: survivalPage.totalItems === 0
                      ? "重装 APK 或检查 assets/data/survival_items.json 是否打进包里"
                      : "换一个类目, 或点上面的「全部」"
                actionText: survivalPage.totalItems === 0 ? "重新载入" : "看全部"
                onActionTriggered: {
                    if (survivalPage.totalItems === 0) survivalPage.reload()
                    else survivalPage.currentTopic = -1
                }
            }
        }
    }
}
