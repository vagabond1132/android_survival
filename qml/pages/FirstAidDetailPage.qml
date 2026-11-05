/**
 * @file FirstAidDetailPage.qml
 * @brief 手册 · 急救详情 (2026-10-20 v9 F2 同款, 丁骨架二级页)
 *
 * 入口: FirstAidPage 目录行 / ⑤求助页 TRIAGE 卡 / 决策页返回. navBus.push({entryId}).
 *
 * 版式逐块对应已评审的 mock (review-v9-screens.html 「V9 · 2」绳结详情):
 *   图版头 150px: --paper-sunk 底 + 1px 墨线压底; 左上紧急度 chip, 右上 26px 方角返回,
 *           中间是"紧急度档位 + 5 格梯"的读数块, 底下 编号 + 分类 + 标题 (21px 800).
 *   读数带  4 格 (关键动作 / 步骤 / 不要做 / 关联物种), 数字全是数组长度.
 *   拨号门  紧贴读数带, 不滚动就能看到 —— 这一页常常是在人已经不清醒时打开的.
 *   正文    一句话说明 → 关键动作 (必做) → 症状 → 详细操作 → 不要做 (斜纹卡) →
 *           关联危险物种 → 来源与审核.
 *   底栏    1px 墨线 + --card-2 底; 左 88px 空心「回目录」, 右实心「交互式决策」.
 *
 * 四条不能破的规则:
 *   ① 不编读数. 四格数字来自 firstAidService.getById 的数组长度; 紧急度/分类是字段本身.
 *      库里没有"存活率""黄金 N 分钟"这种字段, 所以那一格不存在.
 *   ② 不假装有图. 35 条的 video_url 全有值但包里没有任何素材 → 不放播放入口,
 *      读数带右侧写明"本库无操作图示".
 *   ③ 汉字不进等宽. 档位数字走 monoFont, "紧急度""危急"等汉字走默认字体
 *      (见 [[qml-monofont-no-cjk]]).
 *   ④ 数据正文里手写的 "1. " 序号与符号前缀一律走 CommonOptions.stripEntryMarker 剥掉,
 *      序号由页面自己排 (#27/#58 的口径: 不动 json, 只在渲染层剥).
 *
 * 35 条里只有蛇咬伤有交互决策树 (decision_nodes 8 个节点), 所以底栏那颗按钮大多数时候
 * 不出现 —— 出现的是"这条没有决策树, 按上面步骤操作"这句实话, 不是一点了就跳空的假按钮.
 */

