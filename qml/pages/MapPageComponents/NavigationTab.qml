/**
 * @file NavigationTab.qml
 * @brief 「轨迹」Tab: 历史轨迹列表 (搜索 + 排序 + 折叠空轨迹), 点击加载到地图 / 行右分析方块进详情
 *
 * 2026-09-14: P1 增加 "分析" 按钮, 点击 push 到 TrackDetailPage 看详细统计/曲线
 * 2026-10-20 #61 整体改版 (props / signal / refresh 语义不变):
 *   ① 行布局 → ListRow. 原来每行手抄 Rectangle + RowLayout + 两个 Text, 标题白字
 *      (colorTextOnAccent) 画在 colorSurface 浅灰底上 —— sheet 里三处同一个坑.
 *   ② 裸数字 (12/8/64/40/4/2/8/16/14/11/18) → styles token.
 *   ③ 距离换算不再绕 mapService.formatDistance (上下文属性, 拆解构前为 null 会抛),
 *      改 CommonOptions.formatDistance(totalDistanceM / 1000) —— 单例, 恒可用.
 *   ④ 选中高亮的 border.width 从 2 收成 styles.lineAccent (3px 强调线的语义),
 *      未选中给 colorDivider 描边而不是 transparent: 行与行之间原本只靠底色差,
 *      在强阳光下糊成一片.
 * 2026-10-23 #109 真机 (轨迹 Tab):
 *   ① 行标题不再透出老轨迹落盘的 UTC 原始 ISO 名 (_titleOf 识别后换本地时间),
 *      标题带时间时副标题去掉冗余的「起点 …」; 导入名 (GPX/KML) 原样保留.
 *   ② delegate 根节点从 RowLayout 换成 Rectangle + 内层 anchors.fill 布局,
 *      并给 ListView 兜一层 Layout.minimumHeight —— 治「盘上只有 1 条轨迹时
 *      列表区整块空白」(同文件 NearbyTab 的 Rectangle delegate 是真机验证过的).
 *   ③ 标题行补「清空」OutlineButton + tracksClearRequested 信号: 原来「已加载」
 *      只是状态读数, 选中之后没有任何取消/清线入口.
 * 2026-10-29 #170 (用户指定文案): 行尾读数「已画线」→「已加载」。这一枚说的是
 *   "这条轨迹的数据进了地图", 不保证真画得出一根线 (不足两点的线 MapPolyline 不画),
 *   旧文案把状态说成了结果. 全站只有这一处是给用户看的字, 其余同词都在注释里.
 * 2026-10-28 #156 按两步路工作台改版:
 *   ① SectionTitle + 三颗按钮 (导入/刷新/清空) → SheetPanelHead 一行 (标题 + 条数 +
 *      内嵌名称搜索 + ✕ 收起), 三个动作下移到底部动作带. 三颗按钮挤在标题行右半边,
 *      把 44 高的一行变成"标题只剩 5 个字", 抽屉里列表本来就只有 3.5 行 (pass9 ④).
 *   ② 排序 chips (综合=时间新在前 / 里程 / 爬升 / 点数). 稿子里还有「耗时」那一档,
 *      但 getAllTracks() 没有时长字段 —— 不给假读数, 这一档不做.
 *   ③ 「分析」方块从 RowLayout 里挪进 anchors: 方块永远钉在行的右缘, 标题再长也顶不出去.
 *   ④ 0 点轨迹 (导入失败/空记录) 默认折叠成一条读数, 点击展开 —— 库里 755 条里有一批
 *      0 点的, 混在列表里既点不出线又让"多少条"这个读数失真.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: root

    Styles { id: styles; visible: false }

    property var tracks: []
    // 由宿主传进来的已选轨迹 —— delegate 里不能写 mapPage.xxx: id 跨文件不可见,
    // 恒为 undefined, 每生成一行都抛 ReferenceError, 列表整块空掉.
    property var selectedTrackIds: []

    signal trackSelected(string trackId, var track)
    signal trackAnalyzeRequested(string trackId)  // 2026-09-14: P1 新增
    signal trackImportRequested()                 // 2026-10-09: 导入 GPX/KML/CSV 入口
    // 2026-10-23 #109: 清空已加载的轨迹. 无参 —— 本 Tab 只上报意图, 清 selectedTrackIds
    //   和抹掉地图上的线归宿主 (MapBottomSheet → MapPage) 做, 这里不越权.
    signal tracksClearRequested()
    // 2026-10-28 #156: 面板头那枚 ✕ / 动作带的「收起」都只报意图, 折叠态归抽屉.
    signal foldRequested()

    // 抽屉展开态按这一面报的高度来 (见 MapBottomSheet._expandedHeight). 列表面要滚动空间.
    readonly property int preferredSheetHeight: styles.sheetExpH

    // 排序档: recent=新在前 (综合), distance, gain, points
    property string sortBy: "recent"
    // 0 点轨迹默认折叠, 点开才进列表
    property bool showEmptyTracks: false

    readonly property var _sorts: [
        { key: "recent",   label: "综合" },
        { key: "distance", label: "里程" },
        { key: "gain",     label: "爬升" },
        { key: "points",   label: "点数" }
    ]

    // 底部动作带的数据. 「清空」没有已加载轨迹时是 disabled (灰着但看得见),
    // 比"整颗按钮消失"诚实 —— 用户知道有这个动作, 只是现在用不上.
    // 图标只能用 IconLabel._iconMap 里有的码位: layers_clear 那枚字体里没有,
    // 写上去是空白格 + 运行期 console.warn, 所以用 delete.
    readonly property var _bandActions: [
        { key: "import", icon: "note_add",      label: "导入",  tone: "prime" },
        { key: "refresh", icon: "refresh",      label: "刷新" },
        { key: "clear",  icon: "delete",        label: "清空",
          enabled: root.selectedTrackIds.length > 0 },
        { key: "fold",   icon: "expand_more",   label: "收起" }
    ]

    function _onBandAction(key) {
        if (key === "import") root.trackImportRequested()
        else if (key === "refresh") root.refresh()
        else if (key === "clear") root.tracksClearRequested()
        else if (key === "fold") root.foldRequested()
    }

    Component.onCompleted: refresh()

    // 2026-10-09: 监听全局 dataChanged (导入/删除轨迹后 MapService 已 emit) → 自查刷新.
    Connections {
        target: mapService
        function onDataChanged() { root.refresh() }
    }

    function refresh() {
        if (!mapService) { root.tracks = []; return }
        var t = mapService.getAllTracks()
        root.tracks = t || []
    }

    // 2026-10-27 #134: 没有开始时间就返回空串, 由调用方把这一整段省掉.
    //   原来这里回 "无开始时间", 于是导入一条没带时刻的 GPX/CSV, 行副标题变成
    //   "起点 无开始时间 · 6.2 km · 1 200 点" —— 占位文本读起来像数据出了问题,
    //   而"不给假读数"的口径是未知就不出现 (见 TrackDetailPage 的起点读数).
    function _startLabel(s) {
        var t = String(s || "")
        // MapService 写的是 Qt::ISODate ("2026-10-20T12:34:56"). 直接切字符串比
        // new Date() 解析稳 (导入的 GPX 时间戳格式五花八门, 解析失败会得到 NaN).
        if (t.length >= 16 && t.charAt(10) === "T") {
            return t.substring(5, 10) + " " + t.substring(11, 16)
        }
        return t
    }

    // 2026-10-23 #109: 是不是自动生成的名字 (标题已含时间, 副标题就不必再报「起点」).
    // 老 RecordTab 落盘的是 UTC 原始 ISO ("轨迹 2026-10-22T01:31:46"), 新版是本地的
    // "轨迹 10-22 09:31"; 用户从 GPX/KML 导入的真名字不匹配这两种, 一律原样保留.
    function _isGeneratedName(name) {
        var n = String(name || "")
        return /^轨迹\s*\d{4}-\d{2}-\d{2}T/.test(n)
               || /^轨迹\s*\d{2}-\d{2}\s\d{2}:\d{2}$/.test(n)
    }

    // 老名字里的 UTC 串是落盘时写死的, 改不动数据; 显示侧兜底: 认出 UTC 形状就用
    // 本地 startTime 重排, 免得标题 01:31 和副标题 09:31 差 8 小时自相矛盾.
    function _titleOf(track) {
        var n = String(track && track.name ? track.name : "")
        if (/^轨迹\s*\d{4}-\d{2}-\d{2}T/.test(n)) {
            var stamp = root._startLabel(track.startTime)
            return stamp.length > 0 ? "轨迹 " + stamp : "轨迹"
        }
        return n.length > 0 ? n : "(未命名轨迹)"
    }

    // 标题带时间的行, 副标题只剩距离 + 点数; 导入名的行标题没时间, 副标题保「起点」
    // 不让信息变少; 起点也未知时那一段整条不出现, 只留距离 + 点数.
    function _subtitleOf(track) {
        var stat = CommonOptions.formatDistance(Number(track.totalDistanceM || 0) / 1000.0)
                   + " · " + (track.pointCount || 0) + " 点"
        if (root._isGeneratedName(track.name)) {
            return stat
        }
        var stamp = root._startLabel(track.startTime)
        if (stamp.length === 0) return stat
        return "起点 " + stamp + " · " + stat
    }

    // === 视图: 名称过滤 → 折叠 0 点 → 排序 ==================================
    readonly property var _named: {
        var kw = String(panelHead.searchText || "").trim().toLowerCase()
        var all = root.tracks || []
        var out = []
        for (var i = 0; i < all.length; ++i) {
            var t = all[i]
            if (kw.length > 0
                && String(root._titleOf(t)).toLowerCase().indexOf(kw) < 0) continue
            out.push(t)
        }
        return out
    }

    readonly property int _emptyCount: {
        var n = 0
        for (var i = 0; i < _named.length; ++i) {
            if (Number(_named[i].pointCount || 0) <= 0) ++n
        }
        return n
    }

    readonly property var _rows: {
        var src = root._named
        var out = []
        for (var i = 0; i < src.length; ++i) {
            var t = src[i]
            if (!root.showEmptyTracks && Number(t.pointCount || 0) <= 0) continue
            out.push(t)
        }
        var key = root.sortBy
        out.sort(function (a, b) {
            if (key === "distance") return Number(b.totalDistanceM || 0) - Number(a.totalDistanceM || 0)
            if (key === "gain")     return Number(b.elevationGainM || 0) - Number(a.elevationGainM || 0)
            if (key === "points")   return Number(b.pointCount || 0) - Number(a.pointCount || 0)
            // 综合 = 新在前. startTime 是 Qt::ISODate 字符串, 字典序即时间序
            return String(b.startTime || "").localeCompare(String(a.startTime || ""))
        })
        return out
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: styles.pageMargin
        anchors.rightMargin: styles.pageMargin
        anchors.topMargin: styles.spXs
        anchors.bottomMargin: styles.spSm
        spacing: styles.spSm

        SheetPanelHead {
            id: panelHead
            Layout.fillWidth: true
            iconName: "timeline"
            title: "轨迹"
            trailing: root._rows.length + " 条"
            searchPlaceholder: "搜索轨迹名称"
            onFoldRequested: root.foldRequested()
        }

        // 排序 chips: 一行放完, 不占列表高度以外的空间
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

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            // 空列表按 fillHeight 吃满整块, EmptyState 被顶到最底下, 中间一片死白
            // (同 NearbyTab/SearchTab 的口径: 普通 visible 让位, 不能用 Layout.visible).
            visible: root._rows.length > 0
            // 2026-10-23 #109: 只有 1 条轨迹时真机整块空白 —— 有内容就至少撑出一行高度.
            Layout.minimumHeight: styles.rowHTall
            spacing: styles.cardGap
            clip: true
            model: root._rows

            delegate: Rectangle {
                required property var modelData

                readonly property bool picked:
                    root.selectedTrackIds.indexOf(modelData.id) >= 0

                width: list.width
                height: styles.rowHTall
                color: "transparent"

                // 2026-10-28 #156: 「分析」方块改 anchors 钉右缘. 原来它和 ListRow 同在一个
                //   RowLayout 里, 长标题把方块顶出行外 (pass9 ③) —— Layout 把子项的
                //   implicitWidth 当最小宽度, 顶出去是必然; 锚定之后方块的位置跟内容无关.
                // 2026-10-28 控件盘点: 手搓 Rectangle + MouseArea 换成 IconActionCell ——
                //   那颗 MouseArea 按下即独占抓握, 轨迹列表一长就在行里拖不动 (#105 同族).
                IconActionCell {
                    id: analyzeBox

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    cellSize: styles.icBoxSm
                    iconName: "equalizer"
                    tone: CommonOptions.colorAccentSoft
                    onTriggered: root.trackAnalyzeRequested(modelData.id)
                }

                ListRow {
                    anchors.left: parent.left
                    anchors.right: analyzeBox.left
                    anchors.rightMargin: styles.spXs
                    anchors.verticalCenter: parent.verticalCenter
                    dense: true
                    showChevron: false
                    title: root._titleOf(modelData)
                    titleColor: CommonOptions.colorText
                    subtitle: root._subtitleOf(modelData)
                    value: picked ? "已加载" : ""
                    accent: CommonOptions.colorAccentSoft
                    bg: picked ? CommonOptions.colorSurfaceDim : CommonOptions.colorSurface
                    onClicked: root.trackSelected(modelData.id, modelData)
                }
            }
        }

        // 0 点轨迹的折叠读数: 库里有一批导入后 0 点的记录, 点不出线也不该混在列表里
        Rectangle {
            visible: root._emptyCount > 0
            Layout.fillWidth: true
            Layout.preferredHeight: styles.rowHSm
            radius: styles.rSm
            color: emptyTap.pressed ? CommonOptions.colorSurfaceDim
                                    : CommonOptions.colorSurfaceAlt
            border.color: CommonOptions.colorDivider
            border.width: styles.lineHair

            Text {
                anchors.fill: parent
                anchors.leftMargin: styles.spSm
                anchors.rightMargin: styles.spSm
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.showEmptyTracks
                      ? "收起这 " + root._emptyCount + " 条 0 点轨迹"
                      : "另有 " + root._emptyCount + " 条 0 点轨迹 · 点击展开"
                color: CommonOptions.colorTextDim
                font.pixelSize: styles.fsXs
                elide: Text.ElideRight
            }

            MouseArea {
                id: emptyTap
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showEmptyTracks = !root.showEmptyTracks
            }
        }

        EmptyState {
            visible: root._rows.length === 0
            Layout.fillWidth: true
            iconName: "timeline"
            text: String(panelHead.searchText || "").trim().length > 0
                  ? "没有名字匹配「" + panelHead.searchText + "」的轨迹"
                  : "还没有轨迹"
            hint: "在「记录」Tab 开始记录, 或导入 GPX / KML / CSV"
        }

        SheetActionBand {
            Layout.fillWidth: true
            actions: root._bandActions
            onTriggered: root._onBandAction(key)
        }
    }
}
