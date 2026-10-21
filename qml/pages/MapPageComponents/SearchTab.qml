/**
 * @file SearchTab.qml
 * @brief 查找 Tab: 按城市/名称 + 类型/难度/时长 筛选 (不限位置)
 *
 * 数据源: RouteService.search(keyword) + RouteService.getByProvince + getByDifficulty
 *
 * 2026-10-19 整体改版 (props / signal / doSearch 语义不变):
 *   - 尺寸字号全换 Styles token (原 12 / 8 / 6 / 4 / 80 / 56 / 4 / 2 / 16 / 14 / 11 裸数字).
 *   - 标题 → SectionTitle, 结果行 → ListRow, 搜索按钮 → PrimaryButton,
 *     空结果 → EmptyState, 省份下拉 → FilterRow(combo 模式).
 *   - 对比度修复: "查找路线"标题与结果行标题原用 colorTextOnAccent 白字画在
 *     sheet 的 colorSurface / colorSurfaceDim 深灰底上 → colorText.
 *   - routeService 是上下文属性, 拆解构前可能为 null → 取数全部加守卫.
 *   - TextField / SpinBox 补上 token 尺寸与 colorText 前景, 不再吃 Material 默认值.
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

// delegate 里读外层 id (list / root): qmlcachegen 静态编译下没有 Bound 语义会在
// 真机静默 ReferenceError.
pragma ComponentBehavior: Bound

Item {
    id: root

    // 2026-10-16 整体改版: 尺寸/间距 token 实例 (Wave 3 逐页替换用)
    Styles { id: styles; visible: false }

    property string keyword: ""
    property string province: ""
    property int minDifficulty: 1
    property int maxDifficulty: 5
    property int maxDays: 99
    property var results: []
    property var provinces: []
    // 由宿主 (MapBottomSheet ← MapPage) 传进来的已选路线.
    // 不能在 delegate 里直接写 mapPage.selectedRouteIds: id 只在本文件内可见,
    // 跨文件引用恒为 undefined → 每次生成行都抛 ReferenceError, 列表整块空掉.
    property var selectedRouteIds: []

    signal routeSelected(string routeId, var route)

    Component.onCompleted: {
        if (routeService)
            provinces = routeService.getAvailableProvinces()
    }

    function doSearch() {
        if (!routeService) return
        if (keyword && keyword.length > 0) {
            results = routeService.search(keyword)
        } else if (province && province.length > 0) {
            results = routeService.getByProvinceAndDifficulty(
                province, minDifficulty, maxDifficulty)
        } else {
            results = routeService.getByDifficulty(minDifficulty, maxDifficulty)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: styles.spMd
        spacing: styles.spSm

        SectionTitle {
            Layout.fillWidth: true
            icon: "search"
            text: "查找路线"
            titleColor: CommonOptions.colorText
            iconColor: CommonOptions.colorAccentSoft
            pixelSize: styles.fsLg
        }

        TextField {
            id: kwField
            Layout.fillWidth: true
            Layout.preferredHeight: styles.fieldH
            placeholderText: "城市/路线名/关键词"
            placeholderTextColor: CommonOptions.colorTextDim
            color: CommonOptions.colorText
            font.pixelSize: styles.fsMd
            leftPadding: styles.spMd
            rightPadding: styles.spSm
            background: Rectangle {
                radius: styles.rMd
                color: CommonOptions.colorSurfaceDim
                border.color: CommonOptions.colorDivider
                border.width: styles.lineHair
            }
            onAccepted: { root.keyword = text; root.doSearch() }
        }

        FilterRow {
            Layout.fillWidth: true
            label: "省/市"
            labelWidth: styles.icBox
            // 2026-09-14 修: routeService.getAvailableProvinces() 已在
            // C++ 端 prepend "全部", 不要重复加 "(全部)"
            comboModel: root.provinces
            onComboActivated: (index, value) => {
                root.province = (index === 0) ? "" : value
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: styles.spXs

            Text {
                text: "难度"
                color: CommonOptions.colorTextMuted
                font.pixelSize: styles.fsSm
                Layout.preferredWidth: styles.icBox
            }
            SpinBox {
                id: minSpin
                from: 1; to: 5; value: root.minDifficulty
                // 2026-10-19 真机 (52_map_search.png): 原来给 icBox*2 = 80px, 而 Material
                //   SpinBox 左右两个指示器各占 ~48px, 中间 contentItem 被挤成 0 宽 →
                //   数字完全不显示, 只剩 "— +  — +". 宽度必须容得下 指示器×2 + 数值.
                Layout.fillWidth: true
                Layout.preferredWidth: 160
                Layout.preferredHeight: styles.rowHSm
                font.pixelSize: styles.fsSm
                onValueChanged: root.minDifficulty = value
            }
            Text {
                text: "—"
                color: CommonOptions.colorTextDim
                font.pixelSize: styles.fsMd
            }
            SpinBox {
                id: maxSpin
                from: 1; to: 5; value: root.maxDifficulty
                Layout.fillWidth: true
                Layout.preferredWidth: 160
                Layout.preferredHeight: styles.rowHSm
                font.pixelSize: styles.fsSm
                onValueChanged: root.maxDifficulty = value
            }
            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            PrimaryButton {
                text: "搜索"
                iconName: "search"
                filled: true
                tone: CommonOptions.colorAccent
                textSize: styles.fsMd
                onClicked: {
                    root.keyword = kwField.text
                    root.doSearch()
                }
            }
            Item { Layout.fillWidth: true }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: styles.spXs
            clip: true
            model: root.results

            delegate: ListRow {
                required property var modelData

                // 2026-09-15: 选中路线高亮 — 沿用原先从 mapPage.selectedRouteIds
                // 反查的绑定式写法 (选中状态变化会即时刷新行底色)
                readonly property bool picked:
                    root.selectedRouteIds.indexOf(modelData.id) >= 0

                width: list.width
                dense: true
                title: modelData.name || "(未命名)"
                titleColor: CommonOptions.colorText
                subtitle: (modelData.province || "") + " · " + (modelData.city || "")
                value: CommonOptions.difficultyLabel(modelData.difficulty || 1)
                bg: picked ? CommonOptions.colorSurfaceDim : CommonOptions.colorSurface
                // 2026-10-19: ListRow 的 value 文字吃 accent 色. 这里不能再用
                // difficultyColor() / colorAccent —— 黄绿橙蓝那几档落在 colorSurface
                // 深灰底上只有 2.7~2.9:1, 小字看不清; 换 colorAccentSoft (7.4:1),
                // 难度等级改由文字 difficultyLabel 表达.
                accent: CommonOptions.colorAccentSoft
                onClicked: root.routeSelected(modelData.id, modelData)
            }
        }

        EmptyState {
            visible: !root.results || root.results.length === 0
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            iconName: "search"
            text: "还没有搜索结果"
            hint: "换个城市或关键词, 或放宽难度后重新搜索"
            actionText: "重新搜索"
            onActionTriggered: {
                root.keyword = kwField.text
                root.doSearch()
            }
        }
    }
}
