/**
 * @file FieldGuidePage.qml
 * @brief 动植物图鉴主页 (2026-09-14 UI 改版)
 *
 * 改进:
 *   - 顶部 hero 渐变 (森林绿主题)
 *   - 筛选区: 卡片化, 圆角 12
 *   - 列表项: 保留危险等级圆圈 + 学名 + 分布/月份
 *   - 蘑菇警告行 token 化
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: fieldGuidePage
    title: "动植物图鉴"
    property int currentKingdom: 0   // 0=植物 1=动物 2=昆虫 3=蘑菇
    // 2026-09-21: 修 - 之前默认是当前月 (如 9 月), 若数据库里 9 月数据稀疏
    //   (或季节性物种 9 月无), 列表直接为空, 用户报"动植物图鉴无数据".
    //   改为默认 0 = 全部月份, getByProvince 时跳过月份过滤.
    property int currentMonth: 0
    property string currentProvince: "全部"

    property int cardHeight: currentKingdom === 3 ? 110 : 90

    readonly property var kingdomOptions: [
        { value: 0, label: "\ue406 植物" },
        { value: 1, label: "\ue91a 动物" },
        { value: 2, label: "\ue1b9 昆虫" },
        { value: 3, label: "\ue239 蘑菇" }
    ]

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    // 2026-09-24: 省份下拉之前取 routeService.getAvailableProvinces() (全国 34 项),
    //   与图鉴数据实际分布 (山东/山西/河北/河南 + 全国 + 少数南方/西部省份) 完全脱节,
    //   且后端用精确相等匹配 → 选了省份列表骤减甚至为空. 改为:
    //   1) 省份列表用当前 kingdom 自己 service 的 getAvailableProvinces();
    //   2) 后端 FieldGuideIndex::matchProvince 做包含式 + "全国*" 通配.
    function rebuildProvinces() {
        var svc = speciesServiceRegistry.serviceOf(currentKingdom)
        provinceComboModel.clear()
        provinceComboModel.append({ "name": "全部" })
        if (!svc || typeof svc.getAvailableProvinces !== "function") return
        var provs = svc.getAvailableProvinces()
        for (var i = 0; i < provs.length; i++) {
            provinceComboModel.append({ "name": provs[i] })
        }
    }

    function loadData() {
        // 2026-09-21: currentMonth = 0 表示"全部月份", 调用 getAll(); 否则按月过滤.
        var svc = speciesServiceRegistry.serviceOf(currentKingdom)
        if (!svc) return
        if (currentProvince === "全部" && currentMonth === 0) {
            listModel.service = svc
            listModel.method = "getAll"
            listModel.args = []
        } else if (currentProvince === "全部") {
            listModel.service = svc
            listModel.method = "getByMonth"
            listModel.args = [currentMonth]
        } else if (currentMonth === 0) {
            listModel.service = svc
            listModel.method = "getByProvince"
            listModel.args = [currentProvince]
        } else {
            listModel.service = svc
            listModel.method = "getByProvinceAndMonth"
            listModel.args = [currentProvince, currentMonth]
        }
        listModel.refresh()
        Qt.callLater(function() { listModel.refresh() })
    }

    // 2026-09-20: ServiceListModel 由 Page 持有, ListView 直接 model: listModel
    ServiceListModel {
        id: listModel
    }
    ListModel { id: provinceComboModel }

    Component.onCompleted: {
        rebuildProvinces()
        loadData()
    }

    onCurrentKingdomChanged: {
        // 2026-09-24: 换 kingdom 后原省份可能在该类数据中不存在 → 重置为 "全部"
        fieldGuidePage.currentProvince = "全部"
        rebuildProvinces()
        loadData()
    }
    onCurrentMonthChanged: loadData()
    onCurrentProvinceChanged: loadData()

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

                Text {
                    text: "\ue54e"  // Material Icons: menu_book
                    font.family: "Material Icons"
                    font.pixelSize: 32
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "动植物图鉴"
                        color: "white"
                        font.pixelSize: styles.fs2xl
                        font.bold: true
                    }
                    Text {
                        // 2026-09-23: 修 - 去掉 "鲁晋冀豫" 4 字 (山东/山西/河北/河南
                        //   北方 4 省) 地域偏向. 改为全国通用描述, 数据后续会扩展
                        //   南方 (云贵川/两湖/两广) 与西部 (青藏/新疆) 物种.
                        // 2026-10-08: 数字改为 assets/data/*.json 实际条目数
                        //   (339 植物 / 139 动物 / 114 昆虫 / 67 蘑菇). 第四轮扩充后同步.
                        text: "全国常见 339 植物 + 139 动物 + 114 昆虫 + 67 蘑菇 (持续扩展中)"
                        color: "#B0BEC5"
                        font.pixelSize: styles.fsSm
                    }
                }
            }
        }

        // === 筛选区 (卡片) ===
        Rectangle {
            Layout.fillWidth: true
            Layout.margins: styles.spLg
            Layout.topMargin: styles.spLg
            Layout.preferredHeight: filterCol.implicitHeight + 24
            color: CommonOptions.colorSurface
            radius: styles.rLg
            border.color: Qt.darker(CommonOptions.colorSurface, 1.2)
            border.width: 1
            clip: false

            ColumnLayout {
                id: filterCol
                anchors.fill: parent
                anchors.margins: styles.spMd
                spacing: styles.spSm

                // 类型
                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Text {
                        text: "类型"
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                        Layout.preferredWidth: 40
                    }
                    ComboBox {
                        id: kingdomCombo
                        Layout.fillWidth: true
                        model: fieldGuidePage.kingdomOptions
                        textRole: "label"
                        valueRole: "value"
                        // 2026-09-30: 修 - label 用 PUA 码位 (\ue406 植物 等),
                        //   但 ComboBox 未指定字体 → 默认字体无该 PUA 字形 →
                        //   真机上图标显示为方框/空白. Material Icons 字体已由
                        //   qrc 打包并在 Main.qml 用 FontLoader 注册, 这里补 family
                        //   即可让 contentItem(Text) 与弹出列表 delegate(ItemDelegate)
                        //   都走该字体 (两者都 font: control.font).
                        font.family: "Material Icons"
                        currentIndex: fieldGuidePage.currentKingdom
                        onActivated: fieldGuidePage.currentKingdom = currentValue
                    }
                }

                // 省份 + 月份
                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Text {
                        text: "省份"
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                        Layout.preferredWidth: 40
                    }
                    ComboBox {
                        id: provinceCombo
                        Layout.fillWidth: true
                        model: provinceComboModel
                        textRole: "name"
                        currentIndex: {
                            for (var i = 0; i < provinceComboModel.count; i++) {
                                if (provinceComboModel.get(i).name === fieldGuidePage.currentProvince) return i
                            }
                            return 0
                        }
                        onActivated: fieldGuidePage.currentProvince = provinceComboModel.get(currentIndex).name
                    }
                }
                // 月份 (2026-09-21: 加"全部"选项, value=0 表示不过滤; 之前默认当前月
                //   导致 9 月稀疏月份下列表空白)
                // 2026-09-23: 修 - CommonOptions.monthOptions() 已经在第 0 位返回
                //   "全部" (value=0), FieldGuidePage 之前再 concat 一个 "全部"
                //   → ComboBox 显示两个 "全部" 选项. 直接用 CommonOptions 的返回值.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Text {
                        text: "月份"
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                        Layout.preferredWidth: 40
                    }
                    ComboBox {
                        id: monthCombo
                        Layout.fillWidth: true
                        model: CommonOptions.monthOptions()
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: {
                            var opts = CommonOptions.monthOptions()
                            for (var i = 0; i < opts.length; i++) {
                                if (opts[i].value === fieldGuidePage.currentMonth) return i
                            }
                            return 0
                        }
                        onActivated: fieldGuidePage.currentMonth = currentValue
                    }
                }

                // 计数
                Text {
                    text: "\ue01d 共 " + (listModel.count || 0) + " 条"  // Material Icons: equalizer
                    font.family: "Material Icons"
                    color: CommonOptions.colorTextMuted
                    font.pixelSize: styles.fsSm
                }
            }
        }

        // 蘑菇安全警告
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: styles.spLg
            Layout.rightMargin: styles.spLg
            visible: fieldGuidePage.currentKingdom === 3
            Layout.preferredHeight: visible ? 48 : 0
            color: CommonOptions.colorDanger
            radius: styles.rMd

            Text {
                anchors.fill: parent
                anchors.margins: 8
                text: mushroomService ? mushroomService.safetyWarning() : "\ue002 蘑菇风险极高,仅作信息展示。"
                font.family: "Material Icons"
                color: "white"
                font.pixelSize: styles.fsSm
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }
        }

        // 卡片列表
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: styles.spLg
            Layout.topMargin: fieldGuidePage.currentKingdom === 3 ? styles.spSm : 0
            model: listModel
            clip: true
            spacing: styles.spSm

            delegate: Rectangle {
                width: ListView.view.width
                height: fieldGuidePage.cardHeight
                radius: styles.rMd
                color: CommonOptions.colorSurface
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spSm
                    spacing: styles.spSm

                    // 危险等级圆圈
                    Rectangle {
                        Layout.preferredWidth: 50
                        Layout.fillHeight: true
                        radius: 25
                        // 2026-09-21 UI 统一: 危险等级色改用 CommonOptions token (删 #FF9800/#FFC107 硬编码)
                        color: model.dangerLevel >= 4 ? CommonOptions.colorDanger :
                               model.dangerLevel >= 3 ? CommonOptions.colorWarn :
                               model.dangerLevel >= 1 ? "#FFB300" : CommonOptions.colorSuccess

                        Text {
                            anchors.centerIn: parent
                            text: model.dangerLevel >= 4 ? "\ue1db" :  // skull/crossbones
                                  model.dangerLevel >= 3 ? "\ue002" :  // warning
                                  model.dangerLevel >= 1 ? "!" : "\ue5ca"  // check
                            font.family: "Material Icons"
                            color: "white"
                            font.pixelSize: 24
                            font.bold: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: model.commonName || "未知"
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsLg
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: model.scientificName || ""
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsXs
                            font.italic: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: (model.distribution && model.distribution.length > 0
                                   ? "\ue0c8 " + model.distribution.join("/")
                                   : "")
                                  + "  \ue5d3 "
                                  + (model.activeMonths && model.activeMonths.length > 0
                                     ? model.activeMonths.join("、") + " 月"
                                     : "全年")
                            font.family: "Material Icons"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsXs
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Text {
                        text: "›"
                        color: "#607D8B"
                        font.pixelSize: 22
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // 2026-09-19: 改传 entityId (而非 entity model), 让详情页用
                        //   service 重新拉取完整数据, 避免 ListModel role 化导致
                        //   嵌套数组 (ediblePart / lookAlike[fieldMap]) 丢失.
                        fieldGuidePage.ApplicationWindow.window.navBus.navigateTo("FieldGuideDetailPage", {
                            entityId: model.id,
                            kingdomIndex: fieldGuidePage.currentKingdom
                        })
                    }
                }
            }
        }
    }

    // 详情页(动态加载)
    Loader {
        id: fieldGuideDetailLoader
        z: 100
        anchors.fill: parent
        visible: status == Loader.Ready && item !== null
        active: false

        function setEntity(entity) {
            fieldGuideDetailLoader._entity = entity
            sourceComponent = fieldGuideDetailComp
            active = true
        }
        function open() { if (item) item.opened = true }
        function close() { active = false; fieldGuideDetailLoader._entity = null }

        property var _entity: null

        sourceComponent: fieldGuideDetailComp

        Component {
            id: fieldGuideDetailComp
            FieldGuideDetailPage {
                entity: fieldGuideDetailLoader._entity
                kingdomIndex: fieldGuidePage.currentKingdom
                onCloseRequested: fieldGuideDetailLoader.close()
            }
        }
    }
}
