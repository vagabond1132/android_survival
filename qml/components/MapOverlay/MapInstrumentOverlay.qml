/**
 * @file MapInstrumentOverlay.qml
 * @brief ④地图 的丁骨架仪表叠层 —— 迷你盘 + 比例尺 + 搜索/图层/求助 + 定位回中
 *
 * 为什么把这一堆从 MapPage 里抽出来: 改版前地图页有三块各自为政的浮层 —— 顶部一条
 * 48px 深蓝标题栏 (和窗口自己的 header 叠成两条横杠, 白白吃掉 48px 图区)、右侧 6 枚
 * 56px 饱和色圆钮 (MapRightButtonColumn)、右下 +/− (zoomControls)。同一个屏幕三套
 * 视觉语言, 而且按钮越多越没人点. 现在合成一层, 版式照已评审的 mock「丁 ④」:
 *   盘叠在图上 (dial over map), 卡片是纸面+墨线, 不是实心色块.
 *
 * 四条规则:
 *   ① 只有卡片自己吃点击. 根节点是纯 Item, 没有任何 full-size MouseArea —— 地图的
 *      拖动/双击 (#43 手动移动) 必须照常工作, 浮层盖着的地方也能拖.
 *   ② 盘上只画"发现", 不画假读数. 没罗盘朝向 (compassSensor.valid=false) 时盘心
 *      写 "--", Dial 自己不画指针; 微标签行宁可不显示也不给一个 0° 的方向.
 *   ③ 等宽字体只装拉丁与数字 (见 [[qml-monofont-no-cjk]]). 所以这一层的 mono 节点
 *      只有 "ZOOM 13" / "500 m" / "N-UP · CAL 72%" / "3s", 汉字一律走默认字体.
 *   ④ 求助仍然是长按 3 秒才动. 短按不跳页 —— 戴手套/口袋里误触不能把用户推进 SOS 流程.
 *
 * 数据一律由宿主 (MapPage) 传进来: 本组件读不到 mapPage 这个 id (跨文件 id 不可见,
 * 见 [[qml-delegate-outer-id-pragma]]), 也不许在这里查 service.
 */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: ov

    Styles { id: styles; visible: false }

    // === 入参 ==============================================================
    property real heading: 0            // 设备朝向 (compassSensor.heading), 无罗盘时忽略
    property bool hasHeading: false
    property int calibrationPct: -1     // <0 = 拿不到校准度, 不写进微标签
    property var targets: []            // [{bearing, tone}] 盘上的点
    property int zoomLevel: 11
    property string scaleText: ""       // "500 m" / "1.2 km"
    property real scaleBarPx: 62        // 上面那句话对应的像素宽 (宿主算好)
    property int markCount: 0           // 物种标注数 (顶栏那枚小计数)
    property int selectedCount: 0       // 已选路线+轨迹数
    property bool locateReady: false    // 有定位才允许"回中到我的位置"

    // === 出参 ==============================================================
    signal searchClicked()
    signal layersClicked()
    signal locateClicked()
    signal zoomInClicked()
    signal zoomOutClicked()
    signal selectedClicked()
    signal selectedClearClicked()
    signal sosConfirmed()

    z: 1000   // 压在 Map 的所有 MapQuickItem 之上 (原来那几块浮层也是 1000)

    // === 顶部: 搜索 / 图层 / 求助 ==========================================
    RowLayout {
        id: topRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: styles.pageMargin
        anchors.topMargin: styles.spSm
        spacing: styles.spSm

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: styles.btnHSm
            radius: styles.rSm
            color: CommonOptions.withAlpha(CommonOptions.colorSurface, 0.92)
            border.color: CommonOptions.colorText
            border.width: styles.lineHair

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: styles.spSm
                anchors.rightMargin: styles.spSm
                spacing: styles.spSm
                IconLabel {
                    name: "search"
                    size: styles.icSm
                    tintColor: CommonOptions.colorTextDim
                }
                Text {
                    Layout.fillWidth: true
                    text: "搜路线 / 物种 / 已选目标"
                    color: CommonOptions.colorTextMuted
                    font.pixelSize: styles.fsSm
                    elide: Text.ElideRight
                }
                // 标注数放这里: 原来占着顶栏一枚独立按钮, 现在收成行内读数
                Text {
                    visible: ov.markCount > 0
                    text: ov.markCount + " 点"
                    color: CommonOptions.colorTextDim
                    font.pixelSize: styles.fsXs
                }
            }
            TapHandler { onTapped: ov.searchClicked() }
        }

        Rectangle {
            Layout.preferredWidth: styles.btnHSm
            Layout.preferredHeight: styles.btnHSm
            radius: styles.rSm
            color: layersTap.pressed ? CommonOptions.colorSurfaceDim
                                     : CommonOptions.withAlpha(CommonOptions.colorSurface, 0.92)
            border.color: CommonOptions.colorText
            border.width: styles.lineHair
            IconLabel {
                anchors.centerIn: parent
                name: "layers"
                size: styles.icMd
                tintColor: CommonOptions.colorText
            }
            TapHandler { id: layersTap; onTapped: ov.layersClicked() }
        }

        // 求助: 长按 3 秒. 倒计时写在图标位置 (图标字体有 sos 字形, 数字用默认字体)
        Rectangle {
            id: sosBtn
            property int holdSec: 0
            Layout.preferredWidth: styles.btnHSm
            Layout.preferredHeight: styles.btnHSm
            radius: styles.rSm
            color: CommonOptions.withAlpha(CommonOptions.colorHazard, sosArea.pressed ? 0.95 : 0.82)
            border.color: CommonOptions.colorTextOnAccent
            border.width: styles.lineHair

            IconLabel {
                anchors.centerIn: parent
                visible: sosBtn.holdSec === 0
                name: "sos"
                size: styles.icMd
                tintColor: CommonOptions.colorTextOnAccent
            }
            Text {
                anchors.centerIn: parent
                visible: sosBtn.holdSec > 0
                text: (3 - sosBtn.holdSec) + "s"
                color: CommonOptions.colorTextOnAccent
                font.pixelSize: styles.fsMd
                font.bold: true
            }
            Timer {
                id: sosTimer
                interval: 1000
                repeat: true
                onTriggered: {
                    sosBtn.holdSec = Math.min(3, sosBtn.holdSec + 1)
                    if (sosBtn.holdSec >= 3) {
                        stop()
                        sosBtn.holdSec = 0
                        ov.sosConfirmed()
                    }
                }
            }
            // MouseArea 而不是 TapHandler: 需要 pressed/released 两段来计时长
            MouseArea {
                id: sosArea
                anchors.fill: parent
                onPressed: { sosBtn.holdSec = 0; sosTimer.start() }
                onReleased: { sosTimer.stop(); sosBtn.holdSec = 0 }
                onCanceled: { sosTimer.stop(); sosBtn.holdSec = 0 }
            }
        }
    }

    // === 左上: 比例尺 + 缩放 ===============================================
    Column {
        id: zoomCol
        anchors.top: topRow.bottom
        anchors.topMargin: styles.spMd
        anchors.left: parent.left
        anchors.leftMargin: styles.pageMargin
        spacing: styles.spSm

        Rectangle {
            width: scaleBar.width + 2 * styles.spSm
            height: scaleCol.implicitHeight + 2 * styles.spXs
            radius: styles.rSm
            color: CommonOptions.withAlpha(CommonOptions.colorSurface, 0.92)
            border.color: CommonOptions.colorRule
            border.width: styles.lineHair

            Column {
                id: scaleCol
                anchors.centerIn: parent
                spacing: 2
                Text {
                    text: "ZOOM " + ov.zoomLevel
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorTextMuted
                }
                // 标尺: 三段 (空-墨-空), 端头各一条竖线 —— 纯几何, 不依赖字体
                Item {
                    id: scaleBar
                    width: Math.max(30, Math.min(120, ov.scaleBarPx))
                    height: 7
                    Rectangle { anchors.left: parent.left; width: 1; height: parent.height
                               color: CommonOptions.colorText }
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height
                               color: CommonOptions.colorText }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width - 2; height: 1
                               anchors.horizontalCenter: parent.horizontalCenter
                               color: CommonOptions.colorText }
                }
                Text {
                    text: ov.scaleText
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorTextMuted
                }
            }
        }

        Column {
            spacing: styles.lineHair
            Repeater {
                // 两枚方块合成一个 Repeater: + 与 − 只差图标/信号
                // 减号用 ASCII "-": U+2212 在设备 monospace 里不一定有字形 → 方框.
                model: [
                    { key: "in",  glyph: "+" },
                    { key: "out", glyph: "-" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: styles.btnHSm
                    height: styles.btnHSm
                    radius: styles.rSm
                    color: zoomTap.pressed ? CommonOptions.colorSurfaceDim
                                           : CommonOptions.withAlpha(CommonOptions.colorSurface, 0.92)
                    border.color: CommonOptions.colorRule
                    border.width: styles.lineHair
                    Text {
                        anchors.centerIn: parent
                        text: modelData.glyph
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsLg
                        color: CommonOptions.colorText
                    }
                    TapHandler {
                        id: zoomTap
                        onTapped: modelData.key === "in" ? ov.zoomInClicked() : ov.zoomOutClicked()
                    }
                }
            }
        }
    }

    // === 右上: 迷你盘 + 微标签 + 回中 ======================================
    Column {
        id: dialCol
        anchors.top: topRow.bottom
        anchors.topMargin: styles.spSm
        anchors.right: parent.right
        anchors.rightMargin: styles.spSm
        spacing: styles.spXs

        Dial {
            width: styles.dialSize
            height: styles.dialSize
            heading: ov.hasHeading ? ov.heading : 0
            hasFix: ov.hasHeading
            targets: ov.targets
            hubValue: ov.hasHeading ? Math.round(ov.heading) + "°" : "--"
            hubLabel: "HDG"
        }

        // 微标签: 只写拉丁. 没有罗盘时整行不出现, 免得 "--" 旁边再补一串假信息.
        Text {
            visible: ov.hasHeading
            anchors.horizontalCenter: parent.horizontalCenter
            text: "N-UP" + (ov.calibrationPct >= 0 ? " · CAL " + ov.calibrationPct + "%" : "")
            font.family: styles.monoFont
            font.pixelSize: styles.fsXs
            color: CommonOptions.colorTextDim
        }

        Rectangle {
            width: styles.btnHSm
            height: styles.btnHSm
            radius: styles.rSm
            // 没定位时灰底 + 不可点: 按下去只会把地图甩到写死的默认坐标
            enabled: ov.locateReady
            opacity: ov.locateReady ? 1.0 : 0.45
            color: locateTap.pressed ? CommonOptions.colorSurfaceDim
                                     : CommonOptions.withAlpha(CommonOptions.colorSurface, 0.92)
            border.color: ov.locateReady ? CommonOptions.colorText : CommonOptions.colorRule
            border.width: styles.lineHair
            IconLabel {
                anchors.centerIn: parent
                name: "my_location"
                size: styles.icMd
                tintColor: ov.locateReady ? CommonOptions.colorText : CommonOptions.colorTextDim
            }
            TapHandler { id: locateTap; onTapped: ov.locateClicked() }
        }
    }

    // === 左下: 已选目标 chip ================================================
    // 只在选了东西时出现; 单击看清单, 双击清空 (沿用改版前的行为)
    Rectangle {
        id: selChip
        visible: ov.selectedCount > 0
        anchors.left: parent.left
        anchors.leftMargin: styles.pageMargin
        anchors.bottom: parent.bottom
        anchors.bottomMargin: styles.bottomSheetPeek
        width: selChipRow.implicitWidth + 2 * styles.spSm
        height: styles.chipH
        radius: styles.rPill
        color: CommonOptions.withAlpha(CommonOptions.colorSurface, 0.92)
        border.color: CommonOptions.colorText
        border.width: styles.lineHair

        RowLayout {
            id: selChipRow
            anchors.centerIn: parent
            spacing: styles.spXs
            Text {
                text: "已选 " + ov.selectedCount
                color: CommonOptions.colorText
                font.pixelSize: styles.fsSm
            }
            IconLabel { name: "expand_more"; size: styles.icSm; tintColor: CommonOptions.colorTextDim }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: ov.selectedClicked()
            onDoubleClicked: ov.selectedClicked()
        }
    }
}
