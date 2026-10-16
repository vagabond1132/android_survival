/**
 * @file FilterRow.qml
 * @brief 筛选行组件 (2026-09-20 抽出)
 *
 * 用于 RouteListPage / TravelListPage / NearbyTab 等所有需要"标签 + 控件"的筛选场景.
 * 视觉风格统一:
 *   - 标签 12sp, colorTextMuted
 *   - 控件: ComboBox / chip row / ±stepper 三选一
 *   - 整行高度统一 40-44, 圆角 8, 浅边框
 *
 * 用法 1 (ComboBox):
 *   FilterRow { label: "省份"; comboModel: routeListPage.provinces; currentIndex: 0
 *               onComboActivated: (i) => routeListPage.filterProvince = comboModel[i] }
 *
 * 用法 2 (难度 chip):
 *   FilterRow { label: "难度"; chipCount: 5; chipSelected: routeListPage.filterDifficulty
 *               onChipClicked: (n) => routeListPage.filterDifficulty = n }
 *
 * 用法 3 (步进器):
 *   FilterRow { label: "半径"; stepperValue: root.radiusKm + " km"
 *               onStepperMinus: root.radiusKm = Math.max(10, root.radiusKm - 10)
 *               onStepperPlus:  root.radiusKm = Math.min(500, root.radiusKm + 10) }
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

RowLayout {
    id: filterRow

    // === 公共属性 ===
    property string label: ""
    property int labelWidth: 40
    property string accent: CommonOptions.colorAccent
    property string surfaceColor: CommonOptions.colorSurface
    property string borderColor: Qt.darker(CommonOptions.colorSurface, 1.2)

    // === 模式选择: combo / chip / stepper, 三选一 ===
    // combo 模式
    property var comboModel: null
    property string comboTextRole: ""
    property string comboValueRole: ""
    property int comboCurrentIndex: 0
    signal comboActivated(int index, var value)

    // chip 模式 (难度 ★)
    property int chipCount: 0
    property int chipSelected: 0
    signal chipClicked(int n)

    // stepper 模式 (半径 ±)
    property string stepperValue: ""
    signal stepperMinus()
    signal stepperPlus()
    property bool stepperMinusEnabled: true
    property bool stepperPlusEnabled: true

    // 2026-09-21: 暴露内部 ComboBox 实例, 解决调用方在 FilterRow 外部
    //   没法访问 ComboBox 的问题 (之前用 Loader 藏着, 导致
    //   "provCombo is not defined"). 当 comboModel 非空且 Loader 已实例化后,
    //   comboBoxInstance.currentIndex 才可用.
    property QtObject comboBoxInstance: null

    spacing: 8

    Text {
        text: filterRow.label
        color: CommonOptions.colorTextMuted
        font.pixelSize: 12
        Layout.preferredWidth: filterRow.labelWidth
    }

    // === ComboBox 模式 ===
    Loader {
        id: comboLoader
        Layout.fillWidth: true
        // 2026-09-28: 修问题 2 (2.jpg "明显的下拉条, 布局存在问题").
        //   Material 风格 ComboBox 的 implicitHeight 默认 ~48-56px (内容 + 上下
        //   padding + 下划线), 而 chip / stepper 模式显式用 36px → TravelListPage
        //   里 4 个 ComboBox 叠起来时每行都比 chip/stepper 高一大截, 视觉上就是
        //   "明显的下拉条". 显式锁 36px 与其余两种模式对齐.
        //   Loader 会把 item 缩放到自身尺寸, 故设 Loader 高度即可.
        Layout.preferredHeight: 36
        Layout.minimumHeight: 36
        Layout.maximumHeight: 36
        active: filterRow.comboModel !== null
        sourceComponent: ComboBox {
            id: comboBoxItem
            model: filterRow.comboModel
            textRole: filterRow.comboTextRole
            valueRole: filterRow.comboValueRole
            currentIndex: filterRow.comboCurrentIndex
            // 2026-09-28: 双保险 - 即使 Loader 尺寸传播有偏差, ComboBox 自身也锁 36px.
            implicitHeight: 36
            font.pixelSize: 13
            topPadding: 0
            bottomPadding: 0
            onActivated: filterRow.comboActivated(currentIndex, currentValue)
        }
        // 2026-09-21: Loader 加载完后, 内部 ComboBox 实例暴露给外部
        onLoaded: filterRow.comboBoxInstance = item
    }
    // 2026-09-21: 暴露 ComboBox, 让外部 (TravelListPage / RouteListPage 等) 能
    //   通过 filterRow.comboBoxItem 直接读写 currentIndex (例如重置时清零).
    //   在 Loader active 之后才有效; 调用方需保证 Loader 已实例化.

    // === Chip 模式 ===
    Loader {
        Layout.fillWidth: true
        active: filterRow.chipCount > 0 && filterRow.comboModel === null
        sourceComponent: RowLayout {
            spacing: 4
            // 2026-09-20: 增加 "全部" 按钮 (chipCount 个★ + 1 个"全部"),
            //   之前 chipSelected=0 时所有★都灰, 用户没法恢复 "全部". 现在
            //   "全部" 高亮 = 0★ 状态, 视觉明确.
            Rectangle {
                Layout.preferredHeight: 36
                Layout.preferredWidth: 60
                radius: 8
                color: filterRow.chipSelected === 0
                       ? filterRow.accent
                       : filterRow.surfaceColor
                border.color: filterRow.chipSelected === 0
                              ? filterRow.accent
                              : filterRow.borderColor
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "全部"
                    color: filterRow.chipSelected === 0 ? "white" : CommonOptions.colorTextMuted
                    font.pixelSize: 12
                    font.bold: filterRow.chipSelected === 0
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: filterRow.chipClicked(0)
                }
            }
            Repeater {
                model: filterRow.chipCount
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: 8
                    // 难度越高越深红: 1=绿 2=黄 3=橙 4=红 5=深红 (与 RouteListPage 色条同源)
                    readonly property int _idx: index + 1
                    readonly property bool _isSelected: _idx <= filterRow.chipSelected
                    readonly property color _starColor:
                        _idx >= 5 ? "#B71C1C" :
                        _idx >= 4 ? "#D32F2F" :
                        _idx >= 3 ? "#F57C00" :
                        _idx >= 2 ? "#FBC02D" : "#388E3C"
                    color: _isSelected ? _starColor : filterRow.surfaceColor
                    border.color: _isSelected ? _starColor : filterRow.borderColor
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "★"
                        color: parent._isSelected ? "white" : CommonOptions.colorTextMuted
                        font.pixelSize: 18
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: filterRow.chipClicked(parent._idx)
                    }
                }
            }
        }
    }

    // === Stepper 模式 ===
    Loader {
        Layout.fillWidth: true
        active: filterRow.comboModel === null && filterRow.chipCount === 0
        sourceComponent: RowLayout {
            spacing: 0
            Button {
                text: "\ue15b"  // Material Icons: remove
                font.family: "Material Icons"
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                enabled: filterRow.stepperMinusEnabled
                onClicked: filterRow.stepperMinus()
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                color: filterRow.surfaceColor
                border.color: filterRow.borderColor
                border.width: 1
                radius: 8
                Text {
                    anchors.centerIn: parent
                    text: filterRow.stepperValue
                    color: CommonOptions.colorText
                    font.pixelSize: 14
                    font.bold: true
                }
            }
            Button {
                text: "\ue145"  // Material Icons: add
                font.family: "Material Icons"
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                enabled: filterRow.stepperPlusEnabled
                onClicked: filterRow.stepperPlus()
            }
        }
    }
}