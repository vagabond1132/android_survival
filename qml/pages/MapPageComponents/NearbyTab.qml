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
 * 2026-10-28 #156: 标题行换成共用面板头 SheetPanelHead (标题 + 读数 + ✕ 收起一行装完),
 *   新增 foldRequested 上抛. 抽屉现在两档, 折叠态由宿主 MapBottomSheet 持有, 本 Tab 只报意图.
 * 2026-10-29 (用户问题1「有标注, 但看不到排序与信息」):
 *   ① 排序写死"按距离升序" → 三档 chips (距离/危险/最近), 同档按距离兜底;
 *   ② 标注行只报"植物/动物" → 副标题补记录时刻, 危险档单独一颗同色 Text 挂在右边;
 *   ③ 面板头读数 "N 项" → "N 标注 · M 路线", 一眼看出这屏是什么构成的.
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

    // 宿主 mapPage.mapTargets: [{id, speciesId, title, sub, category, danger, dangerLabel,
    //   time, bearing, dist, tone, lat, lon}]  (dist 单位米)
    // Tab 内不能自己写 mapPage.xxx —— id 只在定义它的文件里可见.
    property var targets: []
    property var results: []
    // 已选路线 (高亮用), 同样由宿主透传
    property var selectedRouteIds: []

    // 2026-10-29 (问题1): 排序档. 原来这一屏写死"按距离升序" —— 标注一多, 最近的
    //   那条毒蛇可能排在第 9 行, 而用户要找的正是危险度高的/刚记的那条.
    //   dist = 近的在前 (野外找最近的落脚信息), danger = 危险度高的在前,
    //   recent = 记录时刻新的在前. 后两档同分时仍按距离兜底, 不留随机序.
    property string sortBy: "dist"
    readonly property var _sorts: [
        { key: "dist",   label: "距离" },
        { key: "danger", label: "危险" },
        { key: "recent", label: "最近" }
    ]

    signal routeSelected(string routeId, var route)
    signal targetClicked(var target)
    // 2026-10-28 #156: 面板头右上那枚 ✕ 上抛"收这一档". 抽屉自己决定 folded 怎么落,
    //   Tab 只管报意图 (与 tracksClearRequested 同一口径: 不越权改宿主状态).
    signal foldRequested()

    // 抽屉展开态要按这一面的内容高来 (见 MapBottomSheet._expandedHeight).
    // 列表面要滚动空间, 直接用满 sheetExpH.
    readonly property int preferredSheetHeight: styles.sheetExpH

    // takenAt 是 Qt::ISODate ("2026-10-29T12:34:56"), 切到分钟即可 —— 行副标题是一行
    //   的宽度, 秒没有意义, 全串会把类别挤没. 认不出的形状返回空串 (不写假时刻).
    function _timeShort(v) {
        var t = String(v || "")
        if (t.length >= 16 && t.charAt(10) === "T")
            return t.substring(5, 10) + " " + t.substring(11, 16)
        return ""
    }

    // 行视图: 标注 + 路线 合成一种形状, 再按 sortBy 排
    readonly property var _rows: {
        var out = []
        var t = root.targets || []
        for (var i = 0; i < t.length; ++i) {
            var s = t[i]
            // 2026-10-29 (问题1): 副标题补危险档与记录时刻 —— 只报"植物/动物"等于
            //   没报, 同一类里毒蛇和野菜在这屏上原本长得一模一样.
            var bits = []
            if ((s.sub || "").length > 0) bits.push(s.sub)
            var stamp = root._timeShort(s.time)
            if (stamp.length > 0) bits.push(stamp)
            out.push({
                kind: "species",
                key: "sp_" + (s.id || i),
                id: s.id || "",
                speciesId: s.speciesId || "",
                title: s.title || "未命名标注",
                sub: bits.join(" · "),
                danger: (s.danger === undefined || s.danger === null) ? -1 : Number(s.danger),
                dangerLabel: s.dangerLabel || "",
                time: s.time || "",
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
                danger: -1,
                dangerLabel: "",
                time: "",
                bearing: CommonOptions.bearingDegrees(root.currentLat, root.currentLon, la, lo),
                distM: (Number(e.distance) || 0) * 1000.0,   // getNearby 返回公里
                tone: CommonOptions.colorPlum,
                icon: "hiking",
                lat: la,
                lon: lo,
                raw: e
            })
        }
        var key = root.sortBy
        out.sort(function (a, b) {
            if (key === "danger") {
                // 路线没有危险档 (-1), 自然落在后面; 同档按距离
                var dd = (Number(b.danger) || 0) - (Number(a.danger) || 0)
                if (dd !== 0) return dd
            } else if (key === "recent") {
                // ISODate 串的字典序即时间序; 路线没有记录时刻 (空串), 排最后
                var dc = String(b.time || "").localeCompare(String(a.time || ""))
                if (dc !== 0) return dc
            }
            return a.distM - b.distM
        })
        return out
    }

    // 面板头读数: "3 标注 · 5 路线" 比"8 项"能看出这一屏是什么构成的
    readonly property int _speciesCount: {
        var n = 0
        for (var i = 0; i < root._rows.length; ++i)
            if (root._rows[i].kind === "species") ++n
        return n
    }
    readonly property int _routeCount: root._rows.length - root._speciesCount

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

        // 2026-10-28 #156: SectionTitle(独立一行) → 面板头一行 (标题 + 读数 + ✕ 收起).
        //   两步路把"标题/范围/搜索/关闭"挤在同一行 44 里, 我们原来一块一行,
        //   抽屉里列表只剩 3.5 行 (pass9 ④ 那片死白的另一半).
        SheetPanelHead {
            Layout.fillWidth: true
            iconName: "explore"
            title: "盘上目标"
            trailing: root._speciesCount + " 标注 · " + root._routeCount + " 路线"
            onFoldRequested: root.foldRequested()
        }

        // 2026-10-29 (问题1): 排序 chips, 与「轨迹」Tab 同一排法 (一行放完, 不占列表高度)
        RowLayout {
            Layout.fillWidth: true
            spacing: styles.spXs

            Text {
                text: "排序"
                color: CommonOptions.colorTextDim
                font.pixelSize: styles.fsXs
            }

            Repeater {
                model: root._sorts

                delegate: Chip {
                    required property var modelData

                    Layout.preferredHeight: styles.chipH
                    text: modelData.label
                    checked: root.sortBy === modelData.key
                    accent: CommonOptions.colorAccent
                    textSize: styles.fsSm
                    onClicked: root.sortBy = modelData.key
                }
            }

            Item { Layout.fillWidth: true }
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
            // 2026-10-23 巡检 (#104 布局): 空的 ListView 依然按 fillHeight 吃掉整块
            //   高度, 于是下面的 EmptyState 被顶到 sheet 最底下, 中间一片死白 ——
            //   真机"记录/轨迹 Tab 中部大片空白"就是这个. 空的时候让位给 EmptyState
            //   (普通 visible 对 ColumnLayout 有效, 不能用 Layout.visible,
            //    见 [[qml-layout-visible-vs-row]]).
            visible: root._rows.length > 0
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
                        // 2026-10-29 (问题1): 副标题 = 类别 · 记录时刻, 右接危险档.
                        //   危险档单独一颗 Text 才有颜色位 —— 拼进同一条灰色串里,
                        //   毒蛇和野菜读起来还是一个样.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spXs

                            Text {
                                Layout.fillWidth: true
                                visible: (modelData.sub || "").length > 0
                                text: modelData.sub
                                color: CommonOptions.colorTextDim
                                font.pixelSize: styles.fsXs
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: (modelData.dangerLabel || "").length > 0
                                text: modelData.dangerLabel
                                // 与地图圆点/盘心点同一条 dangerColor, 不能红点配灰字
                                color: modelData.tone
                                font.pixelSize: styles.fsXs
                                font.bold: true
                            }
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

                // 2026-10-23 真机 (A4): 原来是 MouseArea{anchors.fill}. 它按下即拿
                //   exclusive grab, 慢速上下拖时 ListView 拿不回这个抓握 —— 18 项的列表
                //   只能看到 3.5 行, 只有快速甩动 (靠 Flickable 抢 velocity) 才滚得动.
                //   换 TapHandler: 默认 gesturePolicy = SignalsTransmitted, 不做独占抓握,
                //   行照样能点, 拖动留给列表自己 (见 [[qml-taphandler-exclusive-grab]]).
                TapHandler {
                    cursorShape: Qt.PointingHandCursor
                    onTapped: root._activate(modelData)
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
