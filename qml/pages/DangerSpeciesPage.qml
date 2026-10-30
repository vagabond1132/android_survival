/**
 * @file DangerSpeciesPage.qml
 * @brief 危险物种名录 (2026-10-20 v9 F1 目录母版, 丁骨架二级页)
 *
 * 入口: Main.qml 方位条 "warning" → navBus.navigateTo("DangerSpeciesPage", {})
 *       (⑤求助 与 ②图鉴 都进得来, 所以标题条右上要留方角返回).
 * 出口: 点行 → FieldGuideDetailPage{speciesId, preferDanger: true}.
 *
 * 数据源是 danger_species.json 的 33 条 (SpeciesService 只装这一份, 与四本图鉴的
 * 659 条是两套表; 其中 18 条同名 id 也在图鉴里, 靠 preferDanger 取毒性那份).
 * getDangerous(3) 过滤掉 1 条 L2, 本页拿到 32 条.
 *
 * 版式逐块 (同 FieldGuidePage / EquipmentPage 的目录母版):
 *   标题条 54px: DANGER 微标签 / 「危险物种」21px / 读数行 + 右上 26px 方角返回.
 *   分级图例 3 格 (致命 L5 / 高度 L4 / 中度 L3), 数字是数组计数, 同时给下面
 *            DangerChip 的颜色做图例 —— 没有图例, 那五档色阶就是装饰.
 *   目录    按类目分组: 组头 3px 类目色条 + 名称 + 等宽件数;
 *           行 = 图鉴编号 + 中文名 + 生境/海拔 + 危险度胶囊.
 *
 * 三条不能破的规则:
 *   ① 不编读数. 行上的每一条文字都来自 speciesService.getById 的现有字段
 *      (common_name / habitats / min_elevation / max_elevation / danger_level);
 *      getDangerous 只返回 4 个字段, 所以生境与海拔要逐条再取一次, 在 load() 里
 *      一次性摊平进行模型, delegate 不再打 service.
 *   ② 类目色不等于安全色. 组头的绿/蓝/橙/紫是「地物图例」的类别色 (植物=植被绿,
 *      动物=水蓝, 昆虫=火橙, 蘑菇=紫), 蛇类没有对应界门 → 用 hazard 红.
 *      危险度只由 DangerChip 表达 (色 + 文字双通道), 一行里两套语义不许互相顶.
 *   ③ 这一页只读. 处置/急救链接在③详情页, 这里不放拨号也不放"已掌握".
 */

