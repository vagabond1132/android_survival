/**
 * @file EquipmentPage.qml
 * @brief 装备推荐 + 强装检查 (2026-09-14 UI 改版)
 *
 * 改进:
 *   - 顶部 hero 渐变 (橙色背包主题)
 *   - 颜色 token 全部直接走 CommonOptions
 *   - 卡片化, 圆角统一
 *   - 删掉本地的 colorXxx 副本
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: equipmentPage
    title: "装备推荐"

    property int currentTab: 0
    property string currentListId: ""
    property int difficulty: 2  // 1-5

    // 2026-09-23: 环境维度 (之前表单只有海拔/天数/难度, 但 equipment_rules.json 有
    //   19 条规则依赖季节/降水/湿度/UV/风级/昼夜温差/地区标记. 没有输入 → C++ 端只能
    //   用默认值 → 这些规则恒定不触发. 补齐输入控件让规则可被用户影响.)
    property int seasonIndex: 1          // 0春 1夏 2秋 3冬
    property int precipIndex: 0          // 0无 1小 2中 3大 4暴
    property int humidityIndex: 1        // 0干 1中 2湿
    property int uvLevelIndex: 2         // 0弱 1中 2强 3很强 4极强
    property int windLevelIndex: 1       // 0静 1微 2中 3大 4强
    property int diurnalRange: 10        // 昼夜温差 °C
    property bool isRainySeason: false
    property bool isDesert: false
    property bool isCoastal: false
    // 2026-09-30: 环境条件区默认展开 (之前折叠), 环境字段由下拉改为分段单选 chip.
    property bool envExpanded: true

    // 2026-09-19: 接受外部预填参数 (从 RouteDetailPage 跳来时用)
    property int presetAltitude: -1
    property int presetDays: -1
    property int presetDifficulty: -1
    property string presetName: ""

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    // 2026-09-19: 收到 preset 参数时填进表单 (从路线跳转场景).
    //   不能在 onPresetXxxChanged 里直接写 altMaxField.text — Component.onCompleted
    //   之前子 Item 还没实例化, field 是 undefined. 统一在 onCompleted 里读 props.
    Component.onCompleted: {
        if (presetAltitude > 0) altMaxField.text = String(presetAltitude)
        if (presetDays > 0) daysField.text = String(presetDays)
        if (presetDifficulty > 0) equipmentPage.difficulty = presetDifficulty
        if (presetName.length > 0) nameField.text = presetName
    }

    component StarRow: Row {
        spacing: 2
        property int level: 0
        Repeater {
            model: 5
            delegate: Text {
                text: index < parent.level ? "★" : "☆"
                color: index < parent.level ? CommonOptions.colorWarn : CommonOptions.colorTextMuted
                font.pixelSize: 18
            }
        }
    }

    // 2026-09-30: 环境条件分段单选 chip (替代原下拉). 点选即赋值, 无"选中态"未选
    //   的歧义 → 达到"强制选择"效果; 当前项高亮, 用户可见已选值.
    //   options: 字符串数组; picked(index): 回调; 空串选项渲染为"无"并置灰边.
    component EnvChipRow: RowLayout {
        id: chipRow
        property string label: ""
        property var options: []
        property int selected: 0
        // 内联组件不引用外层 styles id, 用本地字号 (与 styles.fsXs / fsSm 同值)
        readonly property int _fsLabel: 10
        readonly property int _fsChip: 12
        signal picked(int index)

        spacing: 6

        Text {
            Layout.preferredWidth: 84
            text: chipRow.label
            color: CommonOptions.colorTextMuted
            font.pixelSize: chipRow._fsLabel
        }
        Repeater {
            model: chipRow.options
            delegate: Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: 8
                readonly property bool _isSel: index === chipRow.selected
                readonly property bool _isNone: modelData === ""
                color: _isSel ? CommonOptions.colorAccent
                              : (_isNone ? Qt.darker(CommonOptions.colorSurface, 1.12)
                                         : CommonOptions.colorSurface)
                border.color: _isSel ? CommonOptions.colorAccent
                                     : (_isNone ? Qt.darker(CommonOptions.colorSurface, 1.25)
                                                : Qt.darker(CommonOptions.colorSurface, 1.2))
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: parent._isNone ? "无" : modelData
                    color: parent._isSel ? "white"
                                         : (parent._isNone ? CommonOptions.colorTextMuted
                                                           : CommonOptions.colorText)
                    font.pixelSize: chipRow._fsChip
                    font.bold: parent._isSel
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chipRow.picked(index)
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // === 顶部 hero (统一深青绿) ===
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            color: "#00695C"  // 深青绿
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00695C" }
                GradientStop { position: 1.0; color: "#00897B" }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: styles.spLg
                spacing: styles.spMd

                Text { text: "\ue53f"; font.family: "Material Icons"; font.pixelSize: 32 }  // backpack
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "装备清单"
                        color: "white"
                        font.pixelSize: styles.fs2xl
                        font.bold: true
                    }
                    Text {
                        text: "智能生成 + 强装检查 + 重量统计"
                        color: "#FFE0B2"
                        font.pixelSize: styles.fsSm
                    }
                }
            }
        }

        // === 输入区 (卡片, 可滚动) ===
        // 2026-09-24: 修 - 展开"环境条件"后输入卡片暴涨到远超屏幕高, 把下方
        //   TabBar + StackLayout (我的清单/装备库) 整个挤出屏幕, 且原 ColumnLayout
        //   不可滚动 → 用户无法上滑看到清单/装备库. 改为 Flickable 包裹, 并给
        //   Layout.maximumHeight 限高 (屏高 55%), 超出部分卡片内部滚动.
        Flickable {
            id: inputFlick
            Layout.fillWidth: true
            Layout.margins: styles.spLg
            Layout.topMargin: styles.spLg
            Layout.preferredHeight: inputCol.implicitHeight + 24
            Layout.maximumHeight: Math.max(180, equipmentPage.height * 0.55)
            contentWidth: width
            contentHeight: inputCol.implicitHeight + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { active: true }

            Rectangle {
                width: inputFlick.width
                height: Math.max(inputFlick.height, inputCol.implicitHeight + 24)
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.2)
                border.width: 1
                clip: false

                ColumnLayout {
                    id: inputCol
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: styles.spSm

                // 2026-09-19: 标题行 + 重置按钮, 一行搞定
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "\ue53f 创建装备清单"  // Material Icons: backpack
                        font.family: "Material Icons"
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsLg
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Button {
                        text: "重置"
                        flat: true
                        Material.foreground: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                        onClicked: resetForm()
                    }
                }

                // 名称 - 占位代替 label, 更紧凑
                TextField {
                    id: nameField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    color: CommonOptions.colorText
                    placeholderText: "清单名称 (留空自动命名)"
                    placeholderTextColor: CommonOptions.colorTextMuted
                    font.pixelSize: styles.fsMd
                }

                // 海拔 + 天数 - 内嵌 label (inline), 不再 stack
                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: "最高海拔(m)"; color: CommonOptions.colorTextMuted; font.pixelSize: styles.fsXs }
                        TextField {
                            id: altMaxField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            text: "1500"
                            inputMethodHints: Qt.ImhDigitsOnly
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsMd
                            onTextChanged: autoUpdateName()
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: "行程天数"; color: CommonOptions.colorTextMuted; font.pixelSize: styles.fsXs }
                        TextField {
                            id: daysField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            text: "2"
                            inputMethodHints: Qt.ImhDigitsOnly
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsMd
                            onTextChanged: autoUpdateName()
                        }
                    }
                }

                // 难度 - 一行内 star + 标签
                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Text {
                        text: "难度"
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsXs
                        Layout.preferredWidth: 32
                    }
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            width: 28
                            height: 28
                            color: "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: index < equipmentPage.difficulty ? "★" : "☆"
                                color: index < equipmentPage.difficulty
                                       ? CommonOptions.colorWarn
                                       : CommonOptions.colorTextMuted
                                font.pixelSize: 20
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: equipmentPage.difficulty = index + 1
                            }
                        }
                    }
                    Text {
                        text: CommonOptions.difficultyLabel(equipmentPage.difficulty)
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsXs
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // 2026-09-23: 环境维度 - 供季节/降水/湿度/UV/风级/昼夜温差/地区标记
                //   类规则使用.
                // 2026-09-30: 默认展开 + 环境字段由下拉改分段单选 chip (强制选择).
                //   Flickable (上方) 已限高 + 内部滚动, 展开后不挤占 TabBar/列表.
                Rectangle {
                    Layout.fillWidth: true
                    // envCol 常驻可见(含标题行); 折叠态下 Layout 会忽略 invisible 的
                    // 子项, implicitHeight 自然收缩到只剩标题行高。
                    Layout.preferredHeight: envCol.implicitHeight + 16
                    color: Qt.darker(CommonOptions.colorSurface, 1.1)
                    radius: styles.rMd
                    clip: true

                    ColumnLayout {
                        id: envCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: styles.spSm
                        spacing: styles.spSm

                        // 折叠标题行 (MouseArea 只覆盖这一行, 不能盖住下面 chip 行)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            color: "transparent"
                            Text {
                                id: envTitle
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\ue8b6 环境条件 (影响季节/天气类推荐)"
                                font.family: "Material Icons"
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsSm
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: equipmentPage.envExpanded ? "\ue316" : "\ue313"
                                font.family: "Material Icons"
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: 20
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: equipmentPage.envExpanded = !equipmentPage.envExpanded
                            }
                        }

                        // 季节 (分段单选)
                        EnvChipRow {
                            Layout.fillWidth: true
                            visible: equipmentPage.envExpanded
                            label: "季节"
                            options: ["春", "夏", "秋", "冬"]
                            selected: equipmentPage.seasonIndex
                            onPicked: (i) => equipmentPage.seasonIndex = i
                        }
                        // 降水 (分段单选)
                        EnvChipRow {
                            Layout.fillWidth: true
                            visible: equipmentPage.envExpanded
                            label: "降水"
                            options: ["", "小雨", "中雨", "大雨", "暴雨"]
                            selected: equipmentPage.precipIndex
                            onPicked: (i) => equipmentPage.precipIndex = i
                        }

                        // 湿度 (分段单选)
                        EnvChipRow {
                            Layout.fillWidth: true
                            visible: equipmentPage.envExpanded
                            label: "湿度"
                            options: ["干燥", "适中", "闷热"]
                            selected: equipmentPage.humidityIndex
                            onPicked: (i) => equipmentPage.humidityIndex = i
                        }
                        // 紫外线 (分段单选)
                        EnvChipRow {
                            Layout.fillWidth: true
                            visible: equipmentPage.envExpanded
                            label: "紫外线"
                            options: ["弱", "中等", "强", "很强", "极强"]
                            selected: equipmentPage.uvLevelIndex
                            onPicked: (i) => equipmentPage.uvLevelIndex = i
                        }

                        // 风力 (分段单选)
                        EnvChipRow {
                            Layout.fillWidth: true
                            visible: equipmentPage.envExpanded
                            label: "风力"
                            options: ["静风", "微风", "中等", "大风", "强风"]
                            selected: equipmentPage.windLevelIndex
                            onPicked: (i) => equipmentPage.windLevelIndex = i
                        }
                        // 昼夜温差 (数值输入)
                        RowLayout {
                            Layout.fillWidth: true
                            visible: equipmentPage.envExpanded
                            spacing: styles.spSm
                            Text {
                                Layout.preferredWidth: 84
                                text: "昼夜温差(°C)"
                                color: CommonOptions.colorTextMuted
                                font.pixelSize: styles.fsXs
                            }
                            TextField {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                text: String(equipmentPage.diurnalRange)
                                inputMethodHints: Qt.ImhDigitsOnly
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsSm
                                onTextChanged: equipmentPage.diurnalRange = parseInt(text) || 0
                            }
                        }

                        // 地区标记 (雨季/沙漠/沿海) - 高原由海拔自动推断, 不做输入
                        RowLayout {
                            Layout.fillWidth: true
                            visible: equipmentPage.envExpanded
                            spacing: styles.spXs
                            Repeater {
                                model: [
                                    { key: "isRainySeason", label: "雨季" },
                                    { key: "isDesert",      label: "沙漠" },
                                    { key: "isCoastal",     label: "沿海" }
                                ]
                                delegate: CheckBox {
                                    text: modelData.label
                                    checked: equipmentPage[modelData.key]
                                    font.pixelSize: styles.fsSm
                                    onToggled: equipmentPage[modelData.key] = checked
                                }
                            }
                        }
                    }
                }

                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    text: "生成装备清单"
                    Material.background: CommonOptions.colorAccent
                    Material.foreground: "white"
                    font.pixelSize: styles.fsLg
                    font.bold: true
                    onClicked: generateList()
                }
            }
            }
        }

        // Tab 栏
        TabBar {
            id: tabBar
            Layout.fillWidth: true
            background: Rectangle { color: CommonOptions.colorSurface }
            // 2026-09-19: 把 TabBar.currentIndex 接到 equipmentPage.currentTab,
            //   否则 TabBar 视觉切换了但 StackLayout 没动, Tab 2 (装备库) 还是
            //   显示 Tab 1 (我的清单) 的内容.
            onCurrentIndexChanged: equipmentPage.currentTab = currentIndex
            TabButton {
                // 2026-09-19: TabButton 文本用 Row 拆 icon + 标签, 单独给 icon
                //   设 Material Icons 字体, 避免 emoji 在系统字体下渲染成 X
                contentItem: Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        text: "\ue153"  // fact_check
                        font.family: "Material Icons"
                        font.pixelSize: styles.fsMd
                        color: parent.parent.checked ? CommonOptions.colorAccent : CommonOptions.colorText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "我的清单"
                        color: parent.parent.checked ? CommonOptions.colorAccent : CommonOptions.colorText
                        font.pixelSize: styles.fsMd
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            TabButton {
                contentItem: Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        text: "\ue8b6"  // search
                        font.family: "Material Icons"
                        font.pixelSize: styles.fsMd
                        color: parent.parent.checked ? CommonOptions.colorAccent : CommonOptions.colorText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "装备库"
                        color: parent.parent.checked ? CommonOptions.colorAccent : CommonOptions.colorText
                        font.pixelSize: styles.fsMd
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: equipmentPage.currentTab

            // 2026-09-19: 切到装备库 tab 时主动刷一次 (Component.onCompleted
            //   在 qmlcachegen 静态编译下时机不稳, 兜底)
            onCurrentIndexChanged: {
                if (currentIndex === 1 && itemsView && itemsView.refreshItems) {
                    itemsView.refreshItems()
                }
                if (currentIndex === 0 && listView && listView.refreshLists) {
                    listView.refreshLists()
                }
            }

            // Tab 1: 我的清单
            Item {
                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.margins: styles.spLg
                    spacing: styles.spSm
                    clip: true

                    model: ServiceListModel {
                        id: listModel
                        service: equipmentService
                        method: "getAllLists"
                    }
                    Component.onCompleted: refreshLists()

                    function refreshLists() {
                        // 2026-09-20: 用 ServiceListModel 替代 clear+for+append 模板 (Phase 3)
                        listModel.refresh()
                    }

                    delegate: SwipeDelegate {
                        id: listDel
                        width: ListView.view.width
                        height: 80
                        // 2026-09-19: 把 model.* 绑到 listDel 自有属性, swipe.left
                        //   Rectangle / swipe.onCompleted 内访问 model 可能 undefined
                        property string _listId: model.id
                        property string _listName: model.name

                        // 主内容 (左滑前的正面)
                        contentItem: Rectangle {
                            radius: styles.rMd
                            color: CommonOptions.colorSurface
                            border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                            border.width: 1

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    equipmentPage.currentListId = listDel._listId
                                    ApplicationWindow.window.navBus.navigateTo("EquipmentDetailPage", {listId: listDel._listId})
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: styles.spSm
                                spacing: styles.spSm

                                Rectangle {
                                    width: 6
                                    Layout.fillHeight: true
                                    radius: 3
                                    color: {
                                        var c = [CommonOptions.colorSuccess, "#8BC34A", CommonOptions.colorWarn,
                                                "#FF9800", CommonOptions.colorDanger]
                                        return c[model.altitudeLevel] || CommonOptions.colorTextMuted
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text {
                                        text: model.name + (model.isCompleted ? "  ✓" : "")
                                        color: CommonOptions.colorText
                                        font.pixelSize: styles.fsLg
                                        font.bold: true
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    // 2026-09-19: 把 \ue52f (bicycle) 改成 \ue536 (hiking) 海拔级别图标
                                    Text {
                                        // 2026-09-19: 🏔️ emoji 替换 Material Icons landscape
                                        text: "\ue536 " + model.altitudeLevelName +
                                              "  ·  \ue6dd " + (model.totalWeightG / 1000).toFixed(2) + " kg"
                                        font.family: "Material Icons"
                                        color: CommonOptions.colorTextMuted
                                        font.pixelSize: styles.fsSm
                                    }
                                }

                                // 2026-09-19: 修改按钮 - 弹改名 Dialog
                                Button {
                                    text: "\ue3c9"  // Material Icons: edit
                                    font.family: "Material Icons"
                                    flat: true
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    Material.foreground: CommonOptions.colorAccent
                                    onClicked: {
                                        renameDialog.listId = listDel._listId
                                        renameDialog.listName = listDel._listName
                                        renameDialog.open()
                                    }
                                }

                                // 2026-09-19: 强装检查直跳入口 — 之前只能从
                                //   EquipmentDetailPage 进入 (间接路径), 现在
                                //   列表行直接可进, 减少一层跳转
                                Button {
                                    text: "\ue153"  // Material Icons: fact_check
                                    font.family: "Material Icons"
                                    flat: true
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    Material.foreground: CommonOptions.colorSuccess
                                    onClicked: {
                                        ApplicationWindow.window.navBus.navigateTo(
                                            "ChecklistPage", {listId: listDel._listId})
                                    }
                                }

                                // 2026-09-29: 补显式删除按钮 - 之前删除只藏在左滑手势里,
                                //   用户看不到入口, 反馈"清单行只有修改/查看, 没法删".
                                //   与装备库 tab 的删除按钮同构 (ToolButton 垃圾桶图标).
                                //   左滑删除保留作为快捷手势.
                                Button {
                                    text: "\ue872"  // Material Icons: delete
                                    font.family: "Material Icons"
                                    flat: true
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    Material.foreground: CommonOptions.colorDanger
                                    onClicked: {
                                        confirmDeleteDialog.listId = listDel._listId
                                        confirmDeleteDialog.listName = listDel._listName
                                        confirmDeleteDialog.open()
                                    }
                                }

                                Text {
                                    text: "›"
                                    color: "#607D8B"
                                    font.pixelSize: 22
                                }
                            }
                        }

                        // 左滑后显示的删除按钮
                        swipe.left: Rectangle {
                            width: listDel.height
                            color: CommonOptions.colorDanger
                            radius: styles.rMd
                            Text {
                                anchors.centerIn: parent
                                text: "\ue872\n删除"  // Material Icons: delete
                                font.family: "Material Icons"
                                color: "white"
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                            }
                            // 2026-09-16: Rectangle 没有 clicked signal, 加 MouseArea
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    confirmDeleteDialog.listId = listDel._listId
                                    confirmDeleteDialog.listName = listDel._listName
                                    confirmDeleteDialog.open()
                                }
                            }
                        }
                        // SwipeDelegate 真正的左滑完成信号在 swipe 附加对象上
                        swipe.onCompleted: {
                            confirmDeleteDialog.listId = listDel._listId
                            confirmDeleteDialog.listName = listDel._listName
                            confirmDeleteDialog.open()
                        }
                    }

                    Connections {
                        target: equipmentService
                        function onListGenerated(listId) { listView.refreshLists() }
                        function onListCompleted(listId) { listView.refreshLists() }
                    }
                }
            }

            // Tab 2: 装备库
            Item {
                // 2026-09-17: ListModel 提到 Item 外面 (避免嵌在 ListView 内被
                // qmlcachegen 静态分析时把 model 引用错位, 写不到 ListModel)
                ListModel { id: itemsModel }

                // 2026-09-21: 装备库顶部 toolbar — "新建装备"按钮放右上角,
                //   之前浮动在右下角 (anchors.right+anchors.bottom) 会遮挡
                //   ListView 最后一行右侧的"删除"按钮, 用户报"新建按钮遮挡
                //   删除按钮". 改成 toolbar 后与 ListView 垂直分离.
                Rectangle {
                    id: itemsToolbar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 56
                    color: CommonOptions.colorSurface
                    border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: "\ue53f 装备库"  // Material Icons: backpack
                            font.family: "Material Icons"
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsMd
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "\ue145 新建"  // Material Icons: add
                            font.family: "Material Icons"
                            Material.background: CommonOptions.colorAccent
                            Material.foreground: "white"
                            Layout.preferredHeight: 40
                            Layout.preferredWidth: 96
                            onClicked: addItemDialog.open()
                        }
                    }
                }

                ListView {
                    id: itemsView
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: itemsToolbar.bottom
                    anchors.bottom: parent.bottom
                    anchors.margins: styles.spLg
                    anchors.topMargin: 8
                    spacing: styles.spSm
                    clip: true

                    model: itemsModel
                    Component.onCompleted: refreshItems()

                    function refreshItems() {
                        itemsModel.clear()
                        if (!equipmentService) {
                            console.warn("[Equipment] equipmentService not available")
                            return
                        }
                        // 2026-09-20: 抽 helper 减少 2 路循环重复 (Phase 3)
                        var base = equipmentService.getAllItems()
                        var user = equipmentService.getUserItems()
                        _appendItems(base, false)
                        _appendItems(user, true)
                    }

                    function _appendItems(arr, isUser) {
                        for (var i = 0; i < arr.length; i++) {
                            itemsModel.append({
                                "id": arr[i].id,
                                "name": arr[i].name,
                                "category": arr[i].category,
                                "weightG": arr[i].weightG,
                                "isCritical": arr[i].isCritical,
                                "isUser": isUser
                            })
                        }
                    }

                    // 2026-09-23: 装备库 item UI 修复 - 内容垂直居中 + 加 category 图标.
    // 之前问题: (a) SwipeDelegate.contentItem = Rectangle, 内部 RowLayout
    //   默认 verticalAlignment 是 AlignVCenter 但 Rectangle + RowLayout 的
    //   子 Item 在 Material 控件 contentItem 模式下, 子 Text 默认 baseline
    //   居中, 但当某行 font.pixelSize 不一致 (14/16/18) 时, 整体看起来"内容
    //   靠下"; (b) 装备 JSON 没存 icon, 之前 model.category 不被映射到图标,
    //   视觉单调.
    // 修法: 给每个 item 显式 Layout.verticalAlignment + 按 category 派生图标.
    function _categoryIcon(cat) {
        switch (cat) {
            case "rescue":     return "\ue1b1"  // report_problem (急救)
            case "protection": return "\ue897"  // lock (防护)
            case "warmth":     return "\ue1ac"  // whatshot (保暖)
            case "altitude":   return "\ue536"  // landscape (高原)
            case "water":      return "\ue544"  // local_drink (饮水)
            case "food":       return "\ue56c"  // restaurant (食物)
            case "light":      return "\ue1b9"  // light (照明 -> 用 flashlight 附近的 emoji)
            case "tools":      return "\ue14d"  // build (工具)
            case "navigation": return "\ue55f"  // room (导航)
            default:           return "\ue53f"   // backpack (兜底)
        }
    }

    delegate: SwipeDelegate {
        id: itemDel
        width: ListView.view.width
        height: 56
        // 2026-09-19: 把 model.* 绑到 SwipeDelegate 自有属性, 因为
        //   swipe.left Rectangle 内 model 上下文不一定可访问
        //   (SwipeDelegate 是 Item 而非 Repeater/Delegate), 之前
        //   直接写 model.isUser / model.id 在 swipe.left Rectangle
        //   / MouseArea 里静默变 undefined → deleteUserItem(id="")
        //   走 id.isEmpty() 分支直接返回 false, 装备库"无法删除"
        property bool _isUser: model.isUser
        property string _itemId: model.id
        property string _itemName: model.name
        property string _itemCategory: model.category
        property int _itemWeight: model.weightG
        property bool _itemCritical: model.isCritical

        contentItem: Rectangle {
            radius: styles.rMd
            color: CommonOptions.colorSurface
            border.color: itemDel._isUser ? CommonOptions.colorAccent
                   : Qt.darker(CommonOptions.colorSurface, 1.15)
            border.width: 1

            // 2026-09-23: 改用 Item 包装 + RowLayout 显式 verticalAlignment,
            //   让装备名称 / 重量 / 编辑删除按钮在同一水平基线, 视觉居中
            // 2026-09-28: 装备库行内容垂直居中修复 — 去掉写在 RowLayout 自身
            //   的 Layout.alignment (对用 anchors 定位的实例是 no-op), 改为给
            //   每个子项 Layout.fillHeight + Text.verticalAlignment, 让不同
            //   字号子项 (图标 28 / 文本 14,12 / 按钮 36) 中心锚同一水平线.
            RowLayout {
                anchors.fill: parent
                anchors.margins: styles.spSm
                spacing: styles.spSm

                // category 图标 (按 item.category 派生)
                Item {
                    Layout.preferredWidth: 28
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    Rectangle {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        radius: 14
                        color: Qt.rgba(0, 0, 0, 0.04)
                    }
                    Text {
                        anchors.centerIn: parent
                        // 2026-10-09 修复: _categoryIcon 定义在 ListView(itemsView) 作用域,
                        //   不是 equipmentPage. 旧写法 equipmentPage._categoryIcon(...) 报
                        //   "Property '_categoryIcon' ... is not a function" (run.txt 刷屏 30+).
                        text: itemsView._categoryIcon(itemDel._itemCategory)
                        font.family: "Material Icons"
                        // 2026-09-23: 颜色按 category 区分, 之前单色太单调
                        color: itemDel._itemCritical
                               ? CommonOptions.colorDanger
                               : CommonOptions.colorAccent
                        font.pixelSize: 18
                    }
                }
                Text {
                    text: model.name + (itemDel._isUser ? "  \ue5d0" : "")
                    color: CommonOptions.colorText
                    font.pixelSize: styles.fsMd
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    text: model.weightG + "g"
                    color: CommonOptions.colorTextMuted
                    font.pixelSize: styles.fsSm
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    verticalAlignment: Text.AlignVCenter
                }
                // 2026-09-20: 右侧直接放"编辑"按钮 — 之前只能左滑,
                //   改用显式按钮 + ToolButton 更直观
                ToolButton {
                    text: "\ue3c9"  // Material Icons: edit
                    font.family: "Material Icons"
                    font.pixelSize: 18
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    Layout.alignment: Qt.AlignVCenter
                    Material.foreground: itemDel._isUser
                                          ? CommonOptions.colorAccent
                                          : CommonOptions.colorTextMuted
                    onClicked: {
                        if (itemDel._isUser) {
                            editItemDialog.editItemId = itemDel._itemId
                            editItemDialog.itemName = itemDel._itemName
                            editItemDialog.itemCategory = itemDel._itemCategory
                            editItemDialog.itemWeight = itemDel._itemWeight
                            editItemDialog.itemCritical = itemDel._itemCritical
                            editItemDialog.open()
                        } else {
                            // 2026-09-20: 基础库 item 不能直接编辑,
                            //   弹"复制为自定义副本"对话框, 让用户
                            //   改个名字/重量就能保存为自己定义
                            cloneItemDialog.baseId = itemDel._itemId
                            cloneItemDialog.baseName = itemDel._itemName
                            cloneItemDialog.baseCategory = itemDel._itemCategory
                            cloneItemDialog.baseWeight = itemDel._itemWeight
                            cloneItemDialog.baseCritical = itemDel._itemCritical
                            cloneItemDialog.open()
                        }
                    }
                }
                ToolButton {
                    text: "\ue872"  // Material Icons: delete
                    font.family: "Material Icons"
                    font.pixelSize: 18
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    Layout.alignment: Qt.AlignVCenter
                    Material.foreground: CommonOptions.colorDanger
                    enabled: itemDel._isUser  // 基础库条目不可删
                    opacity: enabled ? 1 : 0.3
                    onClicked: {
                        // 2026-09-21: Phase 5 - deleteUserItem 返回 Result.
                        if (equipmentService && itemDel._isUser) {
                            var r = equipmentService.deleteUserItem(itemDel._itemId)
                            if (r && r.ok === false) {
                                toast.error(r.error.message || "删除失败")
                            } else {
                                itemsView.refreshItems()
                            }
                        }
                    }
                }
            }
        }

                        // 保留左滑删除作为快捷手势 (user item)
                        swipe.left: Rectangle {
                            visible: itemDel._isUser
                            width: itemDel.height
                            color: CommonOptions.colorDanger
                            radius: styles.rMd
                            Text {
                                anchors.centerIn: parent
                                text: "\ue872\n删除"
                                font.family: "Material Icons"
                                color: "white"
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    // 2026-09-21: Phase 5 - deleteUserItem 返回 Result.
                                    if (equipmentService && itemDel._isUser) {
                                        var r = equipmentService.deleteUserItem(itemDel._itemId)
                                        if (r && r.ok === false) {
                                            toast.error(r.error.message || "删除失败")
                                        } else {
                                            itemsView.refreshItems()
                                        }
                                    }
                                }
                            }
                        }
                        swipe.onCompleted: {
                            if (!itemDel._isUser) {
                                itemDel.swipe.close()
                            }
                        }
                    }
                }
            }
        }
    }

    // 2026-09-17: 新建装备 Dialog
    Dialog {
        id: addItemDialog
        title: "新建装备"
        anchors.centerIn: parent
        // 2026-09-19: 固定 width 避免 implicitWidth 绑定循环
        width: 440
        height: 320
        standardButtons: Dialog.Ok | Dialog.Cancel

        property string itemName: ""
        property string itemCategory: "rescue"
        property int itemWeight: 100
        property bool itemCritical: false

        contentItem: ColumnLayout {
            spacing: 8
            width: 400
            TextField {
                id: newNameField
                Layout.fillWidth: true
                placeholderText: "装备名称 (如: 头灯)"
                onTextChanged: addItemDialog.itemName = text
            }
            // 2026-09-19: 改成中文标签 (展示用), 实际存到 QSettings 的仍是英文 category key
            //   (rescue/protection/...), 与 equipment_base.json 一致, 强装规则能匹配
            ComboBox {
                id: newCategoryCombo
                Layout.fillWidth: true
                model: [
                    { text: "急救救援", key: "rescue" },
                    { text: "防护", key: "protection" },
                    { text: "保暖", key: "warmth" },
                    { text: "高原", key: "altitude" },
                    { text: "饮水", key: "water" },
                    { text: "食物", key: "food" },
                    { text: "照明", key: "light" },
                    { text: "工具", key: "tools" },
                    { text: "导航", key: "navigation" }
                ]
                textRole: "text"
                valueRole: "key"
                onActivated: addItemDialog.itemCategory = currentValue
            }
            TextField {
                id: newWeightField
                Layout.fillWidth: true
                placeholderText: "重量(g)"
                inputMethodHints: Qt.ImhDigitsOnly
                text: "100"
                onTextChanged: addItemDialog.itemWeight = parseInt(text) || 0
            }
            CheckBox {
                id: newCriticalCheck
                text: "关键装备 (强装)"
                onCheckedChanged: addItemDialog.itemCritical = checked
            }
        }
        onAccepted: {
            // 2026-09-21: Phase 5 - addUserItem 返回 Result.
            if (equipmentService && addItemDialog.itemName.trim().length > 0) {
                var r = equipmentService.addUserItem(
                    addItemDialog.itemName.trim(),
                    addItemDialog.itemCategory,
                    addItemDialog.itemWeight,
                    addItemDialog.itemCritical)
                if (r && r.ok === false) {
                    toast.error(r.error.message || "添加失败")
                } else {
                    equipmentPage._refreshItemsView()
                    toast.success("已添加装备")
                }
            }
        }
    }

    // 2026-09-20: 编辑现有 user item — 复用 addItemDialog 的字段类型,
    //   显式 editItemId 区分新建 / 编辑
    // 2026-09-21: 修复 - 之前 TextField 用 `text: editItemDialog.itemName` +
    //   `onTextChanged: editItemDialog.itemName = text` 形成 binding 循环,
    //   qmlcachegen 静态编译下会让 Dialog 整个无法实例化, 用户报
    //   "装备库编辑按钮界面存在问题".
    //   改用 id + onOpened 一次性赋值, 与 addItemDialog / cloneItemDialog 同构.
    Dialog {
        id: editItemDialog
        title: "修改装备"
        anchors.centerIn: parent
        width: 440
        height: 320
        standardButtons: Dialog.Ok | Dialog.Cancel

        property string editItemId: ""
        property string itemName: ""
        property string itemCategory: "rescue"
        property int itemWeight: 100
        property bool itemCritical: false

        onOpened: {
            editNameField.text = itemName
            editWeightField.text = String(itemWeight)
        }

        contentItem: ColumnLayout {
            spacing: 8
            width: 400
            TextField {
                id: editNameField
                Layout.fillWidth: true
                placeholderText: "装备名称"
                onTextChanged: editItemDialog.itemName = text
            }
            ComboBox {
                id: editCatCombo
                Layout.fillWidth: true
                model: [
                    { text: "急救救援", key: "rescue" },
                    { text: "防护", key: "protection" },
                    { text: "保暖", key: "warmth" },
                    { text: "高原", key: "altitude" },
                    { text: "饮水", key: "water" },
                    { text: "食物", key: "food" },
                    { text: "照明", key: "light" },
                    { text: "工具", key: "tools" },
                    { text: "导航", key: "navigation" }
                ]
                textRole: "text"
                valueRole: "key"
                Component.onCompleted: {
                    for (var i = 0; i < model.length; i++) {
                        if (model[i].key === editItemDialog.itemCategory) {
                            currentIndex = i; break
                        }
                    }
                }
                onActivated: editItemDialog.itemCategory = currentValue
            }
            TextField {
                id: editWeightField
                Layout.fillWidth: true
                placeholderText: "重量(g)"
                inputMethodHints: Qt.ImhDigitsOnly
                onTextChanged: editItemDialog.itemWeight = parseInt(text) || 0
            }
            CheckBox {
                id: editCriticalCheck
                text: "关键装备 (强装)"
                Component.onCompleted: checked = editItemDialog.itemCritical
                onCheckedChanged: editItemDialog.itemCritical = checked
            }
        }
        onAccepted: {
            // 2026-09-21: Phase 5 - updateUserItem 返回 Result.
            if (equipmentService && editItemDialog.editItemId.length > 0
                && editItemDialog.itemName.trim().length > 0) {
                var r = equipmentService.updateUserItem(
                    editItemDialog.editItemId,
                    editItemDialog.itemName.trim(),
                    editItemDialog.itemCategory,
                    editItemDialog.itemWeight,
                    editItemDialog.itemCritical)
                if (r && r.ok === false) {
                    toast.error(r.error.message || "保存失败")
                } else {
                    equipmentPage._refreshItemsView()
                    toast.success("已修改装备")
                }
            }
        }
    }

    // 2026-09-20: 基础库条目不能直接编辑, 用户可"复制为自定义副本"再修改
    Dialog {
        id: cloneItemDialog
        title: "复制为自定义装备"
        anchors.centerIn: parent
        width: 440
        height: 320
        standardButtons: Dialog.Ok | Dialog.Cancel

        property string baseId: ""
        property string baseName: ""
        property string baseCategory: "rescue"
        property int baseWeight: 100
        property bool baseCritical: false
        // 2026-09-20: 一次性初始名 (包含 "(副本)" 后缀), 不可被 onTextChanged 改写.
        readonly property string _initName: baseName + " (副本)"

        // 用户点 OK 时再从 cloneNameField 取最终名字 (用户输入覆盖了初始化值)
        onOpened: {
            cloneNameField.text = baseName + " (副本)"
        }

        contentItem: ColumnLayout {
            spacing: 8
            width: 400
            Text {
                text: "基础库条目不能直接编辑, 复制后改名 / 改重保存为自定义装备"
                color: CommonOptions.colorTextMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            TextField {
                id: cloneNameField
                Layout.fillWidth: true
                // 2026-09-20: 不再写 text 绑定 (会触发 onTextChanged 回写 baseName),
                //   改由 cloneItemDialog.onOpened 一次性设置. placeholderText 仅作提示.
                placeholderText: "装备名称"
            }
            ComboBox {
                id: cloneCatCombo
                Layout.fillWidth: true
                model: [
                    { text: "急救救援", key: "rescue" },
                    { text: "防护", key: "protection" },
                    { text: "保暖", key: "warmth" },
                    { text: "高原", key: "altitude" },
                    { text: "饮水", key: "water" },
                    { text: "食物", key: "food" },
                    { text: "照明", key: "light" },
                    { text: "工具", key: "tools" },
                    { text: "导航", key: "navigation" }
                ]
                textRole: "text"
                valueRole: "key"
                currentIndex: {
                    for (var i = 0; i < model.length; i++) {
                        if (model[i].key === cloneItemDialog.baseCategory) return i
                    }
                    return 0
                }
                onActivated: cloneItemDialog.baseCategory = currentValue
            }
            TextField {
                Layout.fillWidth: true
                placeholderText: "重量(g)"
                inputMethodHints: Qt.ImhDigitsOnly
                text: String(cloneItemDialog.baseWeight)
                onTextChanged: cloneItemDialog.baseWeight = parseInt(text) || 0
            }
            CheckBox {
                text: "关键装备 (强装)"
                checked: cloneItemDialog.baseCritical
                onCheckedChanged: cloneItemDialog.baseCritical = checked
            }
        }
        onAccepted: {
            // 2026-09-21: Phase 5 - addUserItem 返回 Result.
            var finalName = (cloneNameField.text || "").trim()
            if (equipmentService && finalName.length > 0) {
                var r = equipmentService.addUserItem(
                    finalName,
                    cloneItemDialog.baseCategory,
                    cloneItemDialog.baseWeight,
                    cloneItemDialog.baseCritical)
                if (r && r.ok === false) {
                    toast.error(r.error.message || "复制失败")
                } else {
                    equipmentPage._refreshItemsView()
                    toast.success("已复制为自定义装备")
                }
            }
        }
    }

    // 2026-09-19: 自动生成清单名 (占位提示, 用户没改时给出建议名)
    function autoUpdateName() {
        if (nameField.text.length === 0) {
            var alt = parseInt(altMaxField.text) || 0
            var days = parseInt(daysField.text) || 1
            if (alt > 0) {
                nameField.placeholderText = "海拔" + alt + "m·" + days + "天"
            }
        }
    }

    // 2026-09-19: 重置表单
    function resetForm() {
        altMaxField.text = "1500"
        daysField.text = "2"
        equipmentPage.difficulty = 2
        // 2026-09-23: 环境维度复位
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
    }

    function generateList() {
        var altMax = parseInt(altMaxField.text) || 0
        var days = parseInt(daysField.text) || 1
        var diff = equipmentPage.difficulty

        if (altMax <= 0) {
            toast.error("请输入有效的海拔 (>0)")  // 2026-09-20: 切 Toast
            return
        }
        if (!equipmentService) {
            toast.error("engine 未就绪, 重启 app 后重试")  // 2026-09-20: 切 Toast
            return
        }

        // 2026-09-19: 名称为空时自动生成 (基于海拔/天数)
        var listName = nameField.text.trim()
        if (listName.length === 0) {
            listName = "海拔" + altMax + "m·" + days + "天"
        }

        // 2026-09-23: 环境维度一并下发. 之前只发 12 个字段, equipment_rules.json
        //   里 19 条依赖季节/降水/湿度/UV/风级/昼夜温差/地区标记的规则拿不到输入,
        //   C++ 端永远用默认值 → 这些规则恒定匹配/不匹配. 风力等级同时反推一个
        //   代表风速喂给 wind_speed 规则 (0/1/2/3/4 级 → 0.2/2/5/9/15 m/s).
        var windSpeedByLevel = [0.2, 2.0, 5.0, 9.0, 15.0]
        var params = {
            "altitudeMax": altMax,
            "altitudeMin": Math.max(0, altMax - 500),
            "altitudeCamp": Math.max(0, altMax - 200),
            "days": days,
            "people": 1,
            "difficulty": diff,
            "season": equipmentPage.seasonIndex,
            "tempAvg": 15.0,
            "tempMin": 5.0,
            "windSpeed": windSpeedByLevel[equipmentPage.windLevelIndex] || 0.0,
            "precipitation": equipmentPage.precipIndex,
            "uvIndex": 5.0,
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
            toast.error("生成失败, 请检查参数")  // 2026-09-20: 切 Toast
            return
        }
        equipmentPage.currentListId = result.id
        ApplicationWindow.window.navBus.navigateTo("EquipmentDetailPage", {listId: result.id})
    }

    // 2026-09-17: 触发装备库刷新 (新建/删除 user item 后调)
    function _refreshItemsView() {
        if (typeof itemsView !== "undefined" && itemsView && itemsView.refreshItems) {
            itemsView.refreshItems()
        }
    }

    // 2026-09-20: errorDialog 已切 Toast (统一反馈), 此处删除
    // 错误信息现在通过 toast.error("...") 调用

    // 2026-09-14: 确认删除 Dialog (左滑后弹出)
    Dialog {
        id: confirmDeleteDialog
        property string listId: ""
        property string listName: ""
        title: "确认删除"
        anchors.centerIn: parent
        // 2026-09-19: 固定 width, 避免 Dialog width <-> contentItem.implicitWidth
        //   形成绑定循环 (前一次 fix 用 `parent.width - 40` 仍是 binding)
        width: 420
        height: 200
        standardButtons: Dialog.Yes | Dialog.No
        contentItem: Text {
            // 固定宽度, 严禁写 parent.width 的 binding
            width: 380
            text: "确定要删除装备清单 \"" + confirmDeleteDialog.listName + "\" 吗？此操作不可撤销。"
            color: CommonOptions.colorText
            wrapMode: Text.WordWrap
        }
        onAccepted: {
            if (listId) {
                // 2026-09-21: Phase 5 - deleteList 返回 Result.
                var r = equipmentService.deleteList(listId)
                if (r && r.ok === false) {
                    toast.error(r.error.message || "删除清单失败")
                } else {
                    listView.refreshLists()
                    toast.success("已删除清单")
                }
            }
        }
    }

    // 2026-09-19: 重命名 Dialog (我的清单 → 修改按钮)
    Dialog {
        id: renameDialog
        property string listId: ""
        property string listName: ""
        title: "重命名清单"
        anchors.centerIn: parent
        width: 420
        height: 220
        standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: ColumnLayout {
            spacing: 8
            width: 380
            Text {
                text: "新名称:"
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsSm
            }
            TextField {
                id: renameField
                Layout.fillWidth: true
                text: renameDialog.listName
                color: CommonOptions.colorText
                onTextChanged: renameDialog.listName = text
            }
        }
        onAccepted: {
            // 2026-09-21: Phase 5 - modifyList 返回 Result.
            if (listId && renameField.text.trim().length > 0) {
                var old = equipmentService.getList(listId)
                if (old && old.id) {
                    old.name = renameField.text.trim()
                    var r = equipmentService.modifyList(listId, old)
                    if (r && r.ok === false) {
                        toast.error(r.error.message || "重命名失败")
                    } else {
                        listView.refreshLists()
                    }
                }
            }
        }
    }
}
