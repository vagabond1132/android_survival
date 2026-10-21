/**
 * @file NavigationTab.qml
 * @brief 「轨迹」Tab: 历史轨迹列表, 点击加载到地图 / 右侧分析按钮进详情
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

    function _startLabel(s) {
        var t = String(s || "")
        // MapService 写的是 Qt::ISODate ("2026-10-20T12:34:56"). 直接切字符串比
        // new Date() 解析稳 (导入的 GPX 时间戳格式五花八门, 解析失败会得到 NaN).
        if (t.length >= 16 && t.charAt(10) === "T") {
            return t.substring(5, 10) + " " + t.substring(11, 16)
        }
        return t.length > 0 ? t : "无开始时间"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: styles.pageMargin
        anchors.rightMargin: styles.pageMargin
        anchors.topMargin: styles.spSm
        anchors.bottomMargin: styles.spSm
        spacing: styles.spSm

        RowLayout {
            Layout.fillWidth: true
            spacing: styles.spSm

            SectionTitle {
                Layout.fillWidth: true
                icon: "timeline"
                text: "历史轨迹"
                trailing: root.tracks.length + " 条"
                titleColor: CommonOptions.colorText
                iconColor: CommonOptions.colorAccentSoft
                pixelSize: styles.fsLg
            }
            // 2026-10-09: 导入入口 (此前 importDialog 无任何 .open() 触发点 → 死功能).
            //   上抛 → MapBottomSheet 透传 → MapPage onTrackImportRequested: importDialog.open()
            PrimaryButton {
                Layout.preferredHeight: styles.btnHSm
                text: "导入"
                iconName: "note_add"
                textSize: styles.fsSm
                onClicked: root.trackImportRequested()
            }
            OutlineButton {
                Layout.preferredHeight: styles.btnHSm
                text: "刷新"
                textSize: styles.fsSm
                onClicked: root.refresh()
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: styles.cardGap
            clip: true
            model: root.tracks

            delegate: RowLayout {
                required property var modelData
                readonly property bool picked:
                    root.selectedTrackIds.indexOf(modelData.id) >= 0

                width: list.width
                height: styles.rowHTall
                spacing: styles.spXs

                ListRow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: styles.rowHTall
                    dense: true
                    showChevron: false
                    title: modelData.name || "(未命名轨迹)"
                    titleColor: CommonOptions.colorText
                    subtitle: "起点 " + root._startLabel(modelData.startTime)
                              + " · " + CommonOptions.formatDistance(
                                  Number(modelData.totalDistanceM || 0) / 1000.0)
                              + " · " + (modelData.pointCount || 0) + " 点"
                    value: picked ? "已画线" : ""
                    accent: CommonOptions.colorAccentSoft
                    bg: picked ? CommonOptions.colorSurfaceDim : CommonOptions.colorSurface
                    onClicked: root.trackSelected(modelData.id, modelData)
                }

                // 分析 (P1): 方形小按钮, 不吃 ListRow 的点击
                Rectangle {
                    Layout.preferredWidth: styles.btnHSm
                    Layout.preferredHeight: styles.btnHSm
                    Layout.alignment: Qt.AlignVCenter
                    radius: styles.rSm
                    color: CommonOptions.colorSurfaceDim
                    border.color: CommonOptions.colorDivider
                    border.width: styles.lineHair
                    IconLabel {
                        anchors.centerIn: parent
                        name: "equalizer"
                        size: styles.icSm
                        tintColor: CommonOptions.colorAccentSoft
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.trackAnalyzeRequested(modelData.id)
                    }
                }
            }
        }

        EmptyState {
            visible: root.tracks.length === 0
            Layout.fillWidth: true
            iconName: "timeline"
            text: "还没有轨迹"
            hint: "在「记录」Tab 开始记录, 或导入 GPX / KML / CSV"
        }
    }
}
