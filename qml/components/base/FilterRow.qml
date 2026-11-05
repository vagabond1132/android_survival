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
    // 2026-11-03 真机 (F1 / 定律 L11): 下拉的**显示值**必须来自页面状态, 不能来自控件内部
    //   那个 currentIndex。现场: 资源页省份选「北京」→ 月份选「7 月」，页头与列表确实按
    //   7 月筛了 (31 条)，但月份框自己还写着「全部」—— 用户看到的控件说"没筛"，数据说"筛了"。
    //   根因不在页面状态 (它是对的)，在 ComboBox 一旦被弹层提交就会自己接管 currentIndex，
    //   声明式那条绑定随时可能不再回头 (同下面 A43 注释里"模型重建把内部 index 打回 -1"
    //   是同一族问题)。所以这里给调用方一个**覆盖口**: 只要 comboDisplayText 非空，
    //   框上写的就是它，控件内部状态再也顶不翻。留空 = 维持旧行为 (由 currentIndex 推)。
    property string comboDisplayText: ""

    // 2026-11-03 (F1 / L11): 从**声明式反查出来的 index** 取显示词，而不是从控件内部的
    //   currentIndex 取。 comboModel 三种形态都要认：ListModel (get)、JS 数组 (下标)、
    //   对象数组带 textRole (取键)。字符串数组没有 textRole 时整行就是显示词。
    function textForRow(index) {
        var m = filterRow.comboModel
        if (!m) return ""
        var n = filterRow.comboRowCount
        if (n <= 0) return ""
        var i = (index < 0 || index >= n) ? 0 : index
        var row = (m.count !== undefined) ? m.get(i) : m[i]
        if (row === undefined || row === null) return ""
        return filterRow.comboTextRole !== "" ? String(row[filterRow.comboTextRole]) : String(row)
    }
    // 2026-10-29 真机 (A43): ②资源切界门后省份框整块空白 (月份框正常) —— 差别只在省份
    //   传的是 ListModel 且页面会原地 clear()+append() 重建。ComboBox 在模型被清空那一刻
    //   会把内部 currentIndex 打回 -1, 而调用方给 comboCurrentIndex 求出来还是 0 —— 值没变
    //   就不发 changed, 下面那条 currentIndex 绑定根本不重跑, 没人把 -1 拽回来, displayText
    //   就成了空字符串。同进程 A/B 实测: 绑定块直连 prov.count 的那版一直显示"全部", 隔了
    //   comboCurrentIndex 这一层的那版重建后 idx=-1 / displayText=""。
    //   所以这里额外读一次"行数", 让 currentIndex 那条绑定必然跟着重建重跑一遍。
    //   ListModel 走 count, JS 数组 / QStringList 走 length (RouteList/TravelList/SearchTab
    //   那几个调用方传的是数组, 不能只认 count)。
    // 2026-11-04 真机 + 容器量实 (F1-2): 上面这句口径没错, 但**代码写错了** —— 原来第二支是
    //   `Array.isArray(comboModel) ? comboModel.length : 0`。C++ 的 Q_INVOKABLE QVariantList /
    //   QStringList 跨到 QML 是**包装列表**: typeof=object、Array.isArray()===false、
    //   .count/.get 都是 undefined, 只有 .length / [i] / indexOf / join 能用
    //   (test_common_options.cpp 的 cpp_qvariantlist_is_wrapped_not_js_array_in_qml /
    //    cpp_stringlist_is_wrapped_not_js_array_in_qml 两条槽各打一遍)。
    //   于是 comboRowCount 走到最后的 0 支 → textForRow 的 `if (n <= 0) return ""` →
    //   displayText 空 → 月份框整块空白。错的是"行数"这一支, 取行那一支 (m[i]) 一直是好的。
    //   判据改成认 .length: 包装列表和真 JS 数组都有 length, 一支顶两支。
    //   定律 L14, 门禁 tools/qml_checks/combo_shape_check.js。
    property int comboRowCount: !comboModel ? 0
                              : (comboModel.count !== undefined ? comboModel.count
                                 : (comboModel.length !== undefined ? comboModel.length : 0))
    // 2026-10-27 真机 (A38): 省份 33 项的下拉按 Material 默认取整列 contentHeight,
    //   比屏幕还高 → 底下几项滚不到。弹出层最多显示这么多行, 其余走 ListView 滚动。
    property int comboPopupMaxRows: 10
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
            currentIndex: {
                var want = filterRow.comboCurrentIndex
                var n = filterRow.comboRowCount
                return n > 0 ? Math.min(want, n - 1) : 0
            }
            implicitHeight: styles.rowHSm
            font.pixelSize: styles.fsMd
            topPadding: 0
            bottomPadding: 0
            // 显示值口径见上面 comboDisplayText / textForRow 的注释 (F1 / L11)
            displayText: filterRow.comboDisplayText.length > 0
                         ? filterRow.comboDisplayText
                         : filterRow.textForRow(filterRow.comboCurrentIndex)
            // 2026-10-23 真机 (#114 布局): 收起态外框吃的是 Material 默认的深描边,
            //   在一片 colorSurface 里像一块"被圈出来的错误". 全站描边口径是 hairline +
            //   colorDivider, 只有正在交互 (弹出中 / 拿到焦点) 才升成 colorText.
            background: Rectangle {
                radius: styles.rSm
                color: CommonOptions.colorSurface
                border.width: styles.lineHair
                border.color: (comboBoxItem.popup.visible || comboBoxItem.activeFocus)
                              ? CommonOptions.colorText : CommonOptions.colorDivider
            }
            // 2026-10-16: Material 的弹出列表挂在 Overlay 上, 不继承 control.font,
            //   必须显式给 delegate, 否则弹出项回退系统字体 → 图标变方框.
            delegate: ItemDelegate {
                id: comboDelegate
                required property var model
                required property var modelData
                required property int index
                width: comboBoxItem.width
                height: styles.rowHSm
                // 2026-10-23 真机 (#114): 选中/高亮那一行原来靠 Material 的淡灰
                //   hover 底 + colorTextOnAccent 白字 —— 白字画在淡灰上, 强光下完全
                //   看不出"当前选的是哪一条" (省下拉里那条「全部」就是这么丢的).
                //   改成浅底深字 + 左侧强调条, 和 ListRow/Chip 的选中口径一致.
                background: Rectangle {
                    color: comboDelegate.highlighted ? CommonOptions.colorSurfaceDim
                                                     : "transparent"
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: styles.lineAccent
                        visible: comboDelegate.highlighted
                        color: CommonOptions.colorAccentSoft
                    }
                }
                contentItem: Text {
                    // 2026-10-19 真机 stage0.log: "FilterRow.qml:102: Unable to assign
                    //   [undefined] to QString" —— 调用方 (RouteListPage / TravelListPage /
                    //   SearchTab) 传的是**字符串数组**且没给 comboTextRole, 于是这里取
                    //   model["displayText"], 而 model 本身就是那个字符串 → undefined,
                    //   弹出层 101 行全是空白, 省份/天数/距离/月份四个筛选器整体不可用.
                    //   只有 FieldGuidePage 用 {name}/{label} 对象数组, 才需要走 textRole.
                    text: filterRow.comboTextRole !== ""
                          ? model[filterRow.comboTextRole] : modelData
                    color: CommonOptions.colorText
                    font.pixelSize: styles.fsMd
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                highlighted: comboBoxItem.highlightedIndex === index
                hoverEnabled: false
            }
            // 2026-10-27 真机 (A38): Material 的 ComboBoxPopup 高度取自 contentItem
            //   (一个 ListView) 的 implicitHeight, 而它默认 = contentHeight —— 33 个省
            //   直接顶穿屏幕, 底下几项点不到。只给那个 ListView 上高度上限, 不整体重写
            //   popup: 重写要引 Popup 类型, 和本工程"只 import QtQuick.Controls.Material"
            //   的打包口径冲突 (见 controls_import_check.js)。
            Component.onCompleted: {
                if (!popup || !popup.contentItem)
                    return
                var lv = popup.contentItem
                lv.clip = true
                lv.implicitHeight = Qt.binding(function () {
                    return Math.min(lv.contentHeight,
                                    filterRow.comboPopupMaxRows * styles.rowHSm)
                })
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
