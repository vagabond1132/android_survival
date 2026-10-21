/**
 * @file EquipmentDetailPage.qml
 * @brief 装备清单档案 (2026-10-20 v9 F2 同款, 丁骨架二级页)
 *
 * 入口: EquipmentPage 清单行 / 生成清单后 navBus.push({listId}).
 * 出口: 底栏「出门前清点」→ ChecklistPage{listId}, 勾选只在那一页发生.
 *
 * 版式逐块对应已评审的 F2 骨架 (同 SurvivalDetailPage / TravelDetailPage):
 *   图版头 150px: colorSurfaceDim 底 + 1px 墨线压底; 左上参数 chip, 右上 26px 方角返回,
 *           中间总重量大字 + 难度梯, 底下 编号 + 状态句 + 清单名 (21px 800).
 *   读数带  4 格 (必带 / 强必带 / 推荐 / 可选), 数字全是四档数组的长度.
 *   进度    5px 墨条 + 等宽 "n / N" + "PACKED / TOTAL ITEMS".
 *   正文    四档分组 × 行 (方角勾选块 + 名称/理由 + 等宽度数, 一列扫下来能当秤读).
 *   底栏    1px 墨线 + colorSurfaceAlt 底; 左 96px 空心「导出 TXT」, 右实心「出门前清点」.
 *
 * 四条不能破的规则:
 *   ① 不编读数. 本页数字全部来自 equipmentService.getList: altitudeMax/Min/Camp, days,
 *      difficulty, totalWeightG, checkedCount, isCompleted + 四档数组. 那份接口不返回
 *      altitudeLevel/altitudeLevelName (只有 getAllLists 返回), 所以档位名只出现在
 *      EquipmentPage 的分组标题, 这一页不重复也不猜.
 *   ② 勾选不在这页. ChecklistPage 才是"清点"的动作面. 改版前这页借 CategorySection 又画
 *      了一遍 CheckBox + 划掉文字, 同一份状态出现两个写入口; 现在行首是纯读数方块
 *      CheckTick, 要看/要改就按底栏去清点页.
 *   ③ 结果要读得完. exportToPdf 返回的是 "已导出: <整串路径>", 长到 toast 消失前读不完
 *      → 改成底栏上方的常驻 note, service 的原文照抄, 不翻译不改写. 所以本页不再引用 toast.
 *   ④ 不硬编兜底路径. 旧代码在拿不到 App.dataPath 时退回 "/sdcard/Android/data/
 *      com.outdoor.survival/files/..." 再试一次: 包名写死后改 applicationId 就静默失效,
 *      而且 exportToPdf 内部不 mkdir, 父目录不存在必回 "导出失败". App.dataPath 取自
 *      QStandardPaths::AppDataLocation 且 App.cpp 已 mkpath → 只用它; 拿不到就在 note
 *      里说清楚, 不做第二次尝试.
 */

