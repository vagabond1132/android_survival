/**
 * @file FilterRow.qml
 * @brief 筛选行组件 (2026-09-20 抽出, 2026-10-16 改版 token 化)
 *
 * 用于 RouteListPage / TravelListPage / NearbyTab 等所有需要"标签 + 控件"的筛选场景.
 * 视觉风格统一: 尺寸全部取自 Styles.*, 颜色全部取自 CommonOptions.*.
 *
 * 用法 1 (ComboBox):
 *   FilterRow { label: "省份"; comboModel: routeListPage.provinces; currentIndex: 0
 *               onComboActivated: (i) => routeListPage.filterProvince = comboModel[i] }
 *
 * 用法 2 (步进器):
 *   FilterRow { label: "半径"; stepperValue: root.radiusKm + " km"
 *               onStepperMinus: root.radiusKm = Math.max(10, root.radiusKm - 10)
 *               onStepperPlus:  root.radiusKm = Math.min(500, root.radiusKm + 10) }
 *
 * 2026-10-21 #65: 删掉第三种模式 "难度 ★ chip" (chipCount / chipSelected /
 *   chipClicked). 全站 0 调用方, 且那颗 ★ 是本页唯一的非等宽字形硬编码 ——
 *   丁骨架里难度一律走 Ladder + difficultyLabel, 不留第二套写法.
 */

// 2026-10-19 真机 stage0.log: delegate 里引用外层 id (如 categorySection / searchDialog) 在 qmlcachegen
// 编译下会抛 ReferenceError, 必须 Bound 语义才能拿到外层组件作用域.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

RowLayout {
    id: filterRow

    Styles { id: styles; visible: false }

    // === 公共属性 ===
    property string label: ""
    property int labelWidth: styles.icBox
    property color surfaceColor: CommonOptions.colorSurface
    property color borderColor: CommonOptions.colorDivider

    // === 模式选择: combo / stepper, 二选一 (靠 comboModel 是否为 null 区分) ===
    // combo 模式
    property var comboModel: null
    property string comboTextRole: ""
    property string comboValueRole: ""
    property int comboCurrentIndex: 0
    signal comboActivated(int index, var value)

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

    spacing: styles.spSm

    Text {
        text: filterRow.label
        color: CommonOptions.colorTextMuted
        font.pixelSize: styles.fsSm
        Layout.preferredWidth: filterRow.labelWidth
    }

    // === ComboBox 模式 ===
    Loader {
        id: comboLoader
        Layout.fillWidth: true
        // 2026-09-28: 修问题 2 (2.jpg "明显的下拉条, 布局存在问题").
        //   Material 风格 ComboBox 的 implicitHeight 默认 ~48-56px, 而 chip /
        //   stepper 模式显式用 36px → TravelListPage 里 4 个 ComboBox 叠起来时
        //   每行都比 chip/stepper 高一大截. 显式锁 36px 与其余两种模式对齐.
        Layout.preferredHeight: styles.rowHSm
        Layout.minimumHeight: styles.rowHSm
        Layout.maximumHeight: styles.rowHSm
        active: filterRow.comboModel !== null
        sourceComponent: ComboBox {
            id: comboBoxItem
            model: filterRow.comboModel
            textRole: filterRow.comboTextRole
            valueRole: filterRow.comboValueRole
            currentIndex: filterRow.comboCurrentIndex
            implicitHeight: styles.rowHSm
            font.pixelSize: styles.fsMd
            topPadding: 0
            bottomPadding: 0
            // 2026-10-16: Material 的弹出列表挂在 Overlay 上, 不继承 control.font,
            //   必须显式给 delegate, 否则弹出项回退系统字体 → 图标变方框.
            delegate: ItemDelegate {
                required property var model
                required property var modelData
                required property int index
                width: comboBoxItem.width
                height: styles.rowHSm
                contentItem: Text {
                    // 2026-10-19 真机 stage0.log: "FilterRow.qml:102: Unable to assign
                    //   [undefined] to QString" —— 调用方 (RouteListPage / TravelListPage /
                    //   SearchTab) 传的是**字符串数组**且没给 comboTextRole, 于是这里取
                    //   model["displayText"], 而 model 本身就是那个字符串 → undefined,
                    //   弹出层 101 行全是空白, 省份/天数/距离/月份四个筛选器整体不可用.
                    //   只有 FieldGuidePage 用 {name}/{label} 对象数组, 才需要走 textRole.
                    text: filterRow.comboTextRole !== ""
                          ? model[filterRow.comboTextRole] : modelData
                    color: highlighted ? CommonOptions.colorTextOnAccent : CommonOptions.colorText
                    font.pixelSize: styles.fsMd
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                highlighted: comboBoxItem.highlightedIndex === index
                hoverEnabled: false
            }
            onActivated: filterRow.comboActivated(currentIndex, currentValue)
        }
        // 2026-09-21: Loader 加载完后, 内部 ComboBox 实例暴露给外部
        onLoaded: filterRow.comboBoxInstance = item
    }

    // === Stepper 模式 ===
    Loader {
        Layout.fillWidth: true
        active: filterRow.comboModel === null
        sourceComponent: RowLayout {
            spacing: 0
            Rectangle {
                Layout.preferredWidth: styles.rowHSm
                Layout.preferredHeight: styles.rowHSm
                radius: styles.rMd
                color: filterRow.stepperMinusEnabled
                       ? filterRow.surfaceColor : CommonOptions.colorSurfaceDim
                IconLabel {
                    anchors.centerIn: parent
                    name: "remove"
                    size: styles.icMd
                    tintColor: filterRow.stepperMinusEnabled
                               ? CommonOptions.colorText : CommonOptions.colorTextDisabled
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: filterRow.stepperMinusEnabled
                    onClicked: filterRow.stepperMinus()
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: styles.rowHSm
                Layout.leftMargin: styles.spXs
                Layout.rightMargin: styles.spXs
                color: filterRow.surfaceColor
                border.color: filterRow.borderColor
                border.width: styles.lineHair
                radius: styles.rMd
                Text {
                    anchors.centerIn: parent
                    text: filterRow.stepperValue
                    color: CommonOptions.colorText
                    font.pixelSize: styles.fsMd
                    font.bold: true
                }
            }
            Rectangle {
                Layout.preferredWidth: styles.rowHSm
                Layout.preferredHeight: styles.rowHSm
                radius: styles.rMd
                color: filterRow.stepperPlusEnabled
                       ? filterRow.surfaceColor : CommonOptions.colorSurfaceDim
                IconLabel {
                    anchors.centerIn: parent
                    name: "add"
                    size: styles.icMd
                    tintColor: filterRow.stepperPlusEnabled
                               ? CommonOptions.colorText : CommonOptions.colorTextDisabled
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: filterRow.stepperPlusEnabled
                    onClicked: filterRow.stepperPlus()
                }
            }
        }
    }
}
