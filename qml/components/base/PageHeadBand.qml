/**
 * @file PageHeadBand.qml
 * @brief 二级页页首标题条 —— 微标签 / 页名 / 读数行 + 右上角控件 (2026-11-03 #42, 定律 L3+L13)
 *
 * 为什么要有这个组件: 12 个二级页各写了一份逐字节相同的标题条, 数写死在页里
 *   (54 高 / 右缘让位 40 / 返回方块 26 / 热区外扩 9), 编号角标那两页又各写 56 与 64.
 *   "同类控件全站一套几何"要求只有一个地方能改 —— 复制体的问题是下一次改字号时
 *   一定有人漏一页, 而漏掉的那页在真机上看起来就是"这页排版不对".
 *
 * 右上角放什么: plateCode 非空 = 图鉴编号角标 (图鉴索引 / 求助页), 否则 = 返回方块;
 *   两者都不要 (①营地 / 「我」这两个 tab 页) 用 showBack: false。
 *   让位量现算 (控件实际宽 + spMd), 不再各页写死; 编号宽度随内容变, 写死的 56/64
 *   本来就是"照着一屏数出来的"。
 *
 * 高度侧的另一半在 page_fill_check.js: 页根 ColumnLayout 必须有一个吃剩余高度的子项,
 *   否则这一条会被顶下去 (真机 F5: 紧急联系人页返回方块 device y 266→454).
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Item {
    id: band

    Styles { id: styles; visible: false }

    property string eyebrowText: ""
    // 装备页的微标签走等宽族; CJK 永远不加字距, 这条只给拉丁微标签用
    property bool eyebrowMono: false
    required property string titleText
    property string statusText: ""
    // 索引类页读数行用 fsSm + colorTextMuted, 其余用 fsXs + colorInk3
    property int statusSize: styles.fsXs
    property color statusColor: CommonOptions.colorInk3
    // 非空 = 右上角放编号而不是返回方块
    property string plateCode: ""
    property color plateTone: CommonOptions.colorInk3
    // 顶级 tab 页 (营地 / 我) 既没有返回方块也没有角标 —— 右上角空着.
    //   不加这个开关就得给这类页再写一份复制体, 而那正是本组件要消灭的东西.
    property bool showBack: true

    signal backClicked

    // 右上角控件实际占宽 (0 = 右上角什么都没有). 让位 = 实际占宽 + 一格间距,
    // 所以「①-④ 哪一格」「10:42 还是 9:9」换字都不会挤到读数行.
    readonly property real headReserve:
        band.plateCode.length > 0 ? plateText.implicitWidth
                                  : (band.showBack ? styles.pageHeadBox : 0)

    Layout.fillWidth: true
    // 2026-11-04 真机 (#42 / 定律 L6-1，0.0.7 走查 A 组判 FAIL): 高度不许小于内容自然高。
    //   原来只写 styles.pageHeadH = 54，而三行 (微标签 + 页名 + 读数行) 的自然高更大，
    //   下面那个 Column 又是 anchors.bottom 贴底 —— 溢出只能往上冒。
    //   真机读数: 营地页与求助页的微标签上缘 283、band 顶 279，字的上半被切成 8 设备 px，
    //   因为这两页把 band 放进了 `ScrollView/Flickable { clip: true }` (不裁的话末段会画进
    //   底部导航条)，其余 9 页同样溢出但没有裁剪祖先所以看着没事。
    //   取 max 而不是把 token 调大: 字号是 Styles 里的活值，写死一个"够用的数"
    //   下一次改字号就会再切一次。门禁 page_head_check.js 第 ⑤ 条守这一行。
    Layout.preferredHeight: Math.max(styles.pageHeadH, headCol.implicitHeight)
    Layout.leftMargin: styles.pageMargin
    Layout.rightMargin: styles.pageMargin

    Column {
        id: headCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // 给右上角让位, 否则读数行从它底下穿过
        anchors.rightMargin: band.headReserve > 0 ? band.headReserve + styles.spMd : 0
        spacing: 3

        Text {
            visible: band.eyebrowText.length > 0
            text: band.eyebrowText
            font.pixelSize: styles.fsXs
            // 非 mono 时留空串 (= 继承全局字体), 这是本仓已有的写法 (IconLabel.qml:146 同款).
            //   不要写 Font.defaultFamily —— qmllint 报 "Member defaultFamily not found on type
            //   QQuickFontEnums", Qt Quick 的 Font 枚举里没有这个成员。
            font.family: band.eyebrowMono ? styles.monoFont : ""
            font.letterSpacing: band.eyebrowMono ? 1.8 : 0
            color: CommonOptions.colorInk3
        }
        Text {
            width: parent.width
            text: band.titleText
            font.pixelSize: styles.fs2xl
            font.bold: true
            color: CommonOptions.colorText
            elide: Text.ElideRight
        }
        Text {
            visible: band.statusText.length > 0
            width: parent.width
            text: band.statusText
            font.pixelSize: band.statusSize
            color: band.statusColor
            elide: Text.ElideRight
        }
    }

    // 返回方块: 26px 描边方块, 热区向外扩 9px 到 44 (戴手套)
    Rectangle {
        id: backBox
        visible: band.showBack && band.plateCode.length === 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: styles.spXs
        width: styles.pageHeadBox
        height: styles.pageHeadBox
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
            anchors.margins: -styles.pageHeadTapPad
            cursorShape: Qt.PointingHandCursor
            onClicked: band.backClicked()
        }
        // L7: 可交互项必须挂 Accessible (真机 pass 2 全程取不到元素坐标, 只能靠像素换算)
        Accessible.role: Accessible.Button
        Accessible.name: "返回"
        Accessible.onPressAction: band.backClicked()
    }

    Plate {
        id: plateText
        visible: band.plateCode.length > 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        code: band.plateCode
        tone: band.plateTone
    }
}
