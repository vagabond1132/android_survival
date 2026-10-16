/**
 * @file FieldGuideImagePickPage.qml
 * @brief 拍照/选图 → 图鉴候选匹配(HSV 颜色特征)
 *
 * 2026-09-11 一次性重写:
 *   - 加 FileDialog 选图 (从相册选)
 *   - 加 Image 预览
 *   - 加返回按钮 (push 进来后能返回)
 *   - 颜色 token 统一
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Dialogs  // 2026-09-14: FileDialog 需要
import QtQuick.Layouts
// 2026-09-14: 移除无关的 QtLocation import (之前误加, 引入大模块解析开销 + 偶发 push 失败)
import OutdoorSurvival 1.0

Page {
    id: pickPage
    title: "拍照检索图鉴"
    property int currentKingdom: 0  // 0=植物 1=动物 2=昆虫 3=蘑菇
    property var currentResults: []
    // 2026-09-16: 改为 imageSource, 直接给 Image 用 (Qt 自动处理 content:// 和 file://)
    // 不再剥离 file:// 前缀, 也不去掉 content://, Image 组件原生支持
    property url currentImageSource: ""
    // 2026-09-17: 补声明 currentImagePath (之前没声明, 用 dynamic property 严格模式会崩)
    // 该字段是 importImage 返回的本地沙盒绝对路径, 给 ImageColorExtractor 读
    property string currentImagePath: ""
    // 2026-09-20: 匹配中标志, 防止用户连点 matchByColor 触发 N 次网格采样
    property bool _matching: false

    background: Rectangle { color: CommonOptions.colorBg }

    readonly property var kingdomOptions: [
        { value: 0, label: "\ue406 植物" },
        { value: 1, label: "\ue91a 动物" },
        { value: 2, label: "\ue1b9 昆虫" },
        { value: 3, label: "\ue239 蘑菇" }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 顶部工具栏: 返回 + 4 大类
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: CommonOptions.colorSurface
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                ToolButton {
                    text: "←"
                    font.pixelSize: 20
                    onClicked: pickPage.ApplicationWindow.window.navBus.back()
                }

                ComboBox {
                    id: kingdomCombo
                    Layout.fillWidth: true
                    model: pickPage.kingdomOptions
                    textRole: "label"
                    valueRole: "value"
                    // 2026-09-30: 同 FieldGuidePage - label 是 PUA 码位, 必须显式
                    //   指定 Material Icons 字体, 否则真机默认字体无字形 → 方框.
                    font.family: "Material Icons"
                    // 2026-09-20: 之前 currentIndex: pickPage.currentKingdom + onActivated
                    //   回写是双向绑定, currentKingdom 外部改动会触发 ping-pong.
                    //   改为单次 Component.onCompleted 初始化 + onActivated 单向通知.
                    Component.onCompleted: currentIndex = pickPage.currentKingdom
                    onActivated: pickPage.currentKingdom = currentValue
                }
            }
        }

        // 操作区
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: CommonOptions.colorBg

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Text {
                    text: "\ue412 选择或拍摄图片"  // Material Icons: camera_alt
                    font.family: "Material Icons"
                    color: CommonOptions.colorText
                    font.pixelSize: 18
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "本功能基于图像颜色特征粗筛,结果仅供参考。务必对照图鉴二次确认。"
                    color: CommonOptions.colorTextMuted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                // 2026-09-11: 图片预览框 (有图时显示图, 无图时显示提示)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    color: CommonOptions.colorSurface
                    radius: 6
                    border.color: CommonOptions.colorTextMuted
                    border.width: 1

                    Image {
                        id: previewImage
                        anchors.fill: parent
                        anchors.margins: 4
                        source: pickPage.currentImageSource
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        // 2026-09-21: 用 status 显式判断, 加 opacity 淡入
                        opacity: status === Image.Ready ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !previewImage.visible && previewImage.status !== Image.Loading
                        text: "\ue2c8\n点击下方按钮选择图片"  // Material Icons: folder_open
                        font.family: "Material Icons"
                        color: CommonOptions.colorTextMuted
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 16
                    }
                    // 加载中: spinner
                    BusyIndicator {
                        anchors.centerIn: parent
                        width: 32; height: 32
                        running: previewImage.status === Image.Loading
                        visible: previewImage.status === Image.Loading
                    }
                    // 加载失败提示
                    Text {
                        anchors.centerIn: parent
                        visible: previewImage.status === Image.Error
                        text: "图片加载失败\n可能格式不支持或文件不存在"
                        color: CommonOptions.colorDanger
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // 选图按钮
                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    text: "\ue2c8 从相册选择"  // Material Icons: folder_open
                    font.family: "Material Icons"
                    Material.background: CommonOptions.colorAccent
                    Material.foreground: "white"
                    font.pixelSize: 16
                    onClicked: fileDialog.open()
                }

                // 拍照按钮 (2026-09-16: 改用 Q_INVOKABLE requestTakePhoto)
                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    text: "\ue412 拍照"  // Material Icons: camera_alt
                    font.family: "Material Icons"
                    Material.background: CommonOptions.colorWarn
                    Material.foreground: "white"
                    font.pixelSize: 16
                    enabled: androidPlatform && androidPlatform.requestTakePhoto
                    onClicked: {
                        if (androidPlatform && androidPlatform.requestTakePhoto) {
                            androidPlatform.requestTakePhoto()
                        }
                    }
                }

                // 匹配按钮
                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    text: "\ue8b6 匹配图鉴"  // Material Icons: search
                    font.family: "Material Icons"
                    Material.background: CommonOptions.colorAccent
                    Material.foreground: "white"
                    font.pixelSize: 16
                    enabled: pickPage.currentImagePath !== "" && !pickPage._matching
                    onClicked: {
                        // 2026-09-14: P0 修复假匹配. 之前硬编码 HSV {h:90,s:60,v:80}
                        // 跟图片完全无关. 现在用 ImageColorExtractor 提取真实主色
                        // (Qt QImage 8x8 网格采样, < 1ms).
                        // 2026-09-20: 加 _matching 锁, 防止用户连点; 失败时 Toast 提示.
                        pickPage._matching = true
                        var colorInfo = ImageColorExtractor.extractFromFile(
                            pickPage.currentImagePath, 8)
                        if (!colorInfo.ok) {
                            pickPage._matching = false
                            toast.error("颜色提取失败: " + (colorInfo.error || "未知"))
                            return
                        }
                        var userColor = {
                            "h": colorInfo.h,
                            "s": colorInfo.s,
                            "v": colorInfo.v
                        }
                        // 2026-09-16: 4 个 service 都有 matchByColor 了, 不用三元保护
                        if (currentKingdom === 0) {
                            pickPage.currentResults = plantService.matchByColor(userColor, 5)
                        } else if (currentKingdom === 1) {
                            pickPage.currentResults = animalService.matchByColor(userColor, 5)
                        } else if (currentKingdom === 2) {
                            pickPage.currentResults = insectService.matchByColor(userColor, 5)
                        } else if (currentKingdom === 3) {
                            pickPage.currentResults = mushroomService.matchByColor(userColor, 5)
                        }
                        pickPage._matching = false
                        console.log("[ImagePicker] matched " + pickPage.currentResults.length + " results, user color h=" + userColor.h + " s=" + userColor.s + " v=" + userColor.v)
                        if (pickPage.currentResults.length === 0) {
                            toast.warn("未找到匹配物种, 试试换张照片")
                        }
                    }
                }

                // 候选结果列表
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: CommonOptions.colorSurface
                    radius: 6
                    visible: pickPage.currentResults.length > 0

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        clip: true

                        model: pickPage.currentResults
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 80
                            color: CommonOptions.colorSurface
                            radius: 4

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                // 相似度大圆
                                Rectangle {
                                    Layout.preferredWidth: 60
                                    Layout.preferredHeight: 60
                                    radius: 30
                                    color: modelData.similarity >= 70 ? CommonOptions.colorSuccess :
                                           modelData.similarity >= 40 ? CommonOptions.colorWarn : CommonOptions.colorDanger
                                    Text {
                                        anchors.centerIn: parent
                                        text: Math.round(modelData.similarity) + "%"
                                        color: "white"
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: modelData.commonName || "未知"
                                        color: CommonOptions.colorText
                                        font.pixelSize: 14
                                        font.bold: true
                                    }
                                    // 2026-09-20: 危险等级 chip 统一 (5 阶段架构重构 Phase 3 接入)
                                    RowLayout {
                                        spacing: 6
                                        DangerChip {
                                            level: modelData.dangerLevel || 0
                                            compact: true
                                        }
                                        Text {
                                            text: modelData.category || ""
                                            color: CommonOptions.colorTextMuted
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 底部免责声明
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: CommonOptions.colorDanger
            visible: pickPage.currentResults.length > 0
            Text {
                anchors.fill: parent
                anchors.margins: 8
                text: "\ue002 相似度仅供参考,务必对照图鉴二次确认"  // Material Icons: warning
                font.family: "Material Icons"
                color: "white"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
    }

    // 2026-09-11: FileDialog 从相册选图
    // 2026-09-16: 兼容 Qt 6.7 新 API (currentFile) 和 旧 API (selectedFile)
    FileDialog {
        id: fileDialog
        title: "选择图片"
        nameFilters: ["图片文件 (*.jpg *.jpeg *.png)", "所有文件 (*)"]
        onAccepted: {
            // 优先 currentFile (Qt 6.7+), 退回 selectedFile
            var url = ""
            if (currentFile && currentFile.toString().length > 0) {
                url = currentFile.toString()
            } else if (selectedFile && selectedFile.toString().length > 0) {
                url = selectedFile.toString()
            }
            if (url.length > 0) {
                // 2026-09-16: Android 11+ FileDialog 返回 content:// URI
                // 1) 设 currentImageSource 让 Image 显示 (Qt 6.7 Image 支持 content://)
                // 2) 调 importImage 复制到沙盒,得到本地路径给 ImageColorExtractor
                pickPage.currentImageSource = url
                if (androidPlatform && androidPlatform.importImage) {
                    var local = androidPlatform.importImage(url)
                    if (local && local.length > 0) {
                        pickPage.currentImagePath = local
                    } else {
                        // 已经是 file://, 直接剥前缀
                        pickPage.currentImagePath = url.replace(/^file:\/\//, "")
                    }
                } else {
                    pickPage.currentImagePath = url.replace(/^file:\/\//, "")
                }
                console.log("[ImagePicker] selected: " + pickPage.currentImagePath)
            } else {
                console.warn("[ImagePicker] FileDialog 接受但 selectedFile/currentFile 都空")
            }
        }
    }

    // 2026-09-16: 监听拍照完成 signal, 设 currentImageSource + currentImagePath
    Connections {
        // 2026-09-17: 去掉 typeof 包装 (QML context property typeof 永远 undefined)
        target: androidPlatform ? androidPlatform : null
        function onPhotoTaken(uri) {
            if (uri && uri.length > 0) {
                pickPage.currentImageSource = uri
                pickPage.currentImagePath = uri.replace(/^file:\/\//, "")
                console.log("[ImagePicker] photo taken: " + pickPage.currentImagePath)
            }
        }
    }
}
