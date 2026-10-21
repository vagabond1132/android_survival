/**
 * @file Section.qml
 * @brief 通用章节组件 (2026-09-14 建立, 2026-10-16 整体改版补全 token)
 *
 * 之前硬编码 "white" / "#37474F" / "#90A4AE" 全部换为 CommonOptions,
 * 本轮把剩下的尺寸字面量 (16 / 8 / 14 / radius 8) 也换成 Styles token.
 *
 * 注意 Styles 的实例化方式: 本组件根节点是 ColumnLayout, 而 Qt Quick Layouts
 * 不参与布局的隐藏项会被忽略, 所以必须写 visible: false, 否则会在章节末尾
 * 多出一行 0 高度 + 一个 spacing 的空隙.
 */

// 2026-10-19 真机 stage0.log: delegate 里引用外层 id (如 categorySection / searchDialog) 在 qmlcachegen
// 编译下会抛 ReferenceError, 必须 Bound 语义才能拿到外层组件作用域.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import OutdoorSurvival 1.0

ColumnLayout {
    id: sectionRoot
    property string title: ""
    // 2026-10-16 改版: 图标一律用 IconLabel 语义名 (如 "warning").
    //   原先还留了一条 titleIcon 裸码位过渡通道, 2026-10-19 Wave 3 把最后
    //   11 处调用方换完后已无人使用, 故删除 —— 保留它只会诱导新代码又写
    //   "\ue1xx", 而那些码位并没有经过字形核对.
    property string titleIconName: ""
    property var items: []
    property color textColor: CommonOptions.colorText
    property string prefix: ""
    property bool asInline: false
    property int itemSpacing: 8

    Styles { id: styles; visible: false }

    Layout.fillWidth: true
    Layout.margins: styles.spLg
    spacing: styles.spSm

    RowLayout {
        Layout.fillWidth: true
        spacing: styles.spXs
        // 首选: 语义名走 SectionTitle (内部 IconLabel, 带字体就绪判断)
        SectionTitle {
            visible: sectionRoot.titleIconName.length > 0
            Layout.fillWidth: true
            icon: sectionRoot.titleIconName
            text: sectionRoot.title
        }
        // 无图标时只出标题
        Text {
            visible: sectionRoot.titleIconName.length === 0
            text: sectionRoot.title
            color: CommonOptions.colorText
            font.pixelSize: styles.fsLg
            font.bold: true
        }
    }

    // 2026-09-11 (#15): Repeater model 用本地 ListModel, 避免 non-NOTIFYable 警告
    ListModel { id: _itemsModel }

    onItemsChanged: _refreshItems()
    Component.onCompleted: _refreshItems()

    function _refreshItems() {
        _itemsModel.clear()
        if (items) {
            for (var i = 0; i < items.length; ++i) {
                _itemsModel.append({ "value": items[i] })
            }
        }
    }

    Repeater {
        model: _itemsModel
        delegate: Loader {
            Layout.fillWidth: true
            sourceComponent: sectionRoot.asInline ? inlineItem : blockItem
            // 2026-09-19: Loader 内可访问 model, 但 Component 根 Item 拿不到.
            //   用 onItemChanged 把 model.value 显式塞到 item 的属性上.
            onItemChanged: {
                if (item) {
                    // 2026-09-21: 用 String() 强转. 之前 model.value 是 QJSValue 类型,
                    //   直接赋给 QString textValue 会报 "Cannot assign QJSValue to QString"
                    //   (Section.qml:71, app_log.txt 反复出现 50+ 次). String() 包一层
                    //   自动调 toString(), 转成原生 JS string 再赋 QString 兼容.
                    item.textValue = (model.value !== undefined && model.value !== null)
                                     ? String(model.value) : ""
                }
            }
        }
    }

    Component {
        id: blockItem
        Rectangle {
            id: blockRoot
            property string textValue: ""
            color: CommonOptions.colorSurface
            radius: styles.rMd
            border.color: CommonOptions.colorDivider
            border.width: styles.lineHair
            Layout.fillWidth: true
            implicitHeight: itemText.implicitHeight + styles.cardPad * 2

            Text {
                id: itemText
                anchors.fill: parent
                anchors.margins: styles.cardPad
                text: sectionRoot.prefix + blockRoot.textValue
                color: sectionRoot.textColor
                font.pixelSize: styles.fsMd
                wrapMode: Text.WordWrap
            }
        }
    }

    Component {
        id: inlineItem
        Text {
            id: inlineRoot
            property string textValue: ""
            text: "• " + inlineRoot.textValue
            color: sectionRoot.textColor
            font.pixelSize: styles.fsMd
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
