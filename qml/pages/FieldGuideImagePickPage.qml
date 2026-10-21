/**
 * @file FieldGuideImagePickPage.qml
 * @brief 选图 → 取主色 → 图鉴候选 (2026-10-20 v9 F1 目录母版, 丁骨架二级页)
 *
 * 入口: Main.qml 方位条 "photo" → navBus.navigateTo("FieldGuideImagePickPage", {})
 *       (原来还有一条 CameraPage 的入口, 该页在 #65 孤儿处置里已删).
 * 出口: 点候选行 → FieldGuideDetailPage{speciesId}.
 *
 * 这一页唯一的"算法"是颜色距离, 版式必须把这一点摊开说, 否则用户会把它当成识图:
 *   ① 主色要看得见. ImageColorExtractor.extractFromFile(path, 8) 给的是 8×8 网格
 *      采出来的一个 HSV. 页面上它做成色块 + 等宽读数贴在图下沿, 每条候选也各带
 *      自己的代表色块 —— 两个色块并排, 用户自己能判断"像不像", 不用信那个百分比.
 *   ② 百分比不是识别结论. similarity = max(0, 100 - HSV距离/6.26)
 *      (PlantService.cpp:293), 与形状/纹理/大小无关. 所以它画成一条 5px 墨条,
 *      不做成红黄绿"准/不准"的灯, 也不给整屏铺一条 colorDanger 警示带 ——
 *      危险红是⑤求助的专用色, 不参与读数值分级.
 *   ③ 结果要读得完, 失败要留得下. 复制失败 / 取色失败 / 0 候选都写进常驻 note 行,
 *      不再用三秒就消失的 toast (改版口径同 EquipmentPage / EquipmentDetailPage).
 *   ④ 换界门或换图就清空候选. 候选是按一个 service 算出来的, 留着上一界的条目
 *      还显示"5 条"是假数据.
 *
 * 2026-10-20: 四大类从 ComboBox 换成 4 枚 Chip. ComboBox 的 popup 挂在 Overlay 上,
 *   delegate 不继承 control.font, 真机上字体覆盖修了两轮才不出方框 (#9). Chip 是
 *   本地组件没有那个坑, 四个类目一屏全可见, 还少一次点击.
 */

