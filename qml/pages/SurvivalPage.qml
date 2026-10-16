/**
 * @file SurvivalPage.qml
 * @brief 避险主页
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: survivalPage
    title: "避险 / 生存"

    property int currentTab: 0  // 0:取火 1:庇护所 2:工具 3:净水
    // 2026-09-20: 加 timestamp 触发 TabBar 重算, 避免 service 加载完成后
    //   counts 还停在初始 0.
    property int _countsTick: 0

    Connections {
        target: survivalService
        // 2026-09-20: dataChanged signal 在 ServiceRegistry::loadDataAll 完成后触发,
        //   此时 fireMethodsCount / shelterCount / toolCount 才反映真实数据.
        //   bump _countsTick 让 TabBar text binding 重算.
        function onDataChanged() { survivalPage._countsTick++ }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 顶部 Tab (text 引用 _countsTick 让数据加载后自动刷新)
        TabBar {
            Layout.fillWidth: true
            TabButton {
                // 2026-09-20: 用 _countsTick 注入到 binding 让 onDataChanged
                //   能强制重算 text (text 默认绑定在 service.fireMethodsCount,
                //   但 service 是同一引用, 数值变了 binding 应该自动跟踪;
                //   这里加 _countsTick 是兜底, 防止某些 service 缓存不更新).
                text: survivalPage._countsTick + 0 < 0 ? "" :
                      ("\ue25d 取火 (" + survivalService.fireMethodsCount + ")")
                font.family: "Material Icons"
            }
            TabButton {
                text: "\ue563 庇护所 (" + survivalService.shelterCount + ")"
                font.family: "Material Icons"
            }
            TabButton {
                text: "\ue14c 工具 (" + survivalService.toolCount + ")"
                font.family: "Material Icons"
            }
        }

        // 列表
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: survivalPage.currentTab

            Repeater {
                model: 4
                delegate: SurvivalList {
                    topic: model.index
                }
            }
        }
    }
}