// delegate 里要读 firstAidDetail 的方法与属性, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: firstAidDetail

    Styles { id: styles; visible: false }

    title: entity.title || "急救详情"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property string entryId: ""
    property var entity: ({})

    function urgencyName(u) {
        if (u === 5) return "危急"
        if (u === 4) return "高"
        if (u === 3) return "中"
        if (u === 2) return "低"
        if (u === 1) return "知识"
        return "未分级"
    }

    function categoryName(c) {
        if (c === 0) return "急症优先"
        if (c === 1) return "创伤处理"
        if (c === 2) return "环境急症"
        if (c === 3) return "中毒急救"
        if (c === 4) return "应急功能"
        return "分类"
    }

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
        if (!entryId || !firstAidService) return
        entity = firstAidService.getById(entryId)
    }

    onEntryIdChanged: firstAidDetail._load()
    // StackView 的 initialProperties 一条条落地, itemId 先到时 service 可能还没就绪,
    // 补一次首帧兜底 (空 entryId 会在 _load 里直接 return, 不多跑空查表).
    Component.onCompleted: firstAidDetail._load()

    // === 派生字段 ==========================================================
    readonly property var _actions: _toArr(entity.criticalActions)
    readonly property var _steps: _toArr(entity.steps)
    readonly property var _donts: _toArr(entity.donts)
    readonly property var _symptoms: _toArr(entity.symptoms)
    readonly property var _speciesIds: _toArr(entity.relatedSpecies)
    readonly property int _urgency: Number(entity.urgency) || 0
    readonly property bool _hasDecision: entity.decisionNodeExists === true

    // 关联物种: 库里查不到的也列出来但点不动 (灰), 查得到的给中文名
    readonly property var _species: {
        var out = []
        for (var i = 0; i < _speciesIds.length; ++i) {
            var sid = _speciesIds[i]
            var hit = speciesService ? speciesService.getById(sid) : ({})
            var resolved = !!(hit && hit.id)
            out.push({
                id: sid,
                name: resolved ? (hit.commonName || hit.name || sid) : sid,
                enabled: resolved
            })
        }
        return out
    }

    readonly property color _tone: CommonOptions.dangerColor(_urgency)

    // 这里刻意没有"下一条". 绳结是一套要按顺序练的阶梯, 急救条目是按紧急度排的查阅表:
    // 从"危急"目录点进蛇咬伤, 翻到下一条可能是"低"档的知识条目 —— 那种轮播在救护现场
    // 只会碍事. 顺序留在目录页 (FirstAidPage 按紧急度分组) 里给, 详情只负责这一条.

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

            // 中间: 紧急度档位 + 5 格梯. 库里没有操作图示, 这块放读数而不是假图 (规则 ②).
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
                        text: firstAidDetail._urgency > 0 ? String(firstAidDetail._urgency) : "—"
                        font.family: styles.monoFont
                        font.pixelSize: 34
                        color: firstAidDetail._tone
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        visible: firstAidDetail._urgency > 0
                        text: "级 " + firstAidDetail.urgencyName(firstAidDetail._urgency)
                        font.pixelSize: styles.fsMd
                        color: CommonOptions.colorTextMuted
                    }
                }
                Ladder {
                    anchors.horizontalCenter: parent.horizontalCenter
                    value: firstAidDetail._urgency
                    tone: firstAidDetail._tone
                    // 顶格 (5 危急) 固定 hazard 红 —— 这是全站允许用红色的两处真危险之一
                    topTone: CommonOptions.colorHazard
                    cellWidth: 9
                    cellHeight: 6
                }
            }

            // 左上: 分类 chip
            Chip {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
                visible: (firstAidDetail.entity.id || "").length > 0
                text: firstAidDetail.categoryName(Number(entity.category))
                accent: firstAidDetail._tone
                checked: true
                textSize: styles.fsXs
            }

            // 右上: 返回方角 26px, 热区向外扩 9px 到 44 (戴手套)
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: styles.pageMargin
                anchors.topMargin: styles.spXs
                width: styles.pageHeadBox
                height: styles.pageHeadBox
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
                    anchors.margins: -styles.pageHeadTapPad
                    cursorShape: Qt.PointingHandCursor
                    onClicked: firstAidDetail.goBack()
                }
            }

            // 底部: 编号 + 条数 (左) / 标题
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
                        code: CommonOptions.plateCode("FA", entity.id || "")
                        tone: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        visible: firstAidDetail._symptoms.length > 0
                        text: firstAidDetail._symptoms.length + " 项识别要点"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: entity.title || "急救详情"
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
                        text: "本条统计"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "这一条没有操作图示"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: [
                            { k: "处置", v: String(firstAidDetail._actions.length) },
                            { k: "步骤", v: String(firstAidDetail._steps.length) },
                            { k: "别做", v: String(firstAidDetail._donts.length) },
                            { k: "物种", v: String(firstAidDetail._species.length) }
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
                                    font.pixelSize: styles.fsXs
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

        // 拨号门: 长按 2 秒才动. 这一页常常是在"人可能已经不清醒"的场景下打开的,
        // 一次误触把 120 拨出去比列表页更糟; 手感与⑤求助页必须一致 (都走同一组件).
        HoldConfirmRow {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spMd
            code: "120"
            title: "拨打 120"
            subtitle: "不会自动拨号 · 长按进度条 2 秒确认"
            onConfirmed: {
                if (!emergencyService) {
                    console.warn("[firstAid detail] emergencyService 不可用")
                    return
                }
                emergencyService.call120()
            }
        }

        // --- ③ 正文 ---
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.bottomMargin: styles.bottomClearance   // A41: 末行给下面的吸底条让位
            Layout.topMargin: styles.spMd
            contentWidth: width
            clip: true
            visible: (firstAidDetail.entity.id || "").length > 0

            ColumnLayout {
                width: parent.width
                spacing: styles.spMd

                // 一句话说明
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: (firstAidDetail.entity.description || "").length > 0
                    text: firstAidDetail.entity.description || ""
                    font.pixelSize: styles.fsMd
                    color: CommonOptions.colorTextMuted
                    wrapMode: Text.WordWrap
                }

                // 关键动作 (必做) —— 这一页最该先读的一块, 排在症状之前
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: firstAidDetail._actions.length > 0
                    Text {
                        Layout.fillWidth: true
                        text: "关键动作 · 必做"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorHazard
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: firstAidDetail._actions.length + " 个动作"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Repeater {
                    model: firstAidDetail._actions
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        spacing: styles.spSm
                        // 序号自排 (hazard 红两位); 数据里的 "1. " 一类前缀剥掉
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: (index < 9 ? "0" : "") + (index + 1)
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsSm
                            color: CommonOptions.colorHazard
                        }
                        Text {
                            Layout.fillWidth: true
                            text: CommonOptions.stripEntryMarker(modelData)
                            font.pixelSize: styles.fsMd
                            font.bold: true
                            color: CommonOptions.colorText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // 识别要点 (数据字段名是 symptoms; 页面上说"怎么认出来")
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: firstAidDetail._symptoms.length > 0
                    Text {
                        Layout.fillWidth: true
                        text: "识别要点"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: firstAidDetail._symptoms.length + " 个体征"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Repeater {
                    model: firstAidDetail._symptoms
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        spacing: styles.spSm
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

                // 详细操作
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: styles.spSm
                    visible: firstAidDetail._steps.length > 0
                    Text {
                        Layout.fillWidth: true
                        text: "详细操作"
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        color: CommonOptions.colorText
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: firstAidDetail._steps.length + " 个步骤"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
                Repeater {
                    model: firstAidDetail._steps
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        spacing: styles.spSm
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: (index < 9 ? "0" : "") + (index + 1)
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsSm
                            color: CommonOptions.colorBlaze
                        }
                        Text {
                            Layout.fillWidth: true
                            // 数据里每条都手写了 "1. " "2. "…, 序号已由左列给出, 剥掉
                            text: CommonOptions.stripEntryMarker(modelData)
                            font.pixelSize: styles.fsMd
                            color: CommonOptions.colorText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // 不要做: 斜纹 + amber 描边卡 (hazard 红只给文字与条纹)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: firstAidDetail._donts.length > 0
                    Layout.preferredHeight: dontRow.implicitHeight + 2 * styles.cardPad
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
                        id: dontRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: styles.hazardBandW + styles.cardPad
                        anchors.rightMargin: styles.cardPad
                        spacing: styles.spSm

                        IconLabel {
                            Layout.alignment: Qt.AlignTop
                            name: "close"
                            size: styles.icMd
                            tintColor: CommonOptions.colorHazard
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: "不要做 · " + firstAidDetail._donts.length + " 条"
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorHazard
                            }
                            Repeater {
                                model: firstAidDetail._donts
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

                // 关联危险物种 (只有蛇咬那几条挂了 related_species)
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    visible: firstAidDetail._species.length > 0
                    spacing: styles.spXs
                    Repeater {
                        model: firstAidDetail._species
                        delegate: Chip {
                            required property var modelData
                            text: (modelData.enabled ? "咬伤源 · " : "目录里没有 · ") + modelData.name
                            textSize: styles.fsSm
                            // 未命中的 id 不弹错也不跳空页: 禁用 + 半透明
                            enabled: modelData.enabled
                            opacity: modelData.enabled ? 1.0 : 0.5
                            onClicked: firstAidDetail.navigateTo("FieldGuideDetailPage", {
                                speciesId: modelData.id,
                                preferDanger: true
                            })
                        }
                    }
                }

                // 来源与审核 (字段有值才写, 不拿"未知"填空)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: styles.pageMargin
                    Layout.rightMargin: styles.pageMargin
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        visible: (firstAidDetail.entity.source || "").length > 0
                        text: "来源 · " + (firstAidDetail.entity.source || "")
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: (firstAidDetail.entity.reviewer || "").length > 0
                        text: "审核 · " + (firstAidDetail.entity.reviewer || "")
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                        wrapMode: Text.WordWrap
                    }
                }

                Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spMd }
            }
        }

        // 取不到条目 (id 打错 / service 还没载入) → 空态, 不是一张只有骨架的页
        EmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: styles.spXl * 2
            visible: (firstAidDetail.entity.id || "").length === 0
            iconName: "firstaid"
            text: "这条急救没有取到"
            hint: "这一条在急救目录里没有收录 · 返回目录换一条"
            actionText: "返回目录"
            onActionTriggered: firstAidDetail.goBack()
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
                    onClicked: firstAidDetail.goBack()
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    visible: firstAidDetail._hasDecision
                    text: "交互式决策 ›"
                    tone: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: firstAidDetail.navigateTo("FirstAidDecisionPage",
                                                         { entryId: firstAidDetail.entryId })
                }
                // 没有树的时候不放假按钮, 直接说清楚这一页就是全部
                Text {
                    Layout.fillWidth: true
                    visible: !firstAidDetail._hasDecision
                             && (firstAidDetail.entity.id || "").length > 0
                    text: "这一条没有分步判断 · 按上面的步骤操作"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
