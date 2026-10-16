/**
 * @file CategorySection.qml
 * @brief 装备清单分类区块 (2026-09-14 token 化, 轻量化)
 *
 * 原则: 大面积统一 colorSurface, 只在小色点 / 标题前 emoji 上体现分类色.
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

ColumnLayout {
    id: categorySection
    property string title: ""
    // 2026-09-19: 新增 titleIcon (Material Icons codepoint) + titleIconFont,
    //   替代原来 title 里嵌 emoji 的写法. emoji 在系统字体下经常渲染为 X.
    property string titleIcon: ""
    property string titleIconFont: "Material Icons"
    property color accentColor: CommonOptions.colorAccent
    property var items: []
    // 2026-09-19: 修 - 之前写 true (bool) 赋给 int 属性, qmlcachegen 静态编译下
    //   会报 "Invalid property assignment: int expected", 让 CategorySection
    //   整个无法实例化, 装备清单详情页因此空白
    property int defaultExpanded: 1
    // 2026-09-20: listId 用于装备勾选回写到对应清单 (equipmentService.setItemChecked)
    property string listId: ""

    // 2026-09-28: 勾选写回后通知父页面 refresh(). 之前 onToggled 里丢弃 setItemChecked
    //   的 Result 且不刷新, 父页面 entity 里的 checked 字段永远是旧值 → 勾选"不保存"
    //   (视觉上勾了, 但重进页面 / 滚动复用 delegate 后回退).
    signal itemCheckToggled(string listId)

    Layout.fillWidth: true
    // 2026-09-23: 修 - 之前 Layout.margins: 16 + Layout.topMargin: 8, 在 4 个
    //   CategorySection 串联时, 上一个的 bottomMargin (16) + 下一个的
    //   topMargin (8) = 24px 空白, 但**间距不均**且标题 RowLayout 高度
    //   隐式计算 (没给 preferredHeight), qmlcachegen 静态编译下标题行偶尔
    //   implicitHeight = 0, 标题被下方 Rectangle 覆盖 → "标题和数据叠在一起".
    //   修法: 标题显式 preferredHeight: 28, Rectangle 显式 preferredHeight
    //   = items.length * 48 + 2, 外层全用 Layout.spacing 不用 margins.
    spacing: 12
    Layout.topMargin: 4
    Layout.bottomMargin: 4

    // 标题 (轻量: 小色点 + 文字) - 显式高度防止 implicit 计算异常
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        Layout.leftMargin: 4
        spacing: 8

        Rectangle {
            width: 8
            height: 8
            radius: 4
            color: categorySection.accentColor
        }
        Text {
            visible: categorySection.titleIcon.length > 0
            text: categorySection.titleIcon
            font.family: categorySection.titleIconFont
            color: CommonOptions.colorText
            font.pixelSize: 14
        }
        Text {
            text: categorySection.title + "  (" + categorySection.items.length + ")"
            color: CommonOptions.colorText
            font.pixelSize: 14
            font.bold: true
            Layout.fillWidth: true
        }
    }

    // 项目列表 (统一卡片, 不用分类色) - 显式 preferredHeight 防止 implicit 计算异常
    Rectangle {
        Layout.fillWidth: true
        // 2026-09-23: 改 - 之前依赖内部 Repeater 撑 implicitHeight, 但项目
        //   子 Rectangle 的 Layout.preferredHeight: 48 + 内层 ColumnLayout
        //   anchors.fill: parent, 在 qmlcachegen 静态编译下 implicitHeight 计算
        //   可能比实际小, 出现"标题与第一行数据重叠"现象.
        //   显式 preferredHeight: items.length * 48 + 2 保证高度正确.
        Layout.preferredHeight: Math.max(categorySection.items.length * 48 + 2, 50)
        color: CommonOptions.colorSurface
        radius: 8
        border.color: Qt.darker(CommonOptions.colorSurface, 1.15)
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            Layout.alignment: Qt.AlignTop

            Repeater {
                model: categorySection.items
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    color: CommonOptions.colorSurface

                    // 2026-09-20: modelData 可能是 {item, checked} 包装, 也可能是裸 EquipmentItem.
                    // 兼容两种, 用 _item / _checked 两个 readonly prop 集中处理.
                    readonly property var _item: (modelData && modelData.item) ? modelData.item : modelData
                    readonly property bool _checked: (modelData && "checked" in modelData) ? !!modelData.checked : false

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        CheckBox {
                            checked: parent.parent._checked
                            onToggled: {
                                // 2026-09-28: 接收 Result 判错 + 通知父页面刷新.
                                //   之前丢弃返回值且不 refresh, 勾选状态无法持久回显.
                                if (equipmentService && parent.parent._item) {
                                    var r = equipmentService.setItemChecked(
                                        categorySection.listId,
                                        parent.parent._item.id || parent.parent._item.name,
                                        checked)
                                    if (r && r.ok === false) {
                                        toast.error(r.error.message || "勾选失败")
                                    }
                                    categorySection.itemCheckToggled(categorySection.listId)
                                }
                            }
                        }

                        Text {
                            text: parent.parent._item ? (parent.parent._item.name || "") : ""
                            color: parent.parent._checked ? CommonOptions.colorTextMuted : CommonOptions.colorText
                            font.pixelSize: 14
                            font.strikeout: parent.parent._checked
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: parent.parent._item ? ((parent.parent._item.weightG || 0) + "g") : ""
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: 12
                        }

                        Text {
                            text: "ⓘ"
                            color: CommonOptions.colorTextMuted
                            font.pixelSize: 14
                        }
                    }
                }
            }
        }
    }
}
