/**
 * @file NearbyTab.qml
 * @brief 「目标」Tab: 以地图中心为盘心, 把物种标注 + 附近路线排成一条按距离升序的列
 *
 * 文件名留 NearbyTab 没改: 它已经注册在 OutdoorSurvival 1.0 (CMakeLists QML_FILES),
 * 改名要同时动 CMake + qmldir + MapBottomSheet 实例化, 换不来任何功能. 只把标题改成
 * 「盘上目标」—— 这一屏读的是"我看的这个点周围有什么", 不是"我在哪的附近".
 *
 * 2026-10-20 #61 整体改版 (原 周边 Tab = 半径筛选 + 路线列表):
 *   ① 两栏并排 → 一条列表. 原来物种标注只在罗盘上画点没有文字行, 想定位某个标注
 *      只能在那圈像素里猜; 现在标注和路线进同一条 按距离排序 的列表, 丁的排法
 *      ("资源不按字母/目录排, 按离你多远排") 才落到这屏.
 *      距离单位统一成米: mapTargets 给米 (CommonOptions.distanceMeters),
 *      getNearby 的 distance 是公里, 直接混着排会让路线永远排在标注前面.
 *   ② 文字颜色: 原标题与两行文案都用 colorTextOnAccent —— 白字只允许出现在饱和填充上,
 *      画在 sheet 的 colorSurface 浅灰底上等于没写 (③详情页同一处坑). 换 colorText /
 *      colorTextMuted / colorTextDim.
 *   ③ 裸数字 (12/10/56/4/16/14/11/2/120) → styles token; 方位列交给 BearingCell.
 *   ④ 删掉「刷新」按钮和 难度/时长 两个筛选属性: 它们从来没参与过过滤 (原代码里
 *      minDifficulty/maxDays 声明了但 refresh() 从不读), 属于抄来的控件. 查询本来
 *      就跟着 中心点 与 半径 的变化自动重跑, 手动刷新没有意义.
 *   ⑤ 中心点用 (0,0) 判定"还没定位" —— MapPage 传下来的是 viewLat/viewLon (地图可视
 *      中心), 无 GPS 时它是默认北京, 这一条挡不住假坐标; 但挡住"抽屉刚建好还没绑上"
 *      的瞬间空查询.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: root

    Styles { id: styles; visible: false }

    // 盘心 = 地图可视中心 (MapPage 透传, 不是 GPS 位置)
    property real currentLat: 0
    property real currentLon: 0
    property int radiusKm: 50

    // 宿主 mapPage.mapTargets: [{id, speciesId, title, sub, bearing, dist, tone, lat, lon}]
    // dist 单位米. Tab 内不能自己写 mapPage.xxx —— id 只在定义它的文件里可见.
    property var targets: []
    property var results: []
    // 已选路线 (高亮用), 同样由宿主透传
    property var selectedRouteIds: []

    signal routeSelected(string routeId, var route)
    signal targetClicked(var target)

    // 行视图: 标注 + 路线 合成一种形状, 再按离盘心的距离排
    readonly property var _rows: {
        var out = []
        var t = root.targets || []
        for (var i = 0; i < t.length; ++i) {
            var s = t[i]
            out.push({
                kind: "species",
                key: "sp_" + (s.id || i),
                id: s.id || "",
                speciesId: s.speciesId || "",
                title: s.title || "未命名标注",
                sub: s.sub || "",
                bearing: Number(s.bearing) || 0,
                distM: Number(s.dist) || 0,
                tone: s.tone,
                icon: "place",
                lat: Number(s.lat),
                lon: Number(s.lon)
            })
        }
        var r = root.results || []
        for (var j = 0; j < r.length; ++j) {
            var e = r[j]
            var la = Number(e.trailheadLat), lo = Number(e.trailheadLon)
            if (!isFinite(la) || !isFinite(lo)) continue
            out.push({
                kind: "route",
                key: "rt_" + (e.id || j),
                id: e.id || "",
                title: e.name || "(未命名路线)",
                sub: (e.province || "") + " · " + CommonOptions.difficultyLabel(e.difficulty || 1)
                     + " · 全长 " + CommonOptions.formatDistance(Number(e.distanceKm) || 0),
                bearing: CommonOptions.bearingDegrees(root.currentLat, root.currentLon, la, lo),
                distM: (Number(e.distance) || 0) * 1000.0,   // getNearby 返回公里
                tone: CommonOptions.colorPlum,
                icon: "hiking",
                lat: la,
                lon: lo,
                raw: e
            })
        }
        out.sort(function (a, b) { return a.distM - b.distM })
        return out
    }

    function refresh() {
        if (!routeService) { root.results = []; return }
        // (0,0): 抽屉刚实例化、宿主还没把 viewLat/viewLon 绑下来的瞬间
        if (root.currentLat === 0 && root.currentLon === 0) { root.results = []; return }
        var res = routeService.getNearby(root.currentLat, root.currentLon, root.radiusKm)
        root.results = res || []
    }

    function _activate(row) {
        if (row.kind === "route") root.routeSelected(row.id, row.raw)
        else root.targetClicked(row)
    }

    onCurrentLatChanged: refresh()
    onCurrentLonChanged: refresh()
    onRadiusKmChanged: refresh()
    Component.onCompleted: refresh()

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: styles.pageMargin
        anchors.rightMargin: styles.pageMargin
        anchors.topMargin: styles.spSm
        anchors.bottomMargin: styles.spSm
        spacing: styles.spSm

        SectionTitle {
            Layout.fillWidth: true
            icon: "explore"
            text: "盘上目标"
            trailing: root._rows.length + " 项"
            titleColor: CommonOptions.colorText
            iconColor: CommonOptions.colorAccentSoft
            pixelSize: styles.fsLg
        }

        // 盘心读数: 汉字标签走默认字体, 数字走 monoFont (混进汉字会回退失败出方框)
        RowLayout {
            Layout.fillWidth: true
            spacing: styles.spXs
            Text {
                text: "盘心"
                color: CommonOptions.colorTextDim
                font.pixelSize: styles.fsXs
            }
            Text {
                text: (root.currentLat === 0 && root.currentLon === 0)
                      ? "--"
                      : root.currentLat.toFixed(4) + ", " + root.currentLon.toFixed(4)
                font.family: styles.monoFont
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorTextMuted
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        FilterRow {
            Layout.fillWidth: true
            label: "半径"
            labelWidth: styles.icBoxSm
            stepperValue: root.radiusKm + " km"
            stepperMinusEnabled: root.radiusKm > 10
            stepperPlusEnabled: root.radiusKm < 500
            onStepperMinus: root.radiusKm = Math.max(10, root.radiusKm - 10)
            onStepperPlus: root.radiusKm = Math.min(500, root.radiusKm + 10)
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: styles.cardGap
            clip: true
            model: root._rows

            delegate: Rectangle {
                required property var modelData

                readonly property bool picked:
                    modelData.kind === "route"
                    && root.selectedRouteIds.indexOf(modelData.id) >= 0

                width: list.width
                height: styles.rowHTall
                radius: styles.rSm
                color: picked ? CommonOptions.colorSurfaceDim : CommonOptions.colorSurface
                border.color: picked ? CommonOptions.colorAccent : CommonOptions.colorDivider
                border.width: picked ? styles.lineAccent : styles.lineHair

                Rectangle {
                    id: bearingStrip
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: styles.bearingColW
                    color: CommonOptions.withAlpha(modelData.tone, 0.14)

                    BearingCell {
                        anchors.centerIn: parent
                        icon: modelData.icon
                        tone: modelData.tone
                        bearing: modelData.bearing
                        showCompass: true
                    }
                }

                RowLayout {
                    anchors.left: bearingStrip.right
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: styles.spSm
                    spacing: styles.spSm

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: CommonOptions.colorText
                            font.pixelSize: styles.fsMd
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: (modelData.sub || "").length > 0
                            text: modelData.sub
                            color: CommonOptions.colorTextDim
                            font.pixelSize: styles.fsXs
                            elide: Text.ElideRight
                        }
                    }

                    // 距离: 纯 ASCII ("620 m" / "1.4 km") → 可以进等宽列
                    Text {
                        text: CommonOptions.formatBearingDistance(modelData.distM)
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsSm
                        color: modelData.tone
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._activate(modelData)
                }
            }
        }

        EmptyState {
            visible: root._rows.length === 0
            Layout.fillWidth: true
            iconName: "explore"
            text: "盘上没有目标"
            hint: "拖动地图换一处, 或在「记录」里拍照标注"
        }
    }
}
