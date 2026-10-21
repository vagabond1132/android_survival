/**
 * @file EquipmentPage.qml
 * @brief 装备清单生成 + 我的清单 + 装备库 (2026-10-20 v9 F1/F3 同款, 丁骨架二级页)
 *
 * 入口有两个: 顶栏菜单抽屉的「装备」(Main.qml case "pack") 与「我」页第四行
 * (MePage), 都压在 stackView 上, 没有底部方位带 → 返回走标题条右上角的方角.
 *
 * 版式逐块对应已评审的 mock (review-v9-screens.html 「V9 · 3」+ 手册目录 F1 母版):
 *   标题条   54px 三段 (GEAR / xxx 微标签 / 视图名 / 读数行) + 右上 26px 方角返回.
 *   视图     三枚 chip 一行 (生成 / 我的清单 N / 装备库 N) 取代旧 TabBar + StackLayout.
 *   表单     两张 Card (行程 / 环境), 整块放在 ScrollView 里, 底栏钉住主操作.
 *   清单行   3px 海拔条 + 名称/副行 + 等宽度数 + 行内三枚方角动作块.
 *   库行     46px 图鉴编号 + 名称/类别 + 等宽度数 + 编辑(基础=复制副本)/删除.
 *   底栏     上边 1px 墨线: 左 OutlineButton 次级, 右 PrimaryButton 主操作.
 *
 * 四条不能破的规则:
 *   ① 不编读数. 库件数 / 关键件数 / 清单份数 / 重量全部由 equipmentService 现算,
 *      页面不写死 43 或 5.
 *   ② 表单里每一项都真的进 params. 旧版还发 tempAvg/tempMin/uvIndex/people 四个字段,
 *      但 equipment_rules.json 的 39 条规则里没有任何温度或人数条件
 *      (RuleConditionStrategy 注册的前缀: altitude/precipitation/season/wind_speed/
 *      wind_level/difficulty/days/diurnal_range/humidity/uv_level/is_*), 留着等于
 *      让用户以为"调了有用" → 一并删掉, 并在卡片注里写明不参与.
 *   ③ 汉字不进等宽 (见 [[qml-monofont-no-cjk]]). 只有编号、"N ITEMS"、度数与 kg/g 走 monoFont.
 *   ④ 不给假入口. 基础库条目不可删 → 删除方块直接不出现 (旧版是 enabled:false + 0.3 透明),
 *      左滑手势撤掉, 所有动作都在行内看得见.
 *
 * 2026-10-20 顺带修掉的三处旧病:
 *   - 输入卡片被限高 40% 内部滚动, "生成"按钮与下方清单挤在同一屏里够不到 (#36).
 *     现在整页只有一个滚动方向: 表单在 ScrollView 内滚, 底栏常驻.
 *   - 三个 Dialog 的 ComboBox + CheckBox 换成文字 chip, 弹层按钮走自定义 footer,
 *     不再出现英文 OK/Cancel (#41).
 *   - 装备库的类别是英文键 (rescue/protection/...), 旧版只映射成图标、从不显示;
 *     现在按中文类别分组并把键译显示出来 (#37 同类).
 */