// delegate 里要读 pickPage 的属性与方法, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Dialogs          // FileDialog 需要
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: pickPage

    Styles { id: styles; visible: false }

    title: "拍照检索图鉴"
    background: Rectangle { color: CommonOptions.colorBg }

    property int currentKingdom: 0      // 0 植物 / 1 动物 / 2 昆虫 / 3 蘑菇
    property url currentImageSource: "" // 给 Image 显示 (Qt 原生支持 content:// 与 file://)
    property string currentImagePath: ""// importImage 复制进沙盒后的绝对路径, 给取色接口
    property var userColor: null        // 取到的主色 {h,s,v}; null = 还没取
    property var rows: []               // 候选行
    property string note: ""            // 常驻提示行 (规则 ③)

    // === 数据源 ==============================================================
    function kingdomService(idx) {
        return idx === 0 ? plantService
             : idx === 1 ? animalService
             : idx === 2 ? insectService
             : idx === 3 ? mushroomService : null
    }
    function kingdomCount(idx) {
        var s = kingdomService(idx)
        return s ? s.totalCount : 0
    }

    readonly property var kingdoms: [
        { k: 0, label: "植物" },
        { k: 1, label: "动物" },
        { k: 2, label: "昆虫" },
        { k: 3, label: "蘑菇" }
    ]

    readonly property string statusLine: {
        if (pickPage.currentImagePath === "")
            return "选一张照片 · 只按主色粗筛"
        if (pickPage.rows.length === 0)
            return "已选图 · 点「按主色匹配」"
        return "候选 " + pickPage.rows.length + " 条 · 点行看图鉴"
    }

    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }
    function navigateTo(page, props) {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.navigateTo(page, props || {})
    }

    function _toArr(v) { return (v && v.length !== undefined) ? v : [] }
    function _cl(v, lo, hi) { return Math.min(hi, Math.max(lo, v)) }

    // 图鉴条目的 representative_color 是 {h,s,v} (h 0-360, s/v 0-100).
    // 换算走 CommonOptions.hsvColor —— QML 没有 Qt.hsv(), 真机上直接 TypeError;
    // 钳位也在 C++ 里做, 这边只负责缺字段返回 null, 由调用方画空格子而不是猜一个色.
    function _hsv(c) {
        if (!c || typeof c !== "object" || !isFinite(Number(c.h))) return null
        return CommonOptions.hsvColor(Math.round(Number(c.h)),
                                      Math.round(Number(c.s) || 0),
                                      Math.round(Number(c.v) || 0))
    }

    // 换图 / 换界门 → 候选与主色一起作废 (规则 ④)
    function _resetMatch() {
        pickPage.rows = []
        pickPage.userColor = null
    }

    function selectKingdom(k) {
        if (pickPage.currentKingdom === k) return
        pickPage.currentKingdom = k
        pickPage._resetMatch()
        pickPage.note = ""
    }

    function setImage(url) {
        pickPage.currentImageSource = url
        pickPage._resetMatch()
    }

    // === 取色 + 匹配 =========================================================
    // 2026-09-14 的 P0 还在: 之前这里硬编码 HSV {h:90,s:60,v:80}, 跟照片无关.
    // 网格采样是同步的 (<1ms), 所以没有加载态可画 —— 不假装 busy.
    function runMatch() {
        pickPage._resetMatch()
        pickPage.note = ""
        if (pickPage.currentImagePath === "") {
            pickPage.note = "还没有可取色的图片"
            return
        }
        var svc = kingdomService(pickPage.currentKingdom)
        if (!svc) {
            pickPage.note = "图鉴服务还没就绪"
            return
        }
        var info = ImageColorExtractor.extractFromFile(pickPage.currentImagePath, 8)
        if (!info || !info.ok) {
            pickPage.note = "取色失败: " + ((info && info.error) ? info.error : "接口没给原因")
            return
        }
        pickPage.userColor = { h: Number(info.h), s: Number(info.s), v: Number(info.v) }
        var user = pickPage.userColor
        var res = pickPage._toArr(svc.matchByColor(user, 5))
        var out = []
        for (var i = 0; i < res.length; ++i) {
            var e = res[i]
            var cat = String(e.category || "")
            out.push({
                speciesId: String(e.id || ""),
                plate: CommonOptions.plateCode("SP", String(e.id || "")),
                name: String(e.commonName || "未命名"),
                sci: String(e.scientificName || ""),
                cat: cat.length > 0 ? CommonOptions.speciesCategoryLabel(cat) : "",
                level: Number(e.dangerLevel) || 0,
                sim: Math.round(pickPage._cl(Number(e.similarity) || 0, 0, 100)),
                swatch: pickPage._hsv(e.representativeColor)
            })
        }
        pickPage.rows = out
        if (out.length === 0) {
            // matchByColor 只跳过 representative_color 为空的条目, 四本图鉴都有色,
            // 所以真取到 0 条只可能是这一界本身是空的 —— 就说这件事, 别说"换个角度拍".
            pickPage.note = pickPage.kingdomCount(pickPage.currentKingdom) === 0
                            ? "本界 0 条条目, 没有可比对的代表色"
                            : "接口返回 0 条候选"
        }
        console.log("[ImagePick] h=" + user.h + " s=" + user.s + " v=" + user.v
                    + " k=" + pickPage.currentKingdom + " -> " + out.length + " rows")
    }

    Component.onCompleted: {
        if (!androidPlatform) pickPage.note = "这台设备没有拍照/相册通道"
    }

    onCurrentImageSourceChanged: {
        if (pickPage.currentImageSource.toString().length === 0) {
            pickPage.currentImagePath = ""
            pickPage._resetMatch()
        }
    }

    // === 版面 ================================================================
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
                    text: "IMAGE MATCH"
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    font.letterSpacing: 1.8
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: "拍照检索图鉴"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: pickPage.statusLine
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
                    onClicked: pickPage.goBack()
                }
            }
        }

        // --- 界门 chip ---
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            spacing: styles.spXs

            Repeater {
                model: pickPage.kingdoms
                delegate: Chip {
                    required property var modelData
                    text: modelData.label + " " + pickPage.kingdomCount(modelData.k)
                    checked: pickPage.currentKingdom === modelData.k
                    accent: CommonOptions.kingdomColor(modelData.k)
                    textSize: styles.fsSm
                    onClicked: pickPage.selectKingdom(modelData.k)
                }
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spXs
            text: "数字 = 本界条目数 · 换界门会清空候选"
            font.pixelSize: styles.fsXs
            color: CommonOptions.colorTextDim
            elide: Text.ElideRight
        }

        // --- 预览 (取色读数贴在图下沿, 规则 ①) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: styles.chartH
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            color: CommonOptions.colorSurface
            border.color: CommonOptions.colorRule
            border.width: styles.lineHair

            Image {
                id: previewImage
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 4
                // 读数带占 26px, 让出来, 否则照片下沿被自己的读数压住
                anchors.bottomMargin: pickPage.userColor !== null ? 30 : 4
                source: pickPage.currentImageSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250 } }
            }
            Text {
                anchors.centerIn: parent
                visible: !previewImage.visible && previewImage.status !== Image.Loading
                         && previewImage.status !== Image.Error
                text: pickPage.currentImageSource.toString().length > 0 ? "等待解码" : "选一张照片"
                color: CommonOptions.colorTextDim
                font.pixelSize: styles.fsMd
            }
            BusyIndicator {
                anchors.centerIn: parent
                width: styles.icXl
                height: styles.icXl
                running: previewImage.status === Image.Loading
                visible: previewImage.status === Image.Loading
            }
            Text {
                anchors.centerIn: parent
                visible: previewImage.status === Image.Error
                text: "这张图解码失败\n换一张,或改用拍照"
                color: CommonOptions.colorDanger
                font.pixelSize: styles.fsSm
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 26
                visible: pickPage.userColor !== null
                color: CommonOptions.colorSurface
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: styles.lineHair
                    color: CommonOptions.colorRule
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: styles.spSm
                    anchors.rightMargin: styles.spSm
                    spacing: styles.spSm
                    Rectangle {
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                        Layout.alignment: Qt.AlignVCenter
                        color: pickPage.userColor
                               ? pickPage._hsv(pickPage.userColor) : CommonOptions.colorSurfaceDim
                        border.color: CommonOptions.colorText
                        border.width: styles.lineHair
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        // 只装拉丁与数字: H/S/V 与数值 (monoFont 不许混汉字)
                        text: pickPage.userColor
                              ? ("H " + Math.round(pickPage.userColor.h)
                                 + "  S " + Math.round(pickPage.userColor.s)
                                 + "  V " + Math.round(pickPage.userColor.v))
                              : ""
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsSm
                        font.letterSpacing: 1.2
                        color: CommonOptions.colorText
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "8×8 网格主色"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                    }
                }
            }
        }

        // --- 取图 ---
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            spacing: styles.spSm

            OutlineButton {
                Layout.fillWidth: true
                text: "从相册选择"
                tone: CommonOptions.colorText
                onClicked: fileDialog.open()
            }
            // 拍照在 Android 侧才接得上 (requestTakePhoto 是 AndroidPlatform 的 invokable)
            OutlineButton {
                Layout.fillWidth: true
                text: "拍照"
                tone: CommonOptions.colorText
                enabled: androidPlatform ? true : false
                onClicked: {
                    if (androidPlatform) androidPlatform.requestTakePhoto()
                }
            }
        }

        PrimaryButton {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            text: "按主色匹配"
            iconName: "search"        // 已核验码位 (原 \ue412 实为 photo, 不是 search)
            tone: CommonOptions.colorAccent
            enabled: pickPage.currentImagePath !== ""
            onClicked: pickPage.runMatch()
        }

        // --- 常驻提示 (规则 ③) ---
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spSm
            visible: pickPage.note.length > 0
            text: pickPage.note
            font.pixelSize: styles.fsSm
            color: CommonOptions.colorLegendAmber
            wrapMode: Text.WordWrap
        }

        // --- 候选区头 (兼作相似度的图例) ---
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spMd
            visible: pickPage.rows.length > 0
            spacing: styles.spSm

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "CANDIDATES"
                font.family: styles.monoFont
                font.pixelSize: styles.fsXs
                font.letterSpacing: 1.6
                color: CommonOptions.colorInk3
            }
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: String(pickPage.rows.length)
                font.family: styles.monoFont
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorText
            }
            Item { Layout.fillWidth: true }
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "色块 = 图鉴代表色 · 条 = 接近度"
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorTextDim
                elide: Text.ElideRight
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: styles.pageMargin
            Layout.rightMargin: styles.pageMargin
            Layout.topMargin: styles.spXs
            Layout.bottomMargin: styles.pageGap

            ListView {
                id: candList
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 0
                model: pickPage.rows
                visible: pickPage.rows.length > 0

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: candList.width
                    // 行里两排信息 (名称+学名 / 编号+类目+接近度), 60 装不下第二排
                    height: styles.rowHTall + styles.spMd

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pickPage.navigateTo(
                                       "FieldGuideDetailPage",
                                       { speciesId: modelData.speciesId })
                    }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spSm

                            Rectangle {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                Layout.alignment: Qt.AlignVCenter
                                // 图鉴条目没填代表色时留空格子, 不猜一个颜色 (规则 ①)
                                color: modelData.swatch ? modelData.swatch
                                                        : CommonOptions.colorSurfaceDim
                                border.color: CommonOptions.colorText
                                border.width: styles.lineHair
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
                                    visible: modelData.sci.length > 0
                                    text: modelData.sci
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorTextDim
                                    elide: Text.ElideRight
                                }
                            }
                            DangerChip {
                                Layout.alignment: Qt.AlignVCenter
                                level: modelData.level
                                compact: true
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: styles.spSm

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.plate
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsXs
                                font.letterSpacing: 1.2
                                color: CommonOptions.colorInk3
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                visible: modelData.cat.length > 0
                                text: modelData.cat
                                font.pixelSize: styles.fsXs
                                color: CommonOptions.colorTextDim
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                Layout.preferredWidth: 60
                                Layout.preferredHeight: 5
                                Layout.alignment: Qt.AlignVCenter
                                color: CommonOptions.colorSurfaceAlt
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * modelData.sim / 100
                                    color: CommonOptions.colorText
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.sim + "%"
                                font.family: styles.monoFont
                                font.pixelSize: styles.fsSm
                                color: CommonOptions.colorText
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: styles.lineHair
                        color: CommonOptions.colorRuleSoft
                        visible: index < pickPage.rows.length - 1
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: pickPage.rows.length === 0
                iconName: "search"
                text: pickPage.currentImagePath === "" ? "还没有图片" : "还没有匹配结果"
                hint: pickPage.currentImagePath === ""
                      ? "从相册选一张,或拍一张 · 只比主色,不比形状"
                      : "色已经取到 · 点「按主色匹配」取前 5 条"
                actionText: pickPage.currentImagePath === "" ? "从相册选择" : "立即匹配"
                onActionTriggered: {
                    if (pickPage.currentImagePath === "") fileDialog.open()
                    else pickPage.runMatch()
                }
            }
        }
    }

    // === 取图通道 ============================================================
    // 兼容 Qt 6.7 的 currentFile 与更早的 selectedFile; Android 11+ 返回 content://,
    // 必须先 importImage 复制进沙盒拿本地路径 —— 直接把 URI 当路径喂给取色接口,
    // 报的是 "file not found", 用户会以为是自己照片的问题.
    FileDialog {
        id: fileDialog
        title: "选择图片"
        nameFilters: ["图片文件 (*.jpg *.jpeg *.png)", "所有文件 (*)"]
        onAccepted: {
            var url = ""
            if (currentFile && currentFile.toString().length > 0) {
                url = currentFile.toString()
            } else if (selectedFile && selectedFile.toString().length > 0) {
                url = selectedFile.toString()
            }
            if (url.length === 0) {
                console.warn("[ImagePick] FileDialog 接受但 currentFile/selectedFile 都空")
                pickPage.note = "系统没回传图片地址"
                return
            }
            pickPage.setImage(url)
            if (androidPlatform) {
                var local = androidPlatform.importImage(url)
                if (local && local.length > 0) {
                    pickPage.currentImagePath = local
                    pickPage.note = ""
                } else {
                    pickPage.currentImageSource = ""
                    pickPage.currentImagePath = ""
                    pickPage._resetMatch()
                    pickPage.note = "这张图复制不进应用目录, 换一张或改用拍照"
                }
            } else {
                pickPage.currentImagePath = url.replace(/^file:\/\//, "")
            }
            console.log("[ImagePick] selected: " + pickPage.currentImagePath)
        }
    }

    // 拍照完成由 AndroidPlatform 回 file:// URI, 已经是本地文件, 不用再复制
    Connections {
        target: androidPlatform ? androidPlatform : null
        function onPhotoTaken(uri) {
            if (!uri || uri.length === 0) return
            pickPage.setImage(uri)
            pickPage.currentImagePath = uri.replace(/^file:\/\//, "")
            pickPage.note = ""
            console.log("[ImagePick] photo: " + pickPage.currentImagePath)
        }
    }
}
