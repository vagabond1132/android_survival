/**
 * @file SheetPanelHead.qml
 * @brief 地图工作台「面板头」一行: 图标 + 标题 + 读数 + (可选) 内嵌搜索框 + 收起
 *
 * 2026-10-28 #156 新建. 语法抄自用户提供的 5 张两步路工作台真机截图
 * (pass9/ref/lbw1..5, 与本应用测试机同一台机器、density 3.0, 所以尺寸是量出来的):
 *   标题、范围、搜索框、关闭挤在**同一行 44 逻辑高**里; 排序与筛选是下面第二行的
 *   chips, 不占列表高度. 我们原来是一张 SectionTitle + 一行独立控件, 四块各占一行,
 *   于是 480 高的抽屉里列表只剩 3.5 行 (pass9 ④「内容堆顶 + 中部死白」).
 *
 * 为什么做成共用件而不是四个 Tab 各画一遍: 同一形状出现 4 次, 逐页打补丁正是
 * pass6 收口时点过的坑.
 *
 * 尺寸口径:
 *   - 整行 btnH(44) = 实测 132 raw ÷ 3.
 *   - 搜索框 btnHSm(32) = 实测 96 raw ÷ 3. 两步路实测就是 32, 不再往 44 的
 *     "最小可点高度"上靠 —— 输入框的热区是整条字段, 不是里面的光标.
 */
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

RowLayout {
    id: head

    Styles { id: styles; visible: false }

    property string iconName: ""
    property string title: ""
    // 标题右边的读数 ("18 项" / "3 条"). 空串则这一格整段不出现 (不给假读数).
    property string trailing: ""
    // 非空 = 画内嵌搜索框; 空 = 标题与收起之间留弹簧.
    property string searchPlaceholder: ""
    property alias searchText: searchField.text
    // 读数的语气: "warn" 给 blaze (录制中), 默认走次要文字色.
    property string trailingTone: ""

    signal searchSubmitted()
    signal foldRequested()

    Layout.fillWidth: true
    Layout.preferredHeight: styles.btnH
    spacing: styles.spSm

    IconLabel {
        visible: head.iconName.length > 0
        name: head.iconName
        size: styles.icMd
        tintColor: CommonOptions.colorAccentSoft
    }

    Text {
        text: head.title
        font.pixelSize: styles.fsLg
        font.bold: true
        color: CommonOptions.colorText
        elide: Text.ElideRight
        Layout.maximumWidth: styles.icBoxLg * 3
    }

    Text {
        visible: head.trailing.length > 0
        // 这一格可能带汉字 ("18 项"), 不许走 monoFont —— 见 [[qml-monofont-no-cjk]]
        text: head.trailing
        font.pixelSize: styles.fsSm
        color: head.trailingTone === "warn" ? CommonOptions.colorBlaze
                                            : CommonOptions.colorTextDim
        elide: Text.ElideRight
    }

    // 没有搜索框时, 弹簧负责把收起键顶到右缘; 有搜索框时让位给它
    Item {
        visible: head.searchPlaceholder.length === 0
        Layout.fillWidth: true
    }

    TextField {
        id: searchField
        visible: head.searchPlaceholder.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: styles.btnHSm
        placeholderText: head.searchPlaceholder
        placeholderTextColor: CommonOptions.colorTextDim
        color: CommonOptions.colorText
        font.pixelSize: styles.fsMd
        leftPadding: styles.spSm
        rightPadding: styles.spSm
        topPadding: 0
        bottomPadding: 0
        verticalAlignment: Text.AlignVCenter
        background: Rectangle {
            radius: styles.rPill
            color: CommonOptions.colorSurfaceAlt
            border.color: CommonOptions.colorDivider
            border.width: styles.lineHair
        }
        onAccepted: head.searchSubmitted()
    }

    Rectangle {
        Layout.preferredWidth: styles.btnHSm
        Layout.preferredHeight: styles.btnHSm
        Layout.alignment: Qt.AlignVCenter
        radius: styles.rSm
        color: foldTap.pressed ? CommonOptions.colorSurfaceDim
                               : CommonOptions.colorSurface
        border.color: CommonOptions.colorDivider
        border.width: styles.lineHair
        IconLabel {
            anchors.centerIn: parent
            name: "close"
            size: styles.icSm
            tintColor: CommonOptions.colorTextMuted
        }
        TapHandler { id: foldTap; onTapped: head.foldRequested() }
    }
}
