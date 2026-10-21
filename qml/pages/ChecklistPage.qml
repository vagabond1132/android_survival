/**
 * @file ChecklistPage.qml
 * @brief 出门前清点 (2026-10-20 v9 F3, 丁骨架: 标题条 + 进度 + 分组勾选行 + 缺项卡)
 *
 * 两个数据源, 一套版式 (入口决定, 不混):
 *   场景模板 (从「我」第三行 / 底部 build 方位带进来, listId 为空)
 *     checklistService.getTemplates() → 4 份场景 (1日徒步 / 露营 / 车内 / 家庭),
 *     getById(scenario).items 每条有 category / quantity / weightG / required / checked / note.
 *     写回 setItemChecked(scenario, itemId, checked) → SQLite.
 *   装备清单 (从 EquipmentPage / EquipmentDetailPage 带 listId 进来)
 *     equipmentService.getList(listId) → critical/important/recommended/optional 四档,
 *     条目是 {id,name,weightG,reasons,checked}. 写回 setItemChecked(listId, equipmentId, checked).
 *
 * 版式逐块对应已评审的 mock (review-v9-screens.html 「V9 · 3」):
 *   标题条   54px 三段 (GEAR / CHECKLIST 微标签 / 清单名 / 读数行) + 右上 26px 方角返回.
 *   chip 行  只有场景模板有: 四个场景的短名 + 条数.
 *   进度     5px 墨条 + 等宽 "16 / 23" + "PACKED / TOTAL ITEMS" 微标签.
 *   行       15px 方角勾选块 + 名称(带 ×数量) + 副行(备注 / 必备·类别) + 右侧等宽度数.
 *            行高 rowHSm=36 (比绳结目录矮一档: 清单动辄 40 行, 要的是密度不是可点大按钮).
 *   缺项卡   amber 描边 + 左侧 6px hazard 斜纹: 只说"还缺哪几件必备", 列名字.
 *   底栏     上边 1px 墨线: 视图切换两颗 (按类别 / 缺项优先), 当前那一是实心.
 *
 * 三条不能破的规则:
 *   ① 不编读数. 条数 / 必备数 / 重量 / 缺项数全部由 service 返回的 items 现算.
 *      重量按 quantity × weight_g 加权 (mock 的"约 0.9 kg"就是 23 条 890 g 的实际和).
 *      模板 description 里写着"背负重量控制在 700g 以内", 与同一屏算出来的 890 g 打脸
 *      (checklists.json 的历史文案, 数据口径已定"保持现状") → 这一行不显示.
 *   ② 颜色在这一页只承载一件事: hazard 红 = "必备但你还没勾上". 类别本身不上色 ——
 *      13 个打包类别 (急救/取火/求救/净水/工具/防护/食物/照明/水/通信/证件/卫生/生活)
 *      凑不出 13 个互不歧义的图例色, 硬分配就是把图例规则当装饰.
 *   ③ 汉字不进等宽 (见 [[qml-monofont-no-cjk]]). 只有 "N ITEMS"、"PACKED / TOTAL ITEMS"、
 *      宽度数、"16 / 23" 走 monoFont.
 *
 * 2026-10-19 那版的 Hero + 三枚 StatTile + 四段 CategorySection + 两个 Dialog 全部撤掉:
 *   StatTile 的"完成度 87%"和进度条重复; CategorySection 用 CheckBox 与整行点击冲突;
 *   "全部确认完成"那颗按钮点了只弹一句 toast, 没有任何状态写入 —— 死功能, 一并删.
 *   删除清单在 EquipmentPage / EquipmentDetailPage 各有入口, 这里不再放第三颗.
 */