// delegate 里要读 detailPage 的属性, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: detailPage

    Styles { id: styles; visible: false }

    title: entity.name || "装备清单"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 状态 ==============================================================
    property string listId: ""
    property var entity: ({})
    // 导出/删除的结果原文, 常驻在底栏上方 (规则 ③)
    property string note: ""
    // head / item 混合行, 与 ChecklistPage 的 rows 同一套画法
    property var rows: []

    // 四档 = getList 的四个字段. 颜色只用"类别"色里的三档 + 三级墨,
    // hazard 留给真正缺装备的信号 (见规则 ② 下的缺项文字).
    readonly property var buckets: [
        { key: "critical",    label: "必带（绝对关键）", short: "CRITICAL",  tone: CommonOptions.colorHazard },
        { key: "important",   label: "强必带",           short: "IMPORTANT", tone: CommonOptions.colorWarn },
        { key: "recommended", label: "推荐",             short: "RECOMMEND", tone: CommonOptions.colorLegendAmber },
        { key: "optional",    label: "可选",             short: "OPTIONAL",  tone: CommonOptions.colorInk3 }
    ]

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    function _toArr(v) { return (v && v.length !== undefined) ? v : [] }

    function refresh() {
        if (!equipmentService || !detailPage.listId) { detailPage.entity = ({}); return }
        var e = equipmentService.getList(detailPage.listId)
        // getList 对不存在的 id 返回空 map (没有 id 字段), 不抛错
        detailPage.entity = (e && e.id) ? e : ({})
        detailPage.rebuild()
    }

    // 展平成 head + item 两组行; 必备 = 前两档 (与 ChecklistPage 的 required 同口径)
    function rebuild() {
        var out = []
        for (var b = 0; b < buckets.length; ++b) {
            var bk = buckets[b]
            var arr = detailPage._toArr(detailPage.entity[bk.key])
            if (arr.length === 0) continue
            out.push({ kind: "head", label: bk.label, tone: bk.tone, count: arr.length })
            for (var i = 0; i < arr.length; ++i) {
                var it = arr[i]
                var why = detailPage._toArr(it.reasons)
                out.push({
                    kind: "item",
                    itemId: String(it.id || ""),
                    name: String(it.name || "未命名装备"),
                    sub: String(why.length > 0 ? why[0] : ""),
                    grams: Number(it.weightG) || 0,
                    tone: bk.tone,
                    required: b < 2,
                    checked: it.checked === true
                })
            }
        }
        detailPage.rows = out
    }

    // StackView 的 initialProperties 是一条条赋的: listId 先落地时 service 可能还没就绪,
    // 两个时机各补一次; refresh 对空 listId 直接清空, 不会多跑空查表.
    onListIdChanged: { detailPage.note = ""; detailPage.refresh() }
    Component.onCompleted: detailPage.refresh()

    // === 派生字段 ==========================================================
    readonly property bool hasList: (entity.id || "").length > 0

    readonly property int criticalItems: _toArr(entity.critical).length
    readonly property int importantItems: _toArr(entity.important).length
    readonly property int recommendedItems: _toArr(entity.recommended).length
    readonly property int optionalItems: _toArr(entity.optional).length

    readonly property int totalItems: criticalItems + importantItems
                                     + recommendedItems + optionalItems
    readonly property int requiredItems: criticalItems + importantItems
    readonly property int checkedItems: Number(entity.checkedCount) || 0
    readonly property int packedWeightG: Number(entity.totalWeightG) || 0
    readonly property int difficulty: Number(entity.difficulty) || 0

    // 还没勾的必备件数 —— 纯读 entity, 不另开状态
    readonly property int lackRequired: {
        var n = 0
        var keys = ["critical", "important"]
        for (var k = 0; k < keys.length; ++k) {
            var arr = _toArr(entity[keys[k]])
            for (var i = 0; i < arr.length; ++i)
                if (arr[i].checked !== true) ++n
        }
        return n
    }

    readonly property real packedFraction: totalItems > 0
        ? Math.min(checkedItems, totalItems) / totalItems : 0

    // 顶部状态句: 每件数字都能回溯到 getList 的字段
    readonly property string statusLine: {
        if (!detailPage.hasList) return ""
        var s = detailPage.totalItems + " 件 · 必备 " + detailPage.requiredItems
        if (detailPage.lackRequired > 0) s += " · 还缺 " + detailPage.lackRequired
        s += " · 难度 " + detailPage.difficulty + " 星"
        s += entity.isCompleted === true ? " · 已清点" : " · 未清点"
        return s
    }

    // kg 只给数字用等宽, "千克" 走默认字体 (见 [[qml-monofont-no-cjk]])
    readonly property string weightKgText: (detailPage.packedWeightG / 1000).toFixed(2)

    // === 动作 ==============================================================
    function exportList() {
        if (!equipmentService) { detailPage.note = "装备服务没有就绪"; return }
        if (!detailPage.listId) { detailPage.note = "这份清单没有 id, 无法导出"; return }
        // 拿不到 App.dataPath 就不再猜别的路径 (规则 ④)
        if (typeof App === "undefined" || !App || !App.dataPath) {
            detailPage.note = "取不到应用数据目录, 导出没有执行"
            return
        }
        var safe = String(detailPage.entity.name || "装备清单")
                    .replace(/[\/\\:*?"<>|]/g, "_")
        var path = String(App.dataPath) + "/装备清单-" + safe + ".txt"
        var r = equipmentService.exportToPdf(detailPage.listId, path)
        detailPage.note = (r && r.length > 0) ? String(r) : "导出没有返回结果"
    }

    function removeList() {
        if (!equipmentService || !detailPage.listId) {
            confirmDeleteDialog.close()
            detailPage.note = "装备服务没有就绪"
            return
        }
        var r = equipmentService.deleteList(detailPage.listId)
        confirmDeleteDialog.close()
        // deleteList 返回 Result 包装
        if (r && r.ok === false) {
            detailPage.note = (r.error && r.error.message) || "删除清单失败"
        } else {
            detailPage.goBack()
        }
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

            // 中间: 总重量 + 难度梯. 两个都是 getList 的字段, 不是估算.
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
                        text: detailPage.totalItems > 0 ? detailPage.weightKgText : "—"
                        font.family: styles.monoFont
                        font.pixelSize: 34
                        color: CommonOptions.colorText
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        visible: detailPage.totalItems > 0
                        text: "千克"
                        font.pixelSize: styles.fsMd
                        color: CommonOptions.colorTextMuted
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: styles.spSm
                    Ladder {
                        anchors.verticalCenter: parent.verticalCenter
                        value: detailPage.difficulty
                        tone: CommonOptions.difficultyColor(detailPage.difficulty)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: CommonOptions.difficultyLabel(detailPage.difficulty)
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }
            }

            // 左上: 行程 + 海拔上限 (一格话, 先看这场是什么规模)
            Chip {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: styles.pageMargin
                anchors.topMargin: styles.spSm
                visible: detailPage.hasList
                text: (Number(entity.days) || 0) + " 天 · 上限 "
                      + (Number(entity.altitudeMax) || 0) + " m"
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
                    onClicked: detailPage.goBack()
                }
            }

            // 底部: 编号 + 名称 + 状态句
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
                        visible: detailPage.hasList
                        code: CommonOptions.plateCode("PK", detailPage.listId)
                        bracketed: true
                        tone: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        visible: detailPage.hasList
                        text: "PACKING LIST"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.8
                        color: CommonOptions.colorInk3
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: detailPage.entity.name || "装备清单"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: detailPage.statusLine.length > 0
                    text: detailPage.statusLine
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                    elide: Text.ElideRight
                }
            }
        }

        // --- ② 四格读数带 ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: readoutCol.implicitHeight + 2 * styles.spSm
            visible: detailPage.hasList
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
                        text: "BUCKET COUNTS"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.4
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    // 档位名只有 getAllLists 有, 这一页不猜 (规则 ①)
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: (Number(entity.altitudeMin) || 0) + "–"
                              + (Number(entity.altitudeMax) || 0) + " m"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: [
                            { k: "CRITICAL",  v: String(detailPage.criticalItems),
                              t: CommonOptions.colorHazard },
                            { k: "IMPORTANT", v: String(detailPage.importantItems),
                              t: CommonOptions.colorWarn },
                            { k: "RECOMMEND", v: String(detailPage.recommendedItems),
                              t: CommonOptions.colorLegendAmber },
                            { k: "OPTIONAL",  v: String(detailPage.optionalItems),
                              t: CommonOptions.colorInk3 }
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
                                    font.pixelSize: styles.fs2xl
                                    color: modelData.t
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- ③ 清点进度 ---
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spMd
            Layout.bottomMargin: styles.spSm
            visible: detailPage.hasList
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spSm
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 5
                    Layout.alignment: Qt.AlignVCenter
                    color: CommonOptions.colorRuleSoft
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * detailPage.packedFraction
                        color: CommonOptions.colorText
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: detailPage.checkedItems + " / " + detailPage.totalItems
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsSm
                    color: CommonOptions.colorText
                }
            }
            Text {
                text: "PACKED / TOTAL ITEMS"
                font.family: styles.monoFont
                font.pixelSize: styles.fsXs
                font.letterSpacing: 1.4
                color: CommonOptions.colorInk3
            }
        }

        // --- ④ 正文 (四档 × 行) ---
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: detailPage.rows.length > 0

            ListView {
                id: archiveList
                anchors.fill: parent
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: detailPage.rows

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: archiveList.width
                    height: modelData.kind === "head" ? 30 : styles.rowHSm

                    // 分组标题: 3px 档位色条 + 名称 + 件数
                    RowLayout {
                        anchors.fill: parent
                        spacing: styles.spSm
                        visible: modelData.kind === "head"
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: styles.lineAccent
                            Layout.preferredHeight: 14
                            color: modelData.tone
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            color: CommonOptions.colorText
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: modelData.count + " ITEMS"
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsXs
                            font.letterSpacing: 1.4
                            color: CommonOptions.colorInk3
                        }
                    }

                    // 条目行: 勾选块只作读数, 不是控件 (规则 ②)
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: styles.spSm
                        visible: modelData.kind === "item"

                        CheckTick {
                            Layout.alignment: Qt.AlignVCenter
                            on: modelData.checked
                            tone: modelData.tone
                            borderColor: modelData.checked
                                       ? modelData.tone : CommonOptions.colorRule
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                font.pixelSize: styles.fsMd
                                font.bold: true
                                // 必备且还没勾 = 这一屏唯一该跳红的一处
                                color: (modelData.required && !modelData.checked)
                                       ? CommonOptions.colorHazard : CommonOptions.colorText
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: modelData.sub
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                                elide: Text.ElideRight
                            }
                        }
                        // 宽度数: 等宽右对齐, 一列扫下来能当秤读
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: Math.round(modelData.grams) + " g"
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                        }
                    }

                    // 行底线 (组头下面不画, 免得把标题压成一行数据)
                    Rectangle {
                        visible: modelData.kind === "item"
                                 && (!detailPage._nextIsHead(index))
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: styles.lineHair
                        color: CommonOptions.colorRuleSoft
                    }
                }
            }
        }

        // 取不到这份清单 (id 打错 / 已被删) → 空态, 不是一张只有骨架的页
        EmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: styles.spXl * 2
            visible: !detailPage.hasList
            iconName: "backpack"
            text: "这份清单没有取到"
            hint: "listId=" + detailPage.listId + " 不在装备清单里"
            actionText: "回装备页"
            onActionTriggered: detailPage.navigateTo("EquipmentPage", {})
        }

        // --- 删除入口 (destructive 走 Dialog, 不是一按就删) ---
        // 整行热区 (戴手套): RowLayout 里塞不进 anchors.fill 的 MouseArea, 所以外面
        //   套一层 Item, 让行内容和点击区各自铺满.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: styles.rowHSm
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            visible: detailPage.hasList

            RowLayout {
                anchors.fill: parent
                spacing: styles.spSm
                IconLabel {
                    Layout.alignment: Qt.AlignVCenter
                    name: "delete"
                    size: styles.icSm
                    tintColor: CommonOptions.colorDanger
                }
                Text {
                    Layout.fillWidth: true
                    text: "删除这份清单"
                    font.pixelSize: styles.fsMd
                    color: CommonOptions.colorDanger
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: confirmDeleteDialog.open()
            }
        }

        // --- ⑤ 底栏 ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: bottomCol.implicitHeight + 2 * styles.spSm
            color: CommonOptions.colorSurfaceAlt

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            ColumnLayout {
                id: bottomCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.spLg
                anchors.rightMargin: styles.spLg
                spacing: styles.spXs

                // 结果原文常驻 (规则 ③): 路径太长, toast 3 秒就没了
                Text {
                    Layout.fillWidth: true
                    visible: detailPage.note.length > 0
                    text: detailPage.note
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorLegendAmber
                    elide: Text.ElideMiddle
                    wrapMode: Text.NoWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spMd

                    OutlineButton {
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: styles.btnHSm
                        Layout.alignment: Qt.AlignVCenter
                        text: "导出 TXT"
                        tone: CommonOptions.colorTextMuted
                        textSize: styles.fsSm
                        onClicked: detailPage.exportList()
                    }
                    PrimaryButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: styles.btnHSm
                        Layout.alignment: Qt.AlignVCenter
                        text: "出门前清点"
                        iconName: "check"
                        tone: CommonOptions.colorAccent
                        textSize: styles.fsSm
                        enabled: detailPage.totalItems > 0
                        onClicked: detailPage.navigateTo("ChecklistPage",
                                                         { listId: detailPage.listId })
                    }
                }
            }
        }
    }

    // 行底线用: 下一行是不是组头
    function _nextIsHead(i) {
        var n = detailPage.rows[i + 1]
        return !!n && n.kind === "head"
    }

    Dialog {
        id: confirmDeleteDialog
        title: "删除清单"
        anchors.centerIn: parent
        width: Math.min(420, detailPage.width - 2 * styles.pageMargin)
        padding: styles.spMd
        // 全站 Material 弹层背景/前景只认这两个 attached 属性, 写 color: 不生效
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        standardButtons: Dialog.NoButton

        contentItem: Text {
            text: "确定要删除清单「" + (detailPage.entity.name || "")
                  + "」吗？这份清单连同勾选记录一起从设备里去掉，不可撤销。"
            color: CommonOptions.colorText
            font.pixelSize: styles.fsMd
            wrapMode: Text.WordWrap
        }

        footer: RowLayout {
            spacing: styles.spSm
            Item { Layout.fillWidth: true }
            OutlineButton {
                Layout.preferredWidth: 88
                Layout.preferredHeight: styles.btnHSm
                Layout.alignment: Qt.AlignVCenter
                text: "留着"
                tone: CommonOptions.colorTextMuted
                textSize: styles.fsSm
                onClicked: confirmDeleteDialog.close()
            }
            OutlineButton {
                Layout.preferredWidth: 88
                Layout.preferredHeight: styles.btnHSm
                Layout.alignment: Qt.AlignVCenter
                text: "删除"
                tone: CommonOptions.colorDanger
                textSize: styles.fsSm
                onClicked: detailPage.removeList()
            }
        }
    }

    Connections {
        target: equipmentService
        // 勾选/生成/命名都可能在别处发生, 三个信号统一走一次 refresh
        function onListModified(changedId) {
            if (changedId === detailPage.listId) detailPage.refresh()
        }
        function onListGenerated(changedId) {
            if (changedId === detailPage.listId) detailPage.refresh()
        }
        function onDataChanged() { detailPage.refresh() }
    }
}