// delegate 里要读 equipmentPage 的方法与状态, qmlcachegen 静态编译下必须 Bound,
// 否则真机静默 ReferenceError (见 [[qml-delegate-outer-id-pragma]]).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: equipmentPage

    Styles { id: styles; visible: false }

    title: "装备清单"
    background: Rectangle { color: CommonOptions.colorBg }

    // === 视图: 0 生成 / 1 我的清单 / 2 装备库 ==============================
    property int view: 0

    // === 生成器表单 (字段顺序与 EquipmentService::generateList 读键顺序同源) ===
    property int altMax: 1500
    property int days: 2
    property int difficulty: 2          // 1-5
    property int seasonIndex: 1         // 0春 1夏 2秋 3冬
    property int precipIndex: 0         // 0无 1小 2中 3大 4暴
    property int humidityIndex: 1       // 0干 1中 2湿
    property int uvLevelIndex: 2        // 0弱 1中 2强 3很强 4极强
    property int windLevelIndex: 1      // 0静 1微 2中 3大 4强
    property int diurnalRange: 10       // °C, 规则阈值 15 / 20
    property bool isRainySeason: false
    property bool isDesert: false
    property bool isCoastal: false

    // === 数据 ==============================================================
    property var lists: []              // getAllLists().value
    property var listRows: []           // head / item 混合
    property var items: []              // 基础库 + 自定义, 已归一化
    property var itemRows: []           // head / item 混合
    property bool onlyCritical: false
    property string note: ""            // 校验/写操作反馈: 常驻可读, 不闪 toast

    // === 装备条目对话框 (新建 / 修改 / 复制副本 共用一套字段) ===============
    property string dlgMode: "add"      // add | edit | clone
    property string editItemId: ""
    property string dlgCategory: "rescue"
    property bool dlgCritical: false

    readonly property var categoryKeys: ["rescue", "protection", "warmth", "altitude",
                                         "water", "food", "light", "tools", "navigation"]
    readonly property var categoryNames: ["急救救援", "防护", "保暖", "高原",
                                          "饮水", "食物", "照明", "工具", "导航"]
    readonly property var seasonNames: ["春", "夏", "秋", "冬"]

    function categoryLabel(key) {
        var i = categoryKeys.indexOf(key)
        return i >= 0 ? categoryNames[i] : (key && key.length > 0 ? String(key) : "未分类")
    }

    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }
    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }

    function fmtKg(g) {
        if (g <= 0) return "0 kg"
        return (g / 1000).toFixed(2) + " kg"
    }

    readonly property int baseCount: {
        var n = 0
        for (var i = 0; i < items.length; ++i) if (!items[i].isUser) n++
        return n
    }
    readonly property int userCount: items.length - baseCount
    readonly property int criticalCount: {
        var n = 0
        for (var i = 0; i < items.length; ++i) if (items[i].critical) n++
        return n
    }
    readonly property int doneLists: {
        var n = 0
        for (var i = 0; i < lists.length; ++i) if (lists[i].isCompleted === true) n++
        return n
    }
    readonly property int totalGrams: {
        var s = 0
        for (var i = 0; i < lists.length; ++i) s += (Number(lists[i].totalWeightG) || 0)
        return s
    }

    // === 读数行 (每个视图报自己那一档的覆盖面) =============================
    readonly property string statusLine: {
        if (view === 0) {
            if (!equipmentService) return "装备引擎还没就绪 · 检查 ServiceRegistry 是否注册 equipmentService"
            if (items.length === 0) return "装备库空 · 检查 assets/data/equipment_base.json 是否打进包里"
            return altMax + " m · " + days + " 天 · 难度 " + difficulty + " · "
                   + seasonNames[seasonIndex] + " · 库 " + items.length + " 件"
        }
        if (view === 1) {
            if (lists.length === 0) return "还没有生成过清单 · 切到「生成」按行程条件出一份"
            return lists.length + " 份 · 已清点 " + doneLists + " · 合计 " + fmtKg(totalGrams)
        }
        var t = baseCount + " 件基础 · " + userCount + " 件自定义 · 关键 " + criticalCount + " 件"
        return onlyCritical ? t + " · 现只列关键" : t
    }

    readonly property string kicker: view === 0 ? "GEAR / PACK BUILDER"
                                      : (view === 1 ? "GEAR / MY LISTS" : "GEAR / LIBRARY")
    readonly property string pageTitle: view === 0 ? "装备清单"
                                        : (view === 1 ? "我的清单" : "装备库")

    // === 取数 ==============================================================
    function loadLists() {
        if (!equipmentService) { lists = []; listRows = []; return }
        // getAllLists 是 Result 包装 (Phase 5 批次 3), 失败时目录打不开要看得见
        var res = equipmentService.getAllLists()
        var arr = (res && res.ok && res.value && res.value.length !== undefined) ? res.value : []
        if (res && res.ok === false)
            equipmentPage.note = "清单目录读不出来: " + ((res.error && res.error.message) || "未知错误")
        lists = arr
        rebuildLists()
    }

    // 分组轴 = 海拔档 (L0~L6 的名字), 组内按生成时间新→旧.
    // getAllLists 遍历的是存储目录里的 *.json, 顺序跟着文件系统走, 不排就会跳.
    function rebuildLists() {
        var bucket = ({})
        var order = []
        for (var i = 0; i < lists.length; ++i) {
            var l = lists[i]
            var lv = Number(l.altitudeLevel) || 0
            var key = String(lv)
            if (!bucket[key]) {
                bucket[key] = []
                order.push({ lv: lv, label: String(l.altitudeLevelName || "未标注档位") })
            }
            bucket[key].push({
                kind: "item",
                itemId: String(l.id || ""),
                name: String(l.name || "未命名清单"),
                level: lv,
                altMax: Number(l.altitudeMax) || 0,
                grams: Number(l.totalWeightG) || 0,
                checked: Number(l.checkedCount) || 0,
                completed: l.isCompleted === true,
                created: String(l.createdAt || ""),
                label: "", count: 0
            })
        }
        order.sort(function (a, b) { return a.lv - b.lv })
        var out = []
        for (var g = 0; g < order.length; ++g) {
            var members = bucket[String(order[g].lv)]
            members.sort(function (a, b) {
                if (a.created === b.created) return a.name < b.name ? -1 : 1
                return a.created < b.created ? 1 : -1
            })
            // 两类行必须同键: delegate 里的绑定一律会求值 (`visible: false` 不拦绑定),
            // 少一个键真机上就是 "Unable to assign [undefined] to QString/bool/int"。
            out.push({
                kind: "head", label: order[g].label, count: members.length, level: order[g].lv,
                itemId: "", name: "", altMax: 0, grams: 0, checked: 0,
                completed: false, created: ""
            })
            for (var m = 0; m < members.length; ++m) out.push(members[m])
        }
        listRows = out
    }

    function loadItems() {
        if (!equipmentService) { items = []; itemRows = []; return }
        // getAllItems / getUserItems 返回裸 QVariantList (无 Result 包装)
        var base = equipmentService.getAllItems()
        var user = equipmentService.getUserItems()
        var all = []
        var b
        for (b = 0; b < base.length; ++b) all.push(normItem(base[b], false))
        for (b = 0; b < user.length; ++b) all.push(normItem(user[b], true))
        items = all
        rebuildItems()
    }

    function normItem(raw, isUser) {
        return {
            itemId: String(raw.id || ""),
            name: String(raw.name || "未命名装备"),
            category: String(raw.category || ""),
            grams: Number(raw.weightG) || 0,
            critical: raw.isCritical === true,
            isUser: isUser
        }
    }

    // 分组轴 = 类别 (按 equipment_base.json 的 categories 序, 未知类别排最后)
    function rebuildItems() {
        var bucket = ({})
        var order = []
        for (var i = 0; i < items.length; ++i) {
            var it = items[i]
            if (onlyCritical && !it.critical) continue
            var cat = it.category
            if (!bucket[cat]) { bucket[cat] = []; order.push(cat) }
            bucket[cat].push({
                kind: "item",
                itemId: it.itemId,
                name: it.name,
                catKey: cat,
                catLabel: categoryLabel(cat),
                grams: it.grams,
                critical: it.critical,
                isUser: it.isUser,
                plate: CommonOptions.plateCode("GB", it.itemId),
                label: "", count: 0
            })
        }
        order.sort(function (a, b) {
            var ia = categoryKeys.indexOf(a)
            var ib = categoryKeys.indexOf(b)
            if (ia < 0) ia = 999
            if (ib < 0) ib = 999
            return ia - ib
        })
        var out = []
        for (var g = 0; g < order.length; ++g) {
            var members = bucket[order[g]]
            members.sort(function (a, b) {
                if (a.grams !== b.grams) return a.grams - b.grams
                return a.name < b.name ? -1 : 1
            })
            out.push({
                kind: "head", label: categoryLabel(order[g]), count: members.length,
                itemId: "", name: "", catKey: order[g], catLabel: "", grams: 0,
                critical: false, isUser: false, plate: ""
            })
            for (var m = 0; m < members.length; ++m) out.push(members[m])
        }
        itemRows = out
    }

    function refreshAll() {
        loadLists()
        loadItems()
    }

    Component.onCompleted: refreshAll()

    // 写操作 (addUserItem / updateUserItem / deleteUserItem / saveList) 在 C++ 侧
    // 都会发 dataChanged 或 listGenerated → 一律靠信号回表, 不在调用处手动刷,
    // 否则一次点击刷两遍.
    Connections {
        target: equipmentService
        function onDataChanged() { equipmentPage.refreshAll() }
        function onListGenerated(listId) { equipmentPage.loadLists() }
        function onListCompleted(listId) { equipmentPage.loadLists() }
    }
    onOnlyCriticalChanged: rebuildItems()

    // === 生成 ==============================================================
    // 海拔/天数输入直接改写页面状态 (字段 text 不做绑定, 避免与 resetForm 的
    // 一次性赋值互相回写).
    function autoName() {
        if (nameField.text.length === 0) {
            nameField.placeholderText = equipmentPage.altMax > 0
                    ? ("留空自动命名: 海拔" + equipmentPage.altMax + "m·" + equipmentPage.days + "天")
                    : "清单名称 (留空自动命名)"
        }
    }

    function resetForm() {
        altMaxField.text = "1500"
        daysField.text = "2"
        equipmentPage.altMax = 1500
        equipmentPage.days = 2
        equipmentPage.difficulty = 2
        equipmentPage.seasonIndex = 1
        equipmentPage.precipIndex = 0
        equipmentPage.humidityIndex = 1
        equipmentPage.uvLevelIndex = 2
        equipmentPage.windLevelIndex = 1
        equipmentPage.diurnalRange = 10
        equipmentPage.isRainySeason = false
        equipmentPage.isDesert = false
        equipmentPage.isCoastal = false
        nameField.text = ""
        nameField.placeholderText = "清单名称 (留空自动命名)"
        equipmentPage.note = ""
    }

    function generateList() {
        var altMax = equipmentPage.altMax
        var days = equipmentPage.days
        if (altMax <= 0) { equipmentPage.note = "最高海拔要大于 0 米"; return }
        if (days <= 0) { equipmentPage.note = "行程天数要至少 1 天"; return }
        if (!equipmentService) { equipmentPage.note = "装备引擎还没就绪, 重启后再试"; return }

        var listName = nameField.text.trim()
        if (listName.length === 0) listName = "海拔" + altMax + "m·" + days + "天"

        // 风力等级同时反推一个代表风速: 规则里 wind_speed>=8 与 wind_level in
        // [strong,gale] 是两条, 只发等级会漏掉前者.
        var windSpeedByLevel = [0.2, 2.0, 5.0, 9.0, 15.0]
        var params = {
            "altitudeMax": altMax,
            "altitudeMin": Math.max(0, altMax - 500),
            "altitudeCamp": Math.max(0, altMax - 200),
            "days": days,
            "difficulty": equipmentPage.difficulty,
            "season": equipmentPage.seasonIndex,
            "windSpeed": windSpeedByLevel[equipmentPage.windLevelIndex] || 0.0,
            "precipitation": equipmentPage.precipIndex,
            "diurnalRange": equipmentPage.diurnalRange,
            "humidity": equipmentPage.humidityIndex,
            "uvLevel": equipmentPage.uvLevelIndex,
            "windLevel": equipmentPage.windLevelIndex,
            "isRainySeason": equipmentPage.isRainySeason,
            "isDesert": equipmentPage.isDesert,
            "isCoastal": equipmentPage.isCoastal
        }

        var result = equipmentService.generateList(listName, params)
        if (!result || !result.id) {
            equipmentPage.note = "生成没有成功: 规则可能一条没命中, 或清单没能写进存储"
            return
        }
        equipmentPage.note = ""
        navigateTo("EquipmentDetailPage", { listId: String(result.id) })
    }

    // === 条目写操作 ========================================================
    function openItemDialog(mode, seed) {
        var s = seed || ({})
        equipmentPage.dlgMode = mode
        equipmentPage.editItemId = String(s.itemId || "")
        equipmentPage.dlgCategory = s.category ? String(s.category) : "rescue"
        equipmentPage.dlgCritical = s.critical === true
        itemNameText.text = (s.name ? String(s.name) : "") + (mode === "clone" ? " (副本)" : "")
        itemWeightText.text = String(s.grams !== undefined ? s.grams : 100)
        equipmentPage.note = ""
        itemDialog.open()
    }

    function acceptItemDialog() {
        if (!equipmentService) { equipmentPage.note = "装备引擎还没就绪"; return }
        var nm = itemNameText.text.trim()
        if (nm.length === 0) { equipmentPage.note = "装备名称不能为空"; return }
        var g = parseInt(itemWeightText.text) || 0
        var r
        if (equipmentPage.dlgMode === "edit" && equipmentPage.editItemId.length > 0) {
            r = equipmentService.updateUserItem(equipmentPage.editItemId, nm,
                                                equipmentPage.dlgCategory, g,
                                                equipmentPage.dlgCritical)
        } else {
            r = equipmentService.addUserItem(nm, equipmentPage.dlgCategory, g,
                                             equipmentPage.dlgCritical)
        }
        if (r && r.ok === false) {
            equipmentPage.note = ((r.error && r.error.message) || "保存失败")
                    + " · 名称「" + nm + "」没有写进库"
            return
        }
        equipmentPage.note = ""   // 回表由 dataChanged 触发
    }

    function deleteItem(itemId) {
        if (!equipmentService || itemId.length === 0) return
        var r = equipmentService.deleteUserItem(itemId)
        if (r && r.ok === false)
            equipmentPage.note = "删除失败: " + ((r.error && r.error.message) || "未知错误")
    }

    function deleteList(listId, listName) {
        if (!equipmentService || listId.length === 0) return
        var r = equipmentService.deleteList(listId)
        if (r && r.ok === false)
            equipmentPage.note = "删除清单失败: " + ((r.error && r.error.message) || "未知错误")
    }

    function renameList(listId, newName) {
        if (!equipmentService || listId.length === 0 || newName.length === 0) return
        var old = equipmentService.getList(listId)
        if (!old || !old.id) { equipmentPage.note = "这份清单读不到了, 可能已被删除"; return }
        old.name = newName
        var r = equipmentService.modifyList(listId, old)
        if (r && r.ok === false)
            equipmentPage.note = "重命名失败: " + ((r.error && r.error.message) || "未知错误")
    }

    // 行内动作方块: 32px 面 + 外扩 6px 热区 = 44px (touchMin).
    // 内联组件看不到外层 styles id, 自带一个 (与 Chip.qml 同构).
    component ActionCell: Rectangle {
        id: cell
        property string iconName: ""
        property color tone: CommonOptions.colorText
        signal clicked()

        Styles { id: cellStyles; visible: false }

        implicitWidth: 32
        implicitHeight: 32
        radius: cellStyles.rSm
        color: CommonOptions.colorSurface
        border.color: CommonOptions.colorRule
        border.width: cellStyles.lineHair

        IconLabel {
            anchors.centerIn: parent
            name: cell.iconName
            size: cellStyles.icSm
            tintColor: cell.tone
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            enabled: cell.enabled
            cursorShape: cell.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: cell.clicked()
        }
    }

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- 标题条 (54px: 微标签 / 视图名 / 读数行, 右上 26px 方角返回) ---
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
                    text: equipmentPage.kicker
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    font.letterSpacing: 1.8
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: equipmentPage.pageTitle
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: equipmentPage.statusLine
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
                    onClicked: equipmentPage.goBack()
                }
            }
        }

        // --- 视图切换 (三枚 chip 一行, 带条数) ---
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            spacing: styles.spXs

            Repeater {
                model: ["生成", "我的清单 " + equipmentPage.lists.length,
                        "装备库 " + equipmentPage.items.length]
                delegate: Chip {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData
                    checked: index === equipmentPage.view
                    accent: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: equipmentPage.view = index
                }
            }
        }

        // --- 反馈行: 校验/写操作失败常驻在这里, 视图间不丢 ---
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spXs
            visible: equipmentPage.note.length > 0
            text: equipmentPage.note
            font.pixelSize: styles.fsXs
            color: CommonOptions.colorLegendAmber
            wrapMode: Text.WordWrap
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: equipmentPage.view

            // ============================================================
            // 视图 0: 生成器
            // ============================================================
            ScrollView {
                contentWidth: width
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: styles.pageGap

                    // --- 行程卡 ---
                    Card {
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        Layout.topMargin: styles.spSm
                        spacing: styles.spSm

                        SectionTitle {
                            Layout.fillWidth: true
                            icon: "note_add"
                            text: "行程条件"
                            pixelSize: styles.fsLg
                        }

                        TextField {
                            id: nameField
                            Layout.fillWidth: true
                            Layout.preferredHeight: styles.fieldH
                            placeholderText: "清单名称 (留空自动命名)"
                            placeholderTextColor: CommonOptions.colorTextDim
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsMd
                            leftPadding: styles.spSm
                            rightPadding: styles.spSm
                            topPadding: 0
                            bottomPadding: 0
                            background: Rectangle {
                                color: nameField.activeFocus
                                       ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                                border.color: nameField.activeFocus
                                              ? CommonOptions.colorText : CommonOptions.colorRule
                                border.width: styles.lineHair
                                radius: styles.rSm
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spSm

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: "最高海拔 (m)"
                                    color: CommonOptions.colorInk3
                                    font.pixelSize: styles.fsXs
                                }
                                TextField {
                                    id: altMaxField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: styles.btnH
                                    text: "1500"
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    color: CommonOptions.colorText
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsMd
                                    leftPadding: styles.spSm
                                    rightPadding: styles.spSm
                                    topPadding: 0
                                    bottomPadding: 0
                                    onTextChanged: {
                                        equipmentPage.altMax = parseInt(text) || 0
                                        equipmentPage.autoName()
                                    }
                                    background: Rectangle {
                                        color: altMaxField.activeFocus
                                               ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                                        border.color: altMaxField.activeFocus
                                                      ? CommonOptions.colorText : CommonOptions.colorRule
                                        border.width: styles.lineHair
                                        radius: styles.rSm
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: "行程天数"
                                    color: CommonOptions.colorInk3
                                    font.pixelSize: styles.fsXs
                                }
                                TextField {
                                    id: daysField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: styles.btnH
                                    text: "2"
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    color: CommonOptions.colorText
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsMd
                                    leftPadding: styles.spSm
                                    rightPadding: styles.spSm
                                    topPadding: 0
                                    bottomPadding: 0
                                    onTextChanged: {
                                        equipmentPage.days = parseInt(text) || 0
                                        equipmentPage.autoName()
                                    }
                                    background: Rectangle {
                                        color: daysField.activeFocus
                                               ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                                        border.color: daysField.activeFocus
                                                      ? CommonOptions.colorText : CommonOptions.colorRule
                                        border.width: styles.lineHair
                                        radius: styles.rSm
                                    }
                                }
                            }
                        }

                        // 难度: 单选 chip, 选中那枚染难度色 (与路线目录的 3px 条同源)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "难度"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: [1, 2, 3, 4, 5]
                                delegate: Chip {
                                    required property int modelData
                                    Layout.fillWidth: true
                                    text: modelData + " 星"
                                    checked: equipmentPage.difficulty === modelData
                                    accent: CommonOptions.difficultyColor(modelData)
                                    textSize: styles.fsXs
                                    onClicked: equipmentPage.difficulty = modelData
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: CommonOptions.difficultyLabel(equipmentPage.difficulty)
                                  + " · 规则按「该星及以上」触发 (4 星与 5 星各一条附加)"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                            wrapMode: Text.WordWrap
                        }
                    }

                    // --- 环境卡 ---
                    Card {
                        Layout.fillWidth: true
                        Layout.leftMargin: styles.pageMargin
                        Layout.rightMargin: styles.pageMargin
                        spacing: styles.spSm

                        SectionTitle {
                            Layout.fillWidth: true
                            icon: "equalizer"
                            text: "环境条件"
                            pixelSize: styles.fsLg
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "季节"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: ["春", "夏", "秋", "冬"]
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: equipmentPage.seasonIndex === index
                                    accent: CommonOptions.colorAccent
                                    textSize: styles.fsSm
                                    onClicked: equipmentPage.seasonIndex = index
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "降水"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: ["无", "小雨", "中雨", "大雨", "暴雨"]
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: equipmentPage.precipIndex === index
                                    accent: CommonOptions.colorWater
                                    textSize: styles.fsXs
                                    onClicked: equipmentPage.precipIndex = index
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "湿度"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: ["干燥", "适中", "闷热"]
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: equipmentPage.humidityIndex === index
                                    accent: CommonOptions.colorWater
                                    textSize: styles.fsSm
                                    onClicked: equipmentPage.humidityIndex = index
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "紫外线"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: ["弱", "中等", "强", "很强", "极强"]
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: equipmentPage.uvLevelIndex === index
                                    accent: CommonOptions.colorLegendAmber
                                    textSize: styles.fsXs
                                    onClicked: equipmentPage.uvLevelIndex = index
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "风力"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: ["静风", "微风", "中等", "大风", "强风"]
                                delegate: Chip {
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    checked: equipmentPage.windLevelIndex === index
                                    accent: CommonOptions.colorWater
                                    textSize: styles.fsXs
                                    onClicked: equipmentPage.windLevelIndex = index
                                }
                            }
                        }

                        FilterRow {
                            Layout.fillWidth: true
                            label: "温差"
                            labelWidth: 56
                            stepperValue: equipmentPage.diurnalRange + " °C"
                            stepperMinusEnabled: equipmentPage.diurnalRange > 0
                            stepperPlusEnabled: equipmentPage.diurnalRange < 40
                            onStepperMinus: equipmentPage.diurnalRange =
                                            Math.max(0, equipmentPage.diurnalRange - 5)
                            onStepperPlus: equipmentPage.diurnalRange =
                                           Math.min(40, equipmentPage.diurnalRange + 5)
                        }

                        // 地区标记: 多选 chip (雨季/沙漠/沿海)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs
                            Text {
                                Layout.preferredWidth: 56
                                text: "地区"
                                color: CommonOptions.colorInk3
                                font.pixelSize: styles.fsXs
                            }
                            Repeater {
                                model: [["雨季", "isRainySeason"], ["沙漠", "isDesert"], ["沿海", "isCoastal"]]
                                delegate: Chip {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData[0]
                                    checked: equipmentPage[modelData[1]] === true
                                    accent: CommonOptions.colorBlaze
                                    textSize: styles.fsSm
                                    onClicked: equipmentPage[modelData[1]] =
                                               !equipmentPage[modelData[1]]
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "海拔 2500 m 以上自动按高原处理 · 温度与人数不参与选装"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                            wrapMode: Text.WordWrap
                        }
                    }

                    Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spSm }
                }
            }

            // ============================================================
            // 视图 1: 我的清单
            // ============================================================
            Item {
                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.leftMargin: styles.pageMargin
                    anchors.rightMargin: styles.pageMargin
                    anchors.topMargin: styles.spSm
                    anchors.bottomMargin: styles.spSm
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: equipmentPage.listRows

                    // 行 = MouseArea 在前 (垫底), 内容行在后: 行内动作块才不会被子项挡住,
                    // 空白处仍然整行可点.
                    delegate: Item {
                        required property var modelData
                        width: listView.width
                        height: modelData.kind === "head" ? 30 : styles.rowHTall

                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.kind === "item"
                            cursorShape: Qt.PointingHandCursor
                            onClicked: equipmentPage.navigateTo(
                                       "EquipmentDetailPage", { listId: modelData.itemId })
                        }

                        // 分组标题 (海拔档)
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
                                color: CommonOptions.altitudeColor(modelData.level)
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsLg
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.count + " LISTS"
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsXs
                                font.letterSpacing: 1.4
                                color: CommonOptions.colorInk3
                            }
                        }

                        // 清单行
                        RowLayout {
                            anchors.fill: parent
                            anchors.rightMargin: styles.spXs
                            spacing: styles.spSm
                            visible: modelData.kind === "item"

                            Rectangle {
                                Layout.fillHeight: true
                                Layout.preferredWidth: styles.lineAccent
                                color: CommonOptions.altitudeColor(modelData.level)
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
                                    text: "最高 " + modelData.altMax + " m · 已勾 "
                                          + modelData.checked
                                          + (modelData.completed ? " · 已清点" : "")
                                    color: CommonOptions.colorInk3
                                    font.pixelSize: styles.fsXs
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: equipmentPage.fmtKg(modelData.grams)
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                            ActionCell {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: "edit"
                                tone: CommonOptions.colorText
                                onClicked: {
                                    renameDialog.listId = modelData.itemId
                                    renameDialog.listName = modelData.name
                                    itemRenameField.text = modelData.name
                                    renameDialog.open()
                                }
                            }
                            ActionCell {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: "check"
                                tone: CommonOptions.colorForest
                                onClicked: equipmentPage.navigateTo(
                                           "ChecklistPage", { listId: modelData.itemId })
                            }
                            ActionCell {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: "delete"
                                tone: CommonOptions.colorDanger
                                onClicked: {
                                    confirmDeleteDialog.listId = modelData.itemId
                                    confirmDeleteDialog.listName = modelData.name
                                    confirmDeleteDialog.open()
                                }
                            }
                        }

                        Rectangle {
                            visible: modelData.kind === "item"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: styles.lineHair
                            color: CommonOptions.colorRuleSoft
                        }
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: equipmentPage.listRows.length === 0
                    iconName: "backpack"
                    text: "还没有生成过清单"
                    hint: "切到「生成」填最高海拔与天数, 生成的清单会写进应用私有目录"
                    actionText: "去生成"
                    onActionTriggered: {
                        equipmentPage.view = 0
                        equipmentPage.loadLists()
                    }
                }
            }

            // ============================================================
            // 视图 2: 装备库
            // ============================================================
            Item {
                ListView {
                    id: itemsView
                    anchors.fill: parent
                    anchors.leftMargin: styles.pageMargin
                    anchors.rightMargin: styles.pageMargin
                    anchors.topMargin: styles.spSm
                    anchors.bottomMargin: styles.spSm
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: equipmentPage.itemRows

                    delegate: Item {
                        required property var modelData
                        width: itemsView.width
                        height: modelData.kind === "head" ? 30 : styles.rowHTall

                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.kind === "item"
                            cursorShape: Qt.PointingHandCursor
                            // 点行 = 编辑: 自定义条目直接改, 基础条目走"复制为自定义副本"
                            // (基础库写回 QSettings 没有意义, C++ 侧也没有 updateUserItem 的分支)
                            onClicked: equipmentPage.openItemDialog(
                                       modelData.isUser ? "edit" : "clone", modelData)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.rightMargin: styles.spXs
                            spacing: styles.spSm
                            visible: modelData.kind === "head"

                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsLg
                                font.bold: true
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

                        RowLayout {
                            anchors.fill: parent
                            anchors.rightMargin: styles.spXs
                            spacing: 9
                            visible: modelData.kind === "item"

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
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.catLabel + (modelData.isUser ? " · 自定义" : "")
                                              + (modelData.grams <= 0 ? " · 无重量" : "")
                                        color: CommonOptions.colorInk3
                                        font.pixelSize: styles.fsXs
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            // "关键"是这一列唯一的信号 (5/43 件), 用琥珀文字而不是色条:
                            // 色条在本页已经有海拔含义 (视图 1), 不能借来当第二套语义.
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                visible: modelData.critical
                                text: "关键"
                                color: CommonOptions.colorLegendAmber
                                font.pixelSize: styles.fsXs
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.grams + " g"
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorInk3
                            }
                            ActionCell {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                iconName: modelData.isUser ? "edit" : "add"
                                tone: modelData.isUser ? CommonOptions.colorText
                                                       : CommonOptions.colorInk3
                                onClicked: equipmentPage.openItemDialog(
                                           modelData.isUser ? "edit" : "clone", modelData)
                            }
                            // 规则 ④: 基础库条目不可删 → 不给禁用态的假按钮
                            ActionCell {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                visible: modelData.isUser
                                iconName: "delete"
                                tone: CommonOptions.colorDanger
                                onClicked: equipmentPage.deleteItem(modelData.itemId)
                            }
                        }

                        Rectangle {
                            visible: modelData.kind === "item"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: styles.lineHair
                            color: CommonOptions.colorRuleSoft
                        }
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: equipmentPage.itemRows.length === 0
                    iconName: "store"
                    text: equipmentPage.items.length === 0 ? "装备库是空的" : "没有关键装备"
                    hint: equipmentPage.items.length === 0
                          ? "检查 assets/data/equipment_base.json 是否打进包里"
                          : "关掉「只列关键」就能看到全部类别"
                    actionText: equipmentPage.items.length === 0 ? "重新载入" : "看全部"
                    onActionTriggered: {
                        if (equipmentPage.items.length === 0) equipmentPage.loadItems()
                        else equipmentPage.onlyCritical = false
                    }
                }
            }
        }

        // --- 底栏 (主操作常驻, 不随表单内部滚动丢失) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: barRow.implicitHeight + 2 * styles.spSm
            // 视图 1 没有整页级动作 (清单的行内动作齐了), 不摆空按钮
            visible: equipmentPage.view !== 1
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
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                spacing: styles.spMd

                OutlineButton {
                    Layout.preferredWidth: 96
                    Layout.alignment: Qt.AlignVCenter
                    text: equipmentPage.view === 0
                          ? "重置"
                          : (equipmentPage.onlyCritical ? "看全部 " + equipmentPage.items.length
                                                        : "只列关键 " + equipmentPage.criticalCount)
                    tone: CommonOptions.colorText
                    textSize: styles.fsSm
                    onClicked: {
                        if (equipmentPage.view === 0) equipmentPage.resetForm()
                        else equipmentPage.onlyCritical = !equipmentPage.onlyCritical
                    }
                }
                PrimaryButton {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: equipmentPage.view === 0 ? "生成装备清单" : "新建装备"
                    iconName: equipmentPage.view === 0 ? "backpack" : "add"
                    tone: CommonOptions.colorAccent
                    textSize: styles.fsLg
                    onClicked: {
                        if (equipmentPage.view === 0) equipmentPage.generateList()
                        else equipmentPage.openItemDialog("add", ({ grams: 100 }))
                    }
                }
            }
        }
    }

    // === 对话框 ============================================================
    // 装备条目: 新建 / 修改 / 复制副本 共用一套字段 (dlgMode 决定写哪个口子).
    // 不用 standardButtons —— Material 的 OK/Cancel/Yes/No 在中文包里没有译文,
    // 弹出来是英文 (#41); 这里自定义 footer, 按钮文案自己写.
    Dialog {
        id: itemDialog
        modal: true
        anchors.centerIn: parent
        width: Math.min(420, equipmentPage.width - 2 * styles.pageMargin)
        padding: styles.spMd
        // Dialog 的底色走 Material 附加属性 (与 Main.qml searchDialog 同一条路);
        // 直接写 color: 会被 qmllint 判成 Dialog 上没有的属性.
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText

        property string dlgTitle: equipmentPage.dlgMode === "edit" ? "修改装备"
                                : (equipmentPage.dlgMode === "clone" ? "复制为自定义装备" : "新建装备")

        contentItem: ColumnLayout {
            spacing: styles.spSm

            Text {
                Layout.fillWidth: true
                text: itemDialog.dlgTitle
                color: CommonOptions.colorText
                font.pixelSize: styles.fsLg
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: equipmentPage.dlgMode === "clone"
                text: "基础库条目改不动, 复制一份改名或改重量就是你的自定义装备"
                color: CommonOptions.colorInk3
                font.pixelSize: styles.fsXs
                wrapMode: Text.WordWrap
            }
            TextField {
                id: itemNameText
                Layout.fillWidth: true
                Layout.preferredHeight: styles.btnH
                placeholderText: "装备名称"
                placeholderTextColor: CommonOptions.colorTextDim
                color: CommonOptions.colorText
                font.pixelSize: styles.fsMd
                leftPadding: styles.spSm
                rightPadding: styles.spSm
                topPadding: 0
                bottomPadding: 0
                background: Rectangle {
                    color: itemNameText.activeFocus
                           ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                    border.color: itemNameText.activeFocus
                                  ? CommonOptions.colorText : CommonOptions.colorRule
                    border.width: styles.lineHair
                    radius: styles.rSm
                }
            }

            // 类别: 9 枚文字 chip 分两行 (Material 的 ComboBox 弹出层要另管字体,
            // 且 9 类是本库的固定枚举, 摊开比下拉少一次点击)
            Text {
                text: "类别"
                color: CommonOptions.colorInk3
                font.pixelSize: styles.fsXs
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 5
                columnSpacing: styles.spXs
                rowSpacing: styles.spXs

                Repeater {
                    model: equipmentPage.categoryKeys
                    delegate: Chip {
                        required property var modelData
                        Layout.fillWidth: true
                        text: equipmentPage.categoryLabel(modelData)
                        checked: equipmentPage.dlgCategory === modelData
                        accent: CommonOptions.colorAccent
                        textSize: styles.fsXs
                        onClicked: equipmentPage.dlgCategory = String(modelData)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: styles.spSm
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "重量 (g)"
                        color: CommonOptions.colorInk3
                        font.pixelSize: styles.fsXs
                    }
                    TextField {
                        id: itemWeightText
                        Layout.fillWidth: true
                        Layout.preferredHeight: styles.btnH
                        inputMethodHints: Qt.ImhDigitsOnly
                        color: CommonOptions.colorText
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsMd
                        leftPadding: styles.spSm
                        rightPadding: styles.spSm
                        topPadding: 0
                        bottomPadding: 0
                        background: Rectangle {
                            color: itemWeightText.activeFocus
                                   ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                            border.color: itemWeightText.activeFocus
                                          ? CommonOptions.colorText : CommonOptions.colorRule
                            border.width: styles.lineHair
                            radius: styles.rSm
                        }
                    }
                }
                Chip {
                    Layout.alignment: Qt.AlignBottom
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: styles.chipH
                    text: "关键装备"
                    checked: equipmentPage.dlgCritical
                    accent: CommonOptions.colorLegendAmber
                    textSize: styles.fsXs
                    onClicked: equipmentPage.dlgCritical = !equipmentPage.dlgCritical
                }
            }
        }

        footer: RowLayout {
            // footer 由 Popup 按 Dialog.padding 内缩, 这里再写 Layout.* 边距是空操作
            spacing: styles.spMd

            OutlineButton {
                Layout.preferredWidth: 88
                Layout.alignment: Qt.AlignVCenter
                text: "取消"
                tone: CommonOptions.colorText
                textSize: styles.fsSm
                onClicked: itemDialog.reject()
            }
            PrimaryButton {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: equipmentPage.dlgMode === "edit" ? "保存修改" : "存为我的装备"
                tone: CommonOptions.colorAccent
                textSize: styles.fsMd
                onClicked: {
                    equipmentPage.acceptItemDialog()
                    // 校验/写入失败时 note 会留在页面上, 对话框不关, 用户能接着改
                    if (equipmentPage.note.length === 0) itemDialog.accept()
                }
            }
        }
    }

    Dialog {
        id: renameDialog
        property string listId: ""
        property string listName: ""

        modal: true
        anchors.centerIn: parent
        width: Math.min(420, equipmentPage.width - 2 * styles.pageMargin)
        padding: styles.spMd
        // Dialog 的底色走 Material 附加属性 (与 Main.qml searchDialog 同一条路);
        // 直接写 color: 会被 qmllint 判成 Dialog 上没有的属性.
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText

        contentItem: ColumnLayout {
            spacing: styles.spSm

            Text {
                Layout.fillWidth: true
                text: "重命名清单"
                color: CommonOptions.colorText
                font.pixelSize: styles.fsLg
                font.bold: true
                elide: Text.ElideRight
            }
            TextField {
                id: itemRenameField
                Layout.fillWidth: true
                Layout.preferredHeight: styles.btnH
                placeholderText: "新名称"
                placeholderTextColor: CommonOptions.colorTextDim
                color: CommonOptions.colorText
                font.pixelSize: styles.fsMd
                leftPadding: styles.spSm
                rightPadding: styles.spSm
                topPadding: 0
                bottomPadding: 0
                background: Rectangle {
                    color: itemRenameField.activeFocus
                           ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                    border.color: itemRenameField.activeFocus
                                  ? CommonOptions.colorText : CommonOptions.colorRule
                    border.width: styles.lineHair
                    radius: styles.rSm
                }
            }
        }

        footer: RowLayout {
            // footer 由 Popup 按 Dialog.padding 内缩, 这里再写 Layout.* 边距是空操作
            spacing: styles.spMd

            OutlineButton {
                Layout.preferredWidth: 88
                Layout.alignment: Qt.AlignVCenter
                text: "取消"
                tone: CommonOptions.colorText
                textSize: styles.fsSm
                onClicked: renameDialog.reject()
            }
            PrimaryButton {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: "改名"
                tone: CommonOptions.colorAccent
                textSize: styles.fsMd
                onClicked: {
                    var nm = itemRenameField.text.trim()
                    if (nm.length === 0) {
                        equipmentPage.note = "名称不能为空, 清单还是原来那个"
                        return
                    }
                    equipmentPage.renameList(renameDialog.listId, nm)
                    if (equipmentPage.note.length === 0) renameDialog.accept()
                }
            }
        }
    }

    Dialog {
        id: confirmDeleteDialog
        property string listId: ""
        property string listName: ""

        modal: true
        anchors.centerIn: parent
        width: Math.min(420, equipmentPage.width - 2 * styles.pageMargin)
        padding: styles.spMd
        // Dialog 的底色走 Material 附加属性 (与 Main.qml searchDialog 同一条路);
        // 直接写 color: 会被 qmllint 判成 Dialog 上没有的属性.
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText

        contentItem: ColumnLayout {
            spacing: styles.spSm

            Text {
                Layout.fillWidth: true
                text: "删除清单"
                color: CommonOptions.colorDanger
                font.pixelSize: styles.fsLg
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: "要删掉「" + confirmDeleteDialog.listName
                      + "」吗? 这条记录连同勾选状态一起从存储目录移除, 删了找不回。"
                color: CommonOptions.colorText
                font.pixelSize: styles.fsMd
                wrapMode: Text.WordWrap
            }
        }

        footer: RowLayout {
            // footer 由 Popup 按 Dialog.padding 内缩, 这里再写 Layout.* 边距是空操作
            spacing: styles.spMd

            OutlineButton {
                Layout.preferredWidth: 88
                Layout.alignment: Qt.AlignVCenter
                text: "留着"
                tone: CommonOptions.colorText
                textSize: styles.fsSm
                onClicked: confirmDeleteDialog.reject()
            }
            PrimaryButton {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: "删除"
                iconName: "delete"
                tone: CommonOptions.colorDanger
                textSize: styles.fsMd
                onClicked: {
                    equipmentPage.deleteList(confirmDeleteDialog.listId,
                                             confirmDeleteDialog.listName)
                    if (equipmentPage.note.length === 0) confirmDeleteDialog.accept()
                }
            }
        }
    }
}