// delegate 里要读 dangerPage 的属性与方法, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: dangerPage

    Styles { id: styles; visible: false }

    title: "危险物种"
    background: Rectangle { color: CommonOptions.colorBg }

    property var rows: []
    // head 之外的条目按危险度分桶 (图例带三格读它)
    property int n5: 0
    property int n4: 0
    property int n3: 0

    // Category 枚举序 (SpeciesService.h): 0 蛇 / 1 蘑菇 / 2 昆虫 / 3 植物 / 4 动物
    readonly property var categoryList: [
        { id: 0, name: "剧毒蛇类", tone: CommonOptions.colorHazard },
        { id: 1, name: "致命蘑菇", tone: CommonOptions.kingdomColor(3) },
        { id: 2, name: "危险虫类", tone: CommonOptions.kingdomColor(2) },
        { id: 3, name: "毒植物",   tone: CommonOptions.kingdomColor(0) },
        { id: 4, name: "危险动物", tone: CommonOptions.kingdomColor(1) }
    ]

    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }
    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }

    function _toArr(v) { return (v && v.length !== undefined) ? v : [] }

    // 生境最多取两条, 第三条起就换 "+n" —— 一行装不下四个生境, 装下了也读不完
    function habitatText(arr) {
        if (arr.length === 0) return ""
        var s = String(arr[0])
        if (arr.length > 1) s += " · " + String(arr[1])
        if (arr.length > 2) s += " +" + (arr.length - 2)
        return s
    }

    function load() {
        dangerPage.rows = []
        dangerPage.n5 = dangerPage.n4 = dangerPage.n3 = 0
        if (!speciesService) return
        var src = speciesService.getDangerous(3)
        var out = []
        // 组内顺序直接沿用 src —— C++ 侧已按 dangerLevel 倒序排过
        for (var c = 0; c < categoryList.length; ++c) {
            var members = []
            for (var k = 0; k < src.length; ++k)
                if (Number(src[k].category) === categoryList[c].id) members.push(src[k])
            if (members.length === 0) continue
            // head/item 共用一个 delegate: `visible: false` 那一支的绑定照样求值,
            // 所以两种行的字段都要齐 (10-22 巡检: 缺 tone/name/level 报 206 条).
            out.push({ kind: "head", label: categoryList[c].name,
                       tone: categoryList[c].tone, count: members.length,
                       speciesId: "", name: "", plate: "", sub: "", level: 0 })
            for (var m = 0; m < members.length; ++m) {
                var e = members[m]
                // getDangerous 不给生境与海拔, 逐条从同一 service 取齐 (规则 ①)
                var d = speciesService.getById(String(e.id))
                var lvl = Number(e.dangerLevel) || 0
                if (lvl >= 5) ++dangerPage.n5
                else if (lvl === 4) ++dangerPage.n4
                else if (lvl === 3) ++dangerPage.n3
                var hab = habitatText(_toArr(d.habitats))
                var elev = String(d.elevationRange || "")
                out.push({
                    kind: "item",
                    speciesId: String(e.id || ""),
                    name: String(e.commonName || "未命名"),
                    plate: CommonOptions.plateCode("SP", String(e.id || "")),
                    level: lvl,
                    label: "", count: 0, tone: categoryList[c].tone,
                    sub: (hab.length > 0 ? hab : "生境未标注")
                         + (elev.length > 0 ? " · " + elev : "")
                })
            }
        }
        // 兜底: 类目越界的条目也要能看见, 不能静默丢掉 (数据一旦加第 6 类就是这条)
        var known = []
        for (var z = 0; z < categoryList.length; ++z) known.push(categoryList[z].id)
        var rest = []
        for (var r = 0; r < src.length; ++r)
            if (known.indexOf(Number(src[r].category)) < 0) rest.push(src[r])
        if (rest.length > 0) {
            out.push({ kind: "head", label: "其他危险",
                       tone: CommonOptions.colorInk3, count: rest.length,
                       speciesId: "", name: "", plate: "", sub: "", level: 0 })
            for (var q = 0; q < rest.length; ++q) {
                out.push({
                    kind: "item",
                    speciesId: String(rest[q].id || ""),
                    name: String(rest[q].commonName || "未命名"),
                    plate: CommonOptions.plateCode("SP", String(rest[q].id || "")),
                    level: Number(rest[q].dangerLevel) || 0,
                    label: "", count: 0, tone: CommonOptions.colorInk3,
                    sub: "类目未归类"
                })
            }
        }
        dangerPage.rows = out
    }

    Component.onCompleted: dangerPage.load()

    readonly property int itemCount: {
        var n = 0
        for (var i = 0; i < dangerPage.rows.length; ++i)
            if (dangerPage.rows[i].kind === "item") ++n
        return n
    }
    // 图例带三格的最高档: 0 档说明这一级没有条目, 不该画一个空色块
    readonly property var scaleCells: [
        { lv: 5, label: "致命", mono: "L5", n: dangerPage.n5,
          tone: CommonOptions.dangerColor(5) },
        { lv: 4, label: "高度", mono: "L4", n: dangerPage.n4,
          tone: CommonOptions.dangerColor(4) },
        { lv: 3, label: "中度", mono: "L3", n: dangerPage.n3,
          tone: CommonOptions.dangerColor(3) }
    ]

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- 标题条 (54px: 微标签 / 页名 / 读数行, 右上 26px 方角返回) ---
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
                    text: "危险度"
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: "危险物种"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: dangerPage.itemCount + " 条 · 危险度 3 级以上 · 点行看识别与处置"
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
                    onClicked: dangerPage.goBack()
                }
            }
        }

        // --- 危险度图例 (三格, 兼作下面色阶的钥匙) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: scaleCol.implicitHeight + 2 * styles.spSm
            Layout.topMargin: styles.spSm
            visible: dangerPage.itemCount > 0
            color: CommonOptions.colorSurface

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorRule
            }

            ColumnLayout {
                id: scaleCol
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
                        text: "危险度标尺"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "色 = 危险度 · 组头色 = 类目"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: dangerPage.scaleCells
                        delegate: RowLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 0
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
                                    text: String(modelData.n)
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fs2xl
                                    color: modelData.n > 0 ? modelData.tone
                                                           : CommonOptions.colorInk3
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    // 档位是拉丁, 汉字标签另起一个 Text: monoFont 里没有
                                    // CJK 字形 (见 [[qml-monofont-no-cjk]])
                                    Text {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: modelData.mono
                                        font.family: styles.monoFont
                                        font.pixelSize: styles.fsXs
                                        font.letterSpacing: 1.2
                                        color: CommonOptions.colorInk3
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        font.pixelSize: styles.fsXs
                                        color: CommonOptions.colorTextMuted
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- 目录 ---
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: styles.spSm
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin

            ListView {
                id: dangerList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: dangerPage.rows
                visible: dangerPage.itemCount > 0

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: dangerList.width
                    height: modelData.kind === "head" ? 30 : styles.rowH

                    MouseArea {
                        anchors.fill: parent
                        enabled: modelData.kind === "item"
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dangerPage.navigateTo(
                                       "FieldGuideDetailPage",
                                       { speciesId: modelData.speciesId,
                                         preferDanger: true })
                    }

                    // 组头: 3px 类目色条 (规则 ②) + 名称 + 件数
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
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
                            text: modelData.count + " 项"
                            font.pixelSize: styles.fsXs
                            color: CommonOptions.colorInk3
                        }
                    }

                    // 条目行: 编号 / 名称 + 生境海拔 / 危险度胶囊
                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: styles.spSm
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
                                font.pixelSize: styles.fsMd
                                font.bold: true
                                color: CommonOptions.colorText
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
                        DangerChip {
                            Layout.alignment: Qt.AlignVCenter
                            level: modelData.level
                            compact: true
                        }
                    }

                    Rectangle {
                        visible: modelData.kind === "item" && !dangerPage._nextIsHead(index)
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
                visible: dangerPage.itemCount === 0
                iconName: "dangerspecies"
                text: "危险物种库没有取到"
                hint: speciesService
                      ? ("danger_species.json 读回来 0 条 (totalCount="
                         + speciesService.totalCount + ")")
                      : "物种服务还没就绪"
                actionText: "重新加载"
                onActionTriggered: dangerPage.load()
            }
        }
    }

    // 组头下面不画底线, 免得标题被压成一行数据
    function _nextIsHead(i) {
        var n = dangerPage.rows[i + 1]
        return !!n && n.kind === "head"
    }

    Connections {
        target: speciesService
        function onDataChanged() { dangerPage.load() }
    }
}
