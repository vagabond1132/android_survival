/**
 * @file FieldGuideDetailPage.qml
 * @brief 图鉴详情 (2026-09-14 UI 改版)
 *
 * 改进: token 化 + 卡片化 + 按 dangerLevel 着色保留
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: detailPage
    property string entityId: ""
    // 2026-09-19: 兼容旧调用, 保留 entity 入参. 但下面 _loadEntity() 会优先
    //   按 entityId + kingdomIndex 重新拉取完整数据, 避免 ListModel role 化导致
    //   嵌套数组 (ediblePart / lookAlike[fieldMap]) 丢失或变 QQmlListModel.
    property var entity: ({})
    property int kingdomIndex: 0  // 0=植物 1=动物 2=昆虫 3=蘑菇
    property bool opened: false

    // 2026-09-14: 记录位置用, 默认北京 (实际应该用 mapService 的 lastKnownPos)
    property real _lastLat: 39.9087
    property real _lastLon: 116.3975

    signal closeRequested()

    function buildFirstAidModel() {
        var arr = []
        if (entity.firstAidId) {
            arr.push({"scenario": "中毒/咬伤", "id": entity.firstAidId})
        }
        if (entity.firstAidLinks) {
            for (var k in entity.firstAidLinks) {
                arr.push({"scenario": k, "id": entity.firstAidLinks[k]})
            }
        }
        return arr
    }

    // 2026-09-19: 把 list 字段统一转成 JS Array (避免 .join() 报
    //   "Property 'join' of object QQmlListModel is not a function").
    //   QStringList 在 QML 端是 QQmlListModel, 没有 Array.prototype 方法.
    function _toArr(v) {
        if (!v) return []
        if (Array.isArray(v)) return v
        // QQmlListModel 有 length 但没有 Array.isArray
        var out = []
        try {
            for (var i = 0; i < v.length; ++i) out.push(v[i])
        } catch (e) { return [] }
        return out
    }

    // 2026-09-19: 运行时图册 (ImageFetcherService 提供)
    property bool _photoLoading: false
    ListModel { id: photoModel }

    // kingdomIndex -> kingdom 字符串 (缓存目录用)
    function _kingdomName() {
        return ["plantae", "animalia", "insecta", "fungi"][kingdomIndex] || "unknown"
    }

    // 2026-10-08: kingdom 字符串 -> kingdomIndex (易混种跳转时该条目可能跨类别,
    //   如植物详情的易混种是某毒蘑菇, 需跳到蘑菇详情页).
    function _kingdomIndexOf(kingdom) {
        var i = ["plantae", "animalia", "insecta", "fungi"].indexOf(kingdom)
        return i >= 0 ? i : detailPage.kingdomIndex
    }

    // kingdomIndex -> 检索词类别后缀 (中文名兜底时避免错类别, 如"眼镜蛇 plant")
    function _kingdomHint() {
        return ["plant", "animal", "insect", "mushroom"][kingdomIndex] || ""
    }

    // 2026-09-24: 取本实体的下载检索词, photoSources 为空时用学名/中文名兜底.
    //   背景: 数据侧历史遗留导致部分条目没有 photo_sources (animals/insects/mushrooms
    //   曾全量为空), 旧逻辑在此直接 return → imageFetcher.fetchImages 永不调用 →
    //   图册永远"暂无图片". 兜底后即使数据缺字段, 也至少能按学名/中文名检索一次.
    //   数据侧的补齐由 scripts/add_photo_sources.py 负责, 这里只做运行期保底.
    function _collectSources() {
        var data = _toArr(entity.photoSources)
        var out = []
        for (var i = 0; i < data.length; ++i) {
            if (data[i]) out.push(data[i])
        }
        if (out.length > 0) return out
        var sci = (entity.scientificName || "").trim()
        var cn = (entity.commonName || "").trim()
        if (sci) out.push(sci)
        if (cn) {
            out.push(cn)
            var hint = _kingdomHint()
            if (hint) out.push(cn + " " + hint)
        }
        return out
    }

    // 2026-09-19: 重新拉取完整 entity (按 entityId + kingdomIndex)
    //   FieldGuidePage 的 ListModel role 化会丢嵌套数组, 这里走 service
    //   保证 ediblePart / lookAlike 等字段是 JS Array (有 join/filter 等).
    function _loadPhotos() {
        // 2026-09-30 诊断: 图册加载链路埋点 (QML 侧). 走 qDebug → 全局 message handler
        //   汇聚进 stage0.log. 判读: 无 "gp loadPhotos" → 本函数没跑 (entity 未就绪);
        //   有 "gp loadPhotos sources=0" → 检索词为空 (数据字段缺失);
        //   有 "gp loadPhotos ... calling fetchImages" 但无后续 "gp allReady/gp failed"
        //   → C++ 侧信号没回 → 看 C++ 的 "img req/reply" 埋点.
        photoModel.clear()
        if (!entity || !entity.id) {
            console.warn("[gp loadPhotos] SKIP no entity.id")
            return
        }
        var sources = _collectSources()
        if (sources.length === 0) {
            console.warn("[gp loadPhotos] SKIP sources=0 id=" + entity.id)
            return
        }

        var kingdom = detailPage._kingdomName()
        var cached = imageFetcher.cachedImages(entity.id, kingdom)
        // fetchImages 会把已缓存的图作为 imageReady 信号立即重发,
        // 这里只需要标记加载态 (缓存为空时才显示)
        detailPage._photoLoading = (cached.length === 0)
        console.log("[gp loadPhotos] id=" + entity.id + " kingdom=" + kingdom
                    + " sources=" + sources.length + " cached=" + cached.length
                    + " loading=" + detailPage._photoLoading
                    + " → calling fetchImages")
        imageFetcher.fetchImages(entity.id, kingdom, sources)
    }

    // 2026-09-19: 进入页面时按 entityId 重新拉数据 + 触发图册加载
    // 2026-09-20: 之前 Component.onCompleted + onEntityIdChanged 双触发导致 _loadEntity
    //   跑两次 (一次空 id, 一次有效 id). 只用 onEntityIdChanged + onKingdomIndexChanged
    //   兜底首次加载.
    onEntityIdChanged: detailPage._loadEntity()
    onKingdomIndexChanged: detailPage._loadEntity()
    // 2026-09-20: onEntityChanged 不再隐式触发 _loadPhotos, 改为 _loadEntity 显式调
    //   (避免 recordLocation 修改 entity 后 _loadPhotos 再次跑, 清空刚刚加载的图).
    function _loadEntity() {
        var id = entityId || (entity && entity.id) || ""
        if (!id) {
            console.warn("[gp loadEntity] SKIP empty id entityId=" + entityId)
            return
        }
        var fresh = {}
        // 2026-09-30 诊断: 记录走哪个 service + 取回结果, 定位 "图册无数据" 是否卡在取 entity.
        var svcName = ["plantService", "animalService", "insectService", "mushroomService"][kingdomIndex] || "?"
        if (kingdomIndex === 0) fresh = plantService.getById(id)
        else if (kingdomIndex === 1) fresh = animalService.getById(id)
        else if (kingdomIndex === 2) fresh = insectService.getById(id)
        else if (kingdomIndex === 3) fresh = mushroomService.getById(id)
        console.log("[gp loadEntity] id=" + id + " kingdomIndex=" + kingdomIndex
                    + " svc=" + svcName + " got.id=" + ((fresh && fresh.id) ? fresh.id : "(null)"))
        if (fresh && fresh.id) {
            entity = fresh
            // 同步触发图册加载, 因为删了 onEntityChanged 自动触发
            detailPage._loadPhotos()
        }
    }

    background: Rectangle { color: CommonOptions.colorBg }
    Styles { id: styles }

    Flickable {
        anchors.fill: parent
        contentWidth: parent.width
        contentHeight: detailColumn.height
        clip: true

        ColumnLayout {
            id: detailColumn
            width: parent.width
            spacing: 0

            // === 顶部 hero (按危险等级着色) ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                color: {
                    if (entity.dangerLevel >= 4) return "#B71C1C"
                    if (entity.dangerLevel >= 3) return CommonOptions.colorDanger
                    if (entity.dangerLevel >= 2) return CommonOptions.colorWarn
                    if (entity.dangerLevel >= 1) return "#FBC02D"
                    return CommonOptions.colorSuccess
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spLg
                    spacing: styles.spMd

                    Rectangle {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        radius: 32
                        color: "white"
                        opacity: 0.15
                        Text {
                            anchors.centerIn: parent
                            text: entity.dangerLevel >= 4 ? "\ue1db" :
                                  entity.dangerLevel >= 3 ? "\ue002" :
                                  entity.dangerLevel >= 1 ? "!" : "\ue5ca"
                            font.family: "Material Icons"
                            color: "white"
                            font.pixelSize: 32
                            font.bold: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: entity.commonName || ""
                            color: "white"
                            font.pixelSize: styles.fs2xl
                            font.bold: true
                        }
                        Text {
                            text: entity.scientificName || ""
                            color: "#FFFFFF"
                            opacity: 0.8
                            font.pixelSize: styles.fsSm
                            font.italic: true
                        }
                    }
                }
            }

            // === 性质卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 56
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: styles.spSm
                    Text {
                        text: entity.dangerLevel >= 4 ? "\ue1db 危险/致命" :
                              entity.dangerLevel >= 3 ? "\ue002 中毒/有害" :
                              entity.dangerLevel >= 1 ? "! 慎用/微毒" : "\ue5ca 无害可食"
                        font.family: "Material Icons"
                        // 2026-09-21 UI 统一: >= 3 用 colorWarn (中等毒) 不再跟 >= 4 共用 colorDanger
                        color: entity.dangerLevel >= 4 ? CommonOptions.colorDanger :
                               entity.dangerLevel >= 3 ? CommonOptions.colorWarn :
                               entity.dangerLevel >= 1 ? CommonOptions.colorWarn : CommonOptions.colorSuccess
                        font.pixelSize: styles.fsLg
                        font.bold: true
                    }
                    Text {
                        text: entity.category || ""
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                    }
                }
            }

            // === 植物特有: 可食信息 ===
            Rectangle {
                visible: kingdomIndex === 0 && entity.ediblePart && entity.ediblePart.length > 0
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 110
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: CommonOptions.colorSuccess
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 4
                    Text { text: "\ue406 可食信息"; font.family: "Material Icons"; color: CommonOptions.colorSuccess; font.bold: true; font.pixelSize: styles.fsMd }  // eco (leaf)
                    Text {
                        Layout.fillWidth: true
                        text: "部位: " + (entity.ediblePart ? entity.ediblePart.join("/") : "") +
                              "  月份: " + (entity.edibleMonths ? entity.edibleMonths.join("、") : "") +
                              (entity.mustCook ? "  \ue002 必须做熟" : "")
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsSm
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "方法: " + (entity.edibleMethod ? entity.edibleMethod.join("/") : "") +
                              (entity.taste ? "  口感: " + entity.taste : "")
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: entity.harvestTips
                        text: "采摘要点: " + (entity.harvestTips || "")
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsXs
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // === 动物特有: 毒腺/攻击 ===
            Rectangle {
                visible: kingdomIndex === 1 && entity.venomType && entity.venomType !== "none"
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 100
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: CommonOptions.colorDanger
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 4
                    Text { text: "\ue1b1 毒腺信息"; font.family: "Material Icons"; color: CommonOptions.colorDanger; font.bold: true; font.pixelSize: styles.fsMd }
                    Text {
                        Layout.fillWidth: true
                        text: "毒素类型: " + (entity.venomType || "未知") +
                              (entity.venomLocation ? "  部位: " + entity.venomLocation : "") +
                              (entity.attackDistanceCm > 0 ? "  攻击距离: " + entity.attackDistanceCm + "cm" : "")
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsSm
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "活跃时段: " + (entity.activeTime || "未知") +
                              (entity.hibernationMonths && entity.hibernationMonths.length > 0
                               ? "  冬眠: " + entity.hibernationMonths.join("、") + "月" : "")
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsSm
                    }
                }
            }

            // === 蘑菇特有: 中毒信息 ===
            Rectangle {
                visible: kingdomIndex === 3 && entity.poisoningType
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: 100
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: CommonOptions.colorDanger
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 4
                    Text { text: "\ue1b1 中毒信息"; font.family: "Material Icons"; color: CommonOptions.colorDanger; font.bold: true; font.pixelSize: styles.fsMd }
                    Text {
                        Layout.fillWidth: true
                        text: "中毒类型: " + (entity.poisoningType || "未知") +
                              (entity.latencyHours > 0 ? "  潜伏期: " + entity.latencyHours + " 小时" : "") +
                              "  致死率: " + (entity.mortalityRate || "未知")
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsSm
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // === 易混种警示 ===
            Rectangle {
                visible: entity.lookAlike && entity.lookAlike.length > 0
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                // 2026-09-16: 修复 height binding bug
                implicitHeight: contentCol.implicitHeight + 24
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: CommonOptions.colorWarn
                border.width: 1

                ColumnLayout {
                    id: contentCol
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 6
                    Text { text: "\ue002 易混种警示"; font.family: "Material Icons"; color: CommonOptions.colorWarn; font.bold: true; font.pixelSize: styles.fsMd }  // warning
                    Repeater {
                        model: entity.lookAlike || []
                        // 2026-10-08: 有 id 的易混种可点击跳转到其详情页;
                        //   无 id(图鉴外的"外部提及", 如只作参照的物种) 渲染为纯文案.
                        delegate: Rectangle {
                            id: laItem
                            Layout.fillWidth: true
                            // 有 id 且有名字才算可跳转的图鉴内条目
                            readonly property bool _clickable: !!(modelData.id)
                            color: "transparent"
                            implicitHeight: laCol.implicitHeight
                            radius: styles.rMd

                            ColumnLayout {
                                id: laCol
                                width: parent.width
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: "\u25B8 " + (modelData.name || modelData.commonName || "未知") +
                                          (modelData.fatality ? "  (致死性: " + modelData.fatality + ")" : "") +
                                          (laItem._clickable ? "  \u203A" : "")
                                    color: laItem._clickable ? CommonOptions.colorAccent : CommonOptions.colorText
                                    font.pixelSize: styles.fsMd
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "区别: " + (modelData.distinction || "")
                                    color: CommonOptions.colorTextMuted
                                    font.pixelSize: styles.fsSm
                                    wrapMode: Text.WordWrap
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: laItem._clickable
                                cursorShape: laItem._clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    detailPage.ApplicationWindow.window.navBus.navigateTo("FieldGuideDetailPage", {
                                        entityId: modelData.id,
                                        kingdomIndex: detailPage._kingdomIndexOf(modelData.kingdom)
                                    })
                                }
                            }
                        }
                    }
                }
            }

            // === 急救联动 ===
            Rectangle {
                visible: entity.firstAidLinks && Object.keys(entity.firstAidLinks).length > 0 ||
                         entity.firstAidId
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                // 2026-09-16: 修复 height binding bug
                implicitHeight: firstAidCol.implicitHeight + 24
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: CommonOptions.colorAccent
                border.width: 1

                ColumnLayout {
                    id: firstAidCol
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 6
                    Text { text: "\ue1b1 急救联动"; font.family: "Material Icons"; color: CommonOptions.colorAccent; font.bold: true; font.pixelSize: styles.fsMd }  // sos
                    Repeater {
                        model: buildFirstAidModel()
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: modelData.scenario + " → " + modelData.id
                                color: CommonOptions.colorText
                                font.pixelSize: styles.fsSm
                                wrapMode: Text.WordWrap
                            }
                            Button {
                                text: "查看"
                                Material.background: CommonOptions.colorAccent
                                Material.foreground: "white"
                                font.pixelSize: styles.fsSm
                                onClicked: {
                                    ApplicationWindow.window.navBus.navigateTo("FirstAidDetailPage", { entryId: modelData.id })
                                }
                            }
                        }
                    }
                }
            }

            // 2026-09-19: 识别特征 (详细描述上方) - 数据已在 entity.features,
            // 4 个 field_guide_*.json 全部 290 条都有 features 填充 (合计 1119 条)
            Section { titleIcon: "\ue8b6"; title: "识别特征"; items: entity.features || [] }  // search

            // 2026-09-19: 图册 (2 列 GridLayout 容器, 暂无内容, 留 placeholder)
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                implicitHeight: galleryCol.implicitHeight + 24
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                ColumnLayout {
                    id: galleryCol
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: styles.spSm

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "\ue8b6 图册"  // Material Icons: photo_library
                            font.family: "Material Icons"
                            color: CommonOptions.colorText
                            font.bold: true
                            font.pixelSize: styles.fsMd
                            Layout.fillWidth: true
                        }
                        Text {
                            text: detailPage._photoLoading
                                  ? "加载中… " + photoModel.count + " 张"
                                  : photoModel.count + " 张"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsXs
                        }
                        // 2026-09-23: 加图册刷新按钮 - 之前图册无图就永远无图
                        //   (ImageFetcherService 不会重试远程), 现在可手动
                        //   清缓存 + 重拉. 同时给用户一个"网络失败可重试"的入口.
                        Button {
                            text: detailPage._photoLoading ? "\ue1b5" : "\ue5d5"  // hourglass / refresh
                            font.family: "Material Icons"
                            flat: true
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 28
                            Material.foreground: CommonOptions.colorAccent
                            enabled: !detailPage._photoLoading
                            ToolTip.text: "刷新图册 (清缓存重拉)"
                            ToolTip.visible: hovered
                            ToolTip.delay: 600
                            onClicked: {
                                if (!entity || !entity.id) return
                                var kingdom = detailPage._kingdomName()
                                var sources = detailPage._collectSources()
                                if (sources.length === 0) {
                                    recordTip.show("无可用检索词, 无法刷新", false)
                                    return
                                }
                                // 清缓存 + 重新加载
                                console.log("[gp refresh] id=" + entity.id + " kingdom=" + kingdom
                                            + " sources=" + sources.length + " → clearCache + fetchImages")
                                imageFetcher.clearCache(entity.id, kingdom)
                                photoModel.clear()
                                detailPage._photoLoading = true
                                imageFetcher.fetchImages(entity.id, kingdom, sources)
                            }
                        }
                    }

                    // 2 列网格 (图片来源: photoModel, 由 imageFetcher 异步填充)
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: styles.spSm
                        rowSpacing: styles.spSm
                        visible: photoModel.count > 0

                        Repeater {
                            model: photoModel
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 140
                                radius: styles.rMd
                                // 2026-09-21: 占位符深色背景, 让图片加载完成后视觉过渡明显
                                color: "#37474F"
                                border.color: Qt.darker(CommonOptions.colorSurface, 1.2)
                                border.width: 1
                                clip: true

                                // 加载状态跟踪 - id 引用而非 parent.children[0] (避免子元素顺序变化)
                                Image {
                                    id: cellImage
                                    anchors.fill: parent
                                    source: model.path
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    visible: status === Image.Ready
                                    // 加载完成后淡入
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                }
                                // 加载占位 (灰底 + 索引 + spinner)
                                Item {
                                    anchors.fill: parent
                                    visible: cellImage.status !== Image.Ready
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        BusyIndicator {
                                            width: 24; height: 24
                                            running: cellImage.status === Image.Loading
                                            visible: cellImage.status === Image.Loading
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                        Text {
                                            text: cellImage.status === Image.Error
                                                  ? "加载失败"
                                                  : ("图 " + (model.idx + 1))
                                            color: cellImage.status === Image.Error
                                                   ? CommonOptions.colorDanger
                                                   : CommonOptions.colorTextMuted
                                            font.pixelSize: styles.fsXs
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 空态/加载态: 都没有图时
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 80
                        visible: photoModel.count === 0

                        Text {
                            anchors.centerIn: parent
                            text: detailPage._photoLoading ? "正在加载图片…" : "暂无图片"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: styles.fsSm
                        }

                        BusyIndicator {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            running: detailPage._photoLoading
                            visible: detailPage._photoLoading
                            width: 28; height: 28
                        }
                    }
                }
            }

            // === 描述卡 ===
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                // 2026-09-16: 修复 height binding bug
                implicitHeight: descCol.implicitHeight + 24
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
                border.width: 1

                ColumnLayout {
                    id: descCol
                    anchors.fill: parent
                    anchors.margins: styles.spMd
                    spacing: 4
                    Text { text: "\ue873 详细描述"; font.family: "Material Icons"; color: CommonOptions.colorText; font.bold: true; font.pixelSize: styles.fsMd }
                    Text {
                        Layout.fillWidth: true
                        text: entity.description || "暂无"
                        color: CommonOptions.colorText
                        font.pixelSize: styles.fsSm
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "来源: " + (entity.source || "未注明") +
                              (entity.reviewer ? "  审核: " + entity.reviewer : "")
                        color: CommonOptions.colorTextMuted
                        font.pixelSize: styles.fsXs
                    }
                }
            }

            // === 操作按钮 ===
            // 2026-09-17: 内联轻量提示 (无 Toast 组件时), 反馈记录结果
            Rectangle {
                id: recordTip
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                Layout.preferredHeight: tipText.implicitHeight + 16
                visible: false
                color: CommonOptions.colorSurface
                radius: styles.rLg
                border.color: CommonOptions.colorSuccess
                border.width: 1
                Text {
                    id: tipText
                    anchors.fill: parent
                    anchors.margins: 8
                    color: CommonOptions.colorText
                    font.pixelSize: styles.fsSm
                    wrapMode: Text.WordWrap
                }
                Timer {
                    id: tipTimer
                    interval: 1800
                    onTriggered: recordTip.visible = false
                }
                function show(msg, ok) {
                    tipText.text = msg
                    border.color = ok ? CommonOptions.colorSuccess : CommonOptions.colorDanger
                    visible = true
                    tipTimer.restart()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: styles.spLg
                spacing: styles.spSm
                Button {
                    text: "\ue0c8 记录位置"  // Material Icons: place
                    font.family: "Material Icons"
                    Layout.fillWidth: true
                    Material.background: CommonOptions.colorSuccess
                    Material.foreground: "white"
                    enabled: !entity.isRecorded
                    onClicked: {
                        // 2026-09-17: 早退校验 entity.id, 不然 C++ 端写脏数据无反馈
                        if (!entity || !entity.id) {
                            recordTip.show("记录失败: 缺少实体 ID", false)
                            return
                        }
                        var ok = false
                        if (kingdomIndex === 0) {
                            ok = plantService.recordLocation(entity.id, _lastLat, _lastLon, "用户记录")
                        } else if (kingdomIndex === 1) {
                            ok = animalService.recordLocation(entity.id, _lastLat, _lastLon, "用户记录")
                        } else if (kingdomIndex === 2) {
                            ok = insectService.recordLocation(entity.id, _lastLat, _lastLon, "用户记录")
                        } else if (kingdomIndex === 3) {
                            ok = mushroomService.recordLocation(entity.id, _lastLat, _lastLon, "用户记录")
                        }
                        if (ok) {
                            entity.isRecorded = true
                            recordTip.show("✓ 位置已记录 (" + _lastLat.toFixed(4) + ", " + _lastLon.toFixed(4) + ")", true)
                        } else {
                            recordTip.show("记录失败, 请查看日志", false)
                        }
                    }
                }
                Button {
                    text: "\ue865 收藏"  // Material Icons: bookmark
                    font.family: "Material Icons"
                    Layout.fillWidth: true
                    Material.background: CommonOptions.colorWarn
                    Material.foreground: "white"
                    // 2026-09-14: 接 FieldGuideHistory.addRecord 收藏 (类似浏览历史)
                    onClicked: {
                        fieldGuideHistory.addRecord(
                            entity.id, kingdomIndex, entity.commonName,
                            entity.scientificName, entity.category,
                            entity.dangerLevel, "favorited", "", entity.firstAidId,
                            _lastLat, _lastLon, "用户收藏")
                    }
                }
                Button {
                    text: "\ue5c4 返回"  // Material Icons: arrow_back
                    font.family: "Material Icons"
                    Layout.fillWidth: true
                    Material.background: CommonOptions.colorTextMuted
                    Material.foreground: "white"
                    // 2026-09-14: page push 模式用 navBus.back()
                    onClicked: ApplicationWindow.window.navBus.back()
                }
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: styles.spLg }
        }
    }

    // 2026-09-19: ImageFetcherService 信号监听 (缓存命中 + 远程下载)
    // 2026-09-30 诊断: 每个 signal 入口第一行先打日志 —— 这是判定 "C++ 是否真的发了信号"
    //   与 "id 是否对得上" 的关键. 若 C++ 有 "img cached" 而这里无 "gp onImageReady" →
    //   信号名/参数不匹配或 Connections target 断了; 有 "gp onImageReady" 但 id 不匹配 →
    //   页面 entity.id 与 fetch 时传的 id 不一致 (entity 被换过).
    Connections {
        target: imageFetcher
        function onImageReady(id, index, localPath) {
            console.log("[gp onImageReady] id=" + id + " idx=" + index
                        + " curEntityId=" + (detailPage.entity ? detailPage.entity.id : "(no entity)")
                        + " path=" + localPath)
            if (id !== detailPage.entity.id) {
                console.warn("[gp onImageReady] ID MISMATCH, drop")
                return
            }
            // 本地绝对路径 → file:// URL (Windows 测试机 + Android 真机都兼容)
            var url = "file:///"
            if (localPath.charAt(0) === "/") {
                url += localPath
            } else {
                url += localPath.replace(/\\/g, "/").replace(/^([A-Za-z]):/, "$1:")
            }
            // 已存在就不重复加 (cached 路径 + 远程补的可能是同一张)
            for (var i = 0; i < photoModel.count; i++) {
                if (photoModel.get(i).idx === index) {
                    console.log("[gp onImageReady] idx=" + index + " already in model, skip")
                    return
                }
            }
            photoModel.append({"path": url, "idx": index})
            console.log("[gp onImageReady] appended, photoModel.count=" + photoModel.count
                        + " url=" + url)
        }
        function onImagesAllReady(id, paths) {
            console.log("[gp onImagesAllReady] id=" + id
                        + " curEntityId=" + (detailPage.entity ? detailPage.entity.id : "(no entity)")
                        + " paths=" + (paths ? paths.length : 0))
            if (id === detailPage.entity.id) detailPage._photoLoading = false
        }
        function onImageFailed(id, reason) {
            console.warn("[gp onImageFailed] id=" + id + " reason=" + reason)
            if (id === detailPage.entity.id) detailPage._photoLoading = false
        }
    }
}
