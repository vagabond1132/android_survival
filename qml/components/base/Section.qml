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

    // 条目区外框 —— 2026-10-22 #96(b):
    //   之前每条 blockItem 自带 border.color, "识别特征" 的 4 条被画成 4 张各自描边的
    //   独立卡, 读起来像 4 个互不相干的模块; 可它们其实是同一个字段 (features) 的 4 个
    //   值. 改成外框一条描边 + 条目之间 1px 分隔线, 与全站"一张卡装一个字段"一致.
    //   inline 模式没有底板语义, 所以底色/描边一起关掉, 只留条目间距.
    Rectangle {
        Layout.fillWidth: true
        visible: _itemsModel.count > 0
        color: sectionRoot.asInline ? "transparent" : CommonOptions.colorSurface
        border.color: CommonOptions.colorDivider
        border.width: sectionRoot.asInline ? 0 : styles.lineHair
        // 高度跟着内层布局的 implicitHeight: 若改成 layout anchors.fill 本框, 折行文本
        // 的高度要等宽度、宽度又来自本框高度 → 绑定环.
        implicitHeight: itemsCol.implicitHeight

        ColumnLayout {
            id: itemsCol
            width: parent.width
            // 有分隔线时条目之间不留空隙 (线就是边界); inline 模式才用 itemSpacing
            spacing: sectionRoot.asInline ? sectionRoot.itemSpacing : 0

            Repeater {
                model: _itemsModel
                delegate: Loader {
                    required property var model
                    required property int index
                    Layout.fillWidth: true
                    sourceComponent: sectionRoot.asInline ? inlineItem : blockItem
                    // 2026-10-21: 本文件有 pragma ComponentBehavior: Bound, delegate 不再能看见
                    //   视图注入的 `model` 上下文属性 (真机 ReferenceError), 必须 required property 声明。
                    //   Component 根 Item 本来就拿不到 model, 所以仍用 onItemChanged 显式塞值。
                    onItemChanged: {
                        if (item) {
                            // 2026-09-21: 用 String() 强转. 之前 model.value 是 QJSValue 类型,
                            //   直接赋给 QString textValue 会报 "Cannot assign QJSValue to QString"
                            //   (Section.qml:71, app_log.txt 反复出现 50+ 次). String() 包一层
                            //   自动调 toString(), 转成原生 JS string 再赋 QString 兼容.
                            item.textValue = (model.value !== undefined && model.value !== null)
                                             ? String(model.value) : ""
                            // 两条 Component 都声明 first: Loader 只有一份, 赋给谁都得存在
                            item.first = index === 0
                        }
                    }
                }
            }
        }
    }

    Component {
        id: blockItem
        Rectangle {
            id: blockRoot
            property string textValue: ""
            /// 首条不画顶部分隔线 (外框已经给了上边)
            property bool first: true
            color: "transparent"
            Layout.fillWidth: true
            implicitHeight: itemText.implicitHeight + styles.cardPad * 2

            // 条目间 1px 分隔线: 只有外框模式用得上
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: styles.lineHair
                visible: !blockRoot.first
                color: CommonOptions.colorDivider
            }

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
            // 与 blockItem 同形状: Loader 只有一份 delegate, 两边都得接着 `first`
            // (inline 没有分隔线, 收到值也不画)
            property bool first: true
            text: "• " + inlineRoot.textValue
            color: sectionRoot.textColor
            font.pixelSize: styles.fsMd
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