// delegate 里要读 checklistPage 的方法, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: checklistPage

    Styles { id: styles; visible: false }

    // === 入参 ==============================================================
    property string listId: ""       // 非空 = 装备清单入口 (equipmentService)
    property string scenario: ""     // 空 = 取第一份模板

    // true = 按类别分组; false = 缺项优先 (还缺的必备排最前)
    property bool packedByCategory: true

    property var meta: ({})          // {name, kicker, items, required, grams, checked}
    property var rows: []            // head / item 混合行
    property var templates: []       // getTemplates() 排好序的结果

    background: Rectangle { color: CommonOptions.colorBg }
    title: meta.name || "出门前清点"

    readonly property bool useEquipment: listId.length > 0

    // 场景 chip 的固定顺序与短名. 短名是这一页的标签 (完整名在标题条), 数字来自数据.
    // getTemplates() 走 QHash, 遍历序每次启动都可能变 → 不排序的话 chip 会跳.
    readonly property var scenarioOrder: ["hike_1day", "camping_3day",
                                          "car_emergency", "family_emergency"]
    function shortName(id) {
        if (id === "hike_1day") return "1 日徒步"
        if (id === "camping_3day") return "露营"
        if (id === "car_emergency") return "车内"
        if (id === "family_emergency") return "家庭"
        return id
    }

    function _ok(res) { return !!(res && res.ok) }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    // === 取数 ==============================================================
    // 归一化成同一套行结构: mode A (装备) 与 mode B (模板) 只差 group/sub/数量.
    // 形参不叫 id: 那会让行字面量写成 {id: id}, 被 _scratch_debug 的 id 探针当成
    // 一个名为 "id" 的 QML id 声明, 别文件的 model.id 全被报成跨文件引用.
    function _mkItem(itemId, name, qty, grams, group, required, checked, sub) {
        return {
            kind: "item",
            id: itemId,
            name: qty > 1 ? name + " ×" + qty : name,
            sub: sub,
            grams: grams,
            group: group,
            required: required,
            checked: checked,
            missing: required && !checked,
            label: "", count: 0
        }
    }

    // delegate 里两类行的绑定都会求值 —— `visible: false` 不阻止绑定生效,
    // 所以 head 缺 name/sub/checked/grams、item 缺 label/count 都会报
    // "Unable to assign [undefined] to QString/bool/int" (真机 4 处)。两边都补齐。
    function _mkHead(label, count) {
        return {
            kind: "head", label: label, count: count,
            id: "", name: "", sub: "", grams: 0, group: "",
            required: false, checked: false, missing: false
        }
    }

    function _subOf(item, group) {
        var note = item.note || ""
        if (note.length > 0) return note
        return (item.required ? "必备 · " : "") + group
    }

    // 缺项优先模式下的排序: 还缺的必备 → 其余未勾 → 已勾
    function _urgency(r) {
        if (r.missing) return 0
        if (!r.checked) return 1
        return 2
    }

    function _assemble(items) {
        var all = []
        var groups = []
        for (var i = 0; i < items.length; ++i) {
            var r = items[i]
            all.push(r)
            if (groups.indexOf(r.group) < 0) groups.push(r.group)
        }
        var out = []
        if (packedByCategory) {
            for (var g = 0; g < groups.length; ++g) {
                var members = all.filter(function (it) { return it.group === groups[g] })
                out.push(_mkHead(groups[g], members.length))
                for (var m = 0; m < members.length; ++m) out.push(members[m])
            }
        } else {
            var sorted = all.slice().sort(function (a, b) { return _urgency(a) - _urgency(b) })
            var lack = sorted.filter(function (it) { return it.missing })
            out.push(_mkHead("还缺的必备", lack.length))
            for (var s = 0; s < sorted.length; ++s) {
                if (s === lack.length && lack.length > 0)
                    out.push(_mkHead("其余", sorted.length - lack.length))
                out.push(sorted[s])
            }
        }
        return out
    }

    function reload() {
        if (useEquipment) { reloadEquipment(); return }
        reloadScenario()
    }

    function reloadScenario() {
        var raw = checklistService ? checklistService.getTemplates() : []
        var ordered = raw.slice().sort(function (a, b) {
            var ia = scenarioOrder.indexOf(a.id), ib = scenarioOrder.indexOf(b.id)
            if (ia < 0) ia = scenarioOrder.length
            if (ib < 0) ib = scenarioOrder.length
            return ia - ib
        })
        templates = ordered
        if (ordered.length === 0) { meta = ({}); rows = []; return }

        var found = false
        for (var t = 0; t < ordered.length; ++t)
            if (ordered[t].id === scenario) found = true
        if (!found) scenario = ordered[0].id

        var c = checklistService ? checklistService.getById(scenario) : ({})
        if (!c || !c.id) { meta = ({}); rows = []; return }

        var list = []
        var required = 0
        var src = c.items || []
        for (var i = 0; i < src.length; ++i) {
            var it = src[i]
            var qty = Number(it.quantity) || 1
            var grams = (Number(it.weightG) || 0) * qty
            if (it.required) required++
            var grp = it.category || "其他"
            list.push(_mkItem(it.id, it.name || "", qty, grams, grp,
                              !!it.required, !!it.checked, _subOf(it, grp)))
        }
        meta = {
            name: c.name || "",
            kicker: "GEAR / CHECKLIST",
            items: list.length,
            required: required,
            grams: Number(c.totalWeightG) || 0,
            checked: Number(c.checkedCount) || 0
        }
        rows = _assemble(list)
    }

    function reloadEquipment() {
        var l = equipmentService ? equipmentService.getList(listId) : ({})
        if (!l || !l.id) { meta = ({}); rows = []; return }
        // 四档就是这一页的"类别": 档位名自带优先级语义, 不再造第二套分组
        var buckets = [
            { key: "critical", label: "必带（绝对关键）" },
            { key: "important", label: "强必带" },
            { key: "recommended", label: "推荐" },
            { key: "optional", label: "可选" }
        ]
        var list = []
        for (var b = 0; b < buckets.length; ++b) {
            var arr = l[buckets[b].key] || []
            for (var i = 0; i < arr.length; ++i) {
                var it = arr[i]
                var reason = (it.reasons && it.reasons.length) ? it.reasons[0] : buckets[b].label
                list.push(_mkItem(it.id, it.name || "", 1, Number(it.weightG) || 0,
                                  buckets[b].label, b < 2, !!it.checked, reason))
            }
        }
        meta = {
            name: l.name || "装备清单",
            kicker: "GEAR / EQUIPMENT",
            items: list.length,
            // 装备清单的"必备"= critical + important 两档
            required: list.filter(function (r) { return r.required }).length,
            grams: Number(l.totalWeightG) || 0,
            checked: Number(l.checkedCount) || 0
        }
        rows = _assemble(list)
    }

    // 读数行: "23 项 · 必备 19 · 约 0.9 kg（含数量加权）"
    // "含数量加权"只给模板模式 —— 装备清单的条目没有数量字段, 写了就是假口径.
    readonly property string statusLine: {
        if (!meta.items) return useEquipment ? "这份清单没有条目" : "清单数据尚未载入"
        var t = meta.items + " 项 · 必备 " + meta.required
                + " · 约 " + (meta.grams / 1000).toFixed(1) + " kg"
        return useEquipment ? t : t + "（含数量加权）"
    }
    readonly property int missingRequired: {
        var n = 0
        for (var i = 0; i < rows.length; ++i)
            if (rows[i].kind === "item" && rows[i].missing) n++
        return n
    }
    readonly property var missingNames: {
        var out = []
        for (var i = 0; i < rows.length; ++i) {
            if (rows[i].kind === "item" && rows[i].missing) {
                out.push(rows[i].name)
                if (out.length >= 4) break
            }
        }
        return out
    }

    function toggle(row) {
        var svc = useEquipment ? equipmentService : checklistService
        if (!svc) return
        var res = useEquipment ? svc.setItemChecked(listId, row.id, !row.checked)
                               : svc.setItemChecked(scenario, row.id, !row.checked)
        if (!_ok(res))
            console.warn("[checklist] setItemChecked 失败: " + row.id)
        // 服务端会 emit itemChanged / listModified → Connections 再 reload,
        // 这里不自己改 rows, 避免本地状态与库不一致.
    }

    // 两个 service 都在 teardown 期可能为 null, Connections.target 为 null 时不接.
    // 形参个数与信号一致 (itemChanged 有两个参数), 少写不会报错但 qmllint 会提示签名不符.
    Connections {
        target: checklistService
        function onItemChanged(checklistId, itemId) {
            if (!checklistPage.useEquipment && checklistId === checklistPage.scenario)
                checklistPage.reload()
        }
        function onDataChanged() { if (!checklistPage.useEquipment) checklistPage.reload() }
    }
    Connections {
        target: equipmentService
        function onListModified(changedListId) {
            if (checklistPage.useEquipment && changedListId === checklistPage.listId)
                checklistPage.reload()
        }
    }

    Component.onCompleted: reload()
    onListIdChanged: reload()
    onScenarioChanged: { if (!checklistPage.useEquipment) checklistPage.reload() }
    // 分组方式是行序的重排, 不是过滤 —— 换过来时不用重新问 service, 但 rows 要重算
    onPackedByCategoryChanged: reload()

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- 标题条 (54px) ---
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 40      // 给右上角方角让位
                spacing: 3
                Text {
                    text: checklistPage.meta.kicker || "GEAR / CHECKLIST"
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    font.letterSpacing: 1.8
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: checklistPage.meta.name || "出门前清点"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: checklistPage.statusLine
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
                    onClicked: checklistPage.goBack()
                }
            }
        }

        // --- 场景 chip (只有模板模式有; 装备清单只有一份, 没有可换的) ---
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            visible: !checklistPage.useEquipment && checklistPage.templates.length > 1
            spacing: styles.spXs

            Repeater {
                model: checklistPage.templates
                delegate: Chip {
                    required property var modelData
                    text: checklistPage.shortName(modelData.id) + " " + modelData.totalCount
                    checked: modelData.id === checklistPage.scenario
                    accent: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: checklistPage.scenario = modelData.id
                }
            }
        }

        // --- 进度 ---
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spMd
            Layout.bottomMargin: styles.spXs
            visible: checklistPage.meta.items > 0
            spacing: styles.spSm

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 5     // 比 lineAccent(3) 粗一档, 再粗就成色块了
                color: CommonOptions.colorRule
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * fraction
                    readonly property real fraction: checklistPage.meta.items
                        ? Math.min(1, (checklistPage.meta.checked || 0) / checklistPage.meta.items)
                        : 0
                    color: CommonOptions.colorText
                }
            }
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: (checklistPage.meta.checked || 0) + " / " + checklistPage.meta.items
                font.family: styles.monoFont
                font.pixelSize: styles.fsSm
                color: CommonOptions.colorText
            }
        }
        Text {
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            visible: checklistPage.meta.items > 0
            text: "PACKED / TOTAL ITEMS"
            font.family: styles.monoFont
            font.pixelSize: styles.fsXs
            font.letterSpacing: 1.4
            color: CommonOptions.colorInk3
        }

        // --- 清单 ---
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: styles.spSm
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin

            ListView {
                id: packList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: checklistPage.rows
                visible: checklistPage.rows.length > 0

                delegate: Item {
                    required property var modelData
                    width: packList.width
                    height: modelData.kind === "head" ? 30 : styles.rowHSm

                    // 分组标题
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: styles.spSm
                        visible: modelData.kind === "head"
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

                    // 条目行
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: styles.spSm
                        visible: modelData.kind === "item"

                        CheckTick {
                            Layout.alignment: Qt.AlignVCenter
                            on: modelData.checked
                            tone: modelData.missing ? CommonOptions.colorHazard
                                                    : CommonOptions.colorText
                            borderColor: modelData.missing ? CommonOptions.colorHazard
                                                           : CommonOptions.colorRule
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                font.pixelSize: styles.fsMd
                                font.bold: true
                                color: modelData.missing ? CommonOptions.colorHazard
                                                         : CommonOptions.colorText
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
                            color: modelData.missing ? CommonOptions.colorHazard
                                                     : CommonOptions.colorInk3
                        }
                    }

                    // 缺的必备用 hazard 底线挑出来 (规则 ②: 这一页唯一的信号色用途)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: styles.lineHair
                        color: modelData.kind === "item" && modelData.missing
                               ? CommonOptions.colorHazard : CommonOptions.colorRuleSoft
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: modelData.kind === "item"
                        cursorShape: Qt.PointingHandCursor
                        onClicked: checklistPage.toggle(modelData)
                    }
                }

                // 缺项卡: 只说还缺哪几件必备, 不编建议.
                // 外面套 Item 是为了留出与清单的间距 —— ListView.footer 不在布局里,
                // 没有 Layout.topMargin 可用, Rectangle 自己也没有 topMargin.
                footer: Item {
                    width: packList.width
                    // Rectangle 的 implicitHeight 不会跟着显式 height 走 (永远是默认 60),
                    // 所以这里量的是内容列, 不是 lackCard.
                    height: lackCard.visible
                            ? lackCol.implicitHeight + 2 * styles.cardPad + styles.spMd : 0

                    Rectangle {
                        id: lackCard
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        visible: checklistPage.missingRequired > 0
                        height: lackCol.implicitHeight + 2 * styles.cardPad
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
                                id: lackCol
                                Layout.fillWidth: true
                                spacing: 3
                                Text {
                                    Layout.fillWidth: true
                                    text: "缺 " + checklistPage.missingRequired + " 项必备"
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorHazard
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: checklistPage.missingNames.join("、")
                                          + (checklistPage.missingRequired
                                             > checklistPage.missingNames.length ? " 等" : "")
                                          + "。出发前补齐。"
                                    font.pixelSize: styles.fsMd
                                    color: CommonOptions.colorText
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: checklistPage.rows.length === 0
                iconName: "backpack"
                text: checklistPage.useEquipment ? "这份装备清单是空的" : "清单数据没有载入"
                hint: checklistPage.useEquipment
                      ? "回到装备页按行程条件重新生成, 或手动添加要带的条目"
                      : "检查 assets/data/checklists.json 是否打进包里"
                actionText: "重新载入"
                onActionTriggered: checklistPage.reload()
            }
        }

        // --- 底栏: 视图切换 (当前那一是实心) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: barRow.implicitHeight + 2 * styles.spSm
            visible: checklistPage.rows.length > 0
            color: CommonOptions.colorSurfaceAlt

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            RowLayout {
                id: barRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.spLg
                anchors.rightMargin: styles.spLg
                spacing: styles.spMd

                PrimaryButton {
                    Layout.preferredWidth: 88
                    Layout.alignment: Qt.AlignVCenter
                    text: "按类别"
                    filled: checklistPage.packedByCategory
                    tone: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: checklistPage.packedByCategory = true
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    // 缺项数直接进按钮文案: 一眼知道"还有几件必备没带"再决定点不点
                    text: checklistPage.missingRequired > 0
                          ? "缺项优先 " + checklistPage.missingRequired
                          : "缺项优先"
                    filled: !checklistPage.packedByCategory
                    tone: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: checklistPage.packedByCategory = false
                }
            }
        }
    }
}
