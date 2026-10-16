/**
 * @file EmergencyContactsPage.qml
 * @brief 紧急联系人管理
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: contactsPage
    title: "紧急联系人"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        Text {
            text: "紧急联系人将在 SOS 触发时收到短信（含您的位置）"
            color: "#B0BEC5"
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            model: ServiceListModel {
                id: contactModel
                service: emergencyService
                method: "getContacts"
            }
            delegate: Rectangle {
                width: ListView.view.width
                height: 70
                color: CommonOptions.colorSurface
                radius: 4

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 12
                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: model.isPrimary ? "#D32F2F" : "#455A64"
                        Text {
                            anchors.centerIn: parent
                            text: model.isPrimary ? "★" : "●"
                            color: "white"
                            font.pixelSize: 18
                        }
                    }
                    Column {
                        Layout.fillWidth: true
                        Text {
                            text: model.name
                            color: CommonOptions.colorText
                            font.pixelSize: 16
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: model.phone
                            color: "#90A4AE"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    Column {
                        spacing: 4
                        Button {
                            text: "主联系人"
                            flat: true
                            visible: !model.isPrimary
                            onClicked: {
                                // 2026-09-20: 用 index (ListModel delegate 索引) + id 双保险
                                emergencyService.setPrimary(index)
                                Qt.callLater(refresh)
                            }
                        }
                        Button {
                            text: "删除"
                            flat: true
                            Material.foreground: "#FF5252"
                            // 2026-09-21: Phase 5 切到 Result. deleteContact 现在返回
                            // {ok, value, error}, 失败用 Toast.error 提示.
                            onClicked: {
                                var r = emergencyService.deleteContact(index)
                                if (!r.ok) {
                                    toast.error(r.error.message || "删除失败")
                                } else {
                                    Qt.callLater(refresh)
                                }
                            }
                        }
                    }
                }
            }

            function refresh() {
                // 2026-09-20: 用 ServiceListModel 替代 clear+for+append 模板 (Phase 3)
                Qt.callLater(function() { contactModel.refresh() })
            }

            Component.onCompleted: refresh()
        }

        // 添加按钮
        Button {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            text: "+ 添加联系人"
            Material.background: "#1976D2"
            onClicked: addDialog.open()
        }
    }

    Dialog {
        id: addDialog
        title: "添加联系人"
        modal: true
        anchors.centerIn: parent
        width: parent.width * 0.9

        contentItem: ColumnLayout {
            spacing: 12
            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "姓名"
            }
            TextField {
                id: phoneField
                Layout.fillWidth: true
                placeholderText: "电话"
                inputMethodHints: Qt.ImhDialableCharactersOnly
            }
            TextField {
                id: relationField
                Layout.fillWidth: true
                placeholderText: "关系（如：家人）"
            }
            CheckBox {
                id: primaryCheck
                text: "设为主联系人"
                // 2026-09-20: contentItem.color 是 Control.Label.color, Material 风格不响应.
                // 改用 Material.foreground (主题色) 让色统一.
                Material.foreground: CommonOptions.colorText
            }
            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: "取消"
                    flat: true
                    onClicked: addDialog.close()
                }
                Button {
                    text: "保存"
                    highlighted: true
                    onClicked: {
                        // 2026-09-21: Phase 5 切到 Result. addContact 返回 {ok, value, error}.
                        var name = (nameField.text || "").trim()
                        var phone = (phoneField.text || "").trim()
                        if (name.length === 0 || phone.length === 0) {
                            toast.error("姓名和电话不能为空")
                            return
                        }
                        var r = emergencyService.addContact(
                            name,
                            phone,
                            relationField.text,
                            primaryCheck.checked)
                        if (r.ok) {
                            addDialog.close()
                            Qt.callLater(listView.refresh)
                            toast.success("已添加联系人")
                        } else {
                            toast.error(r.error.message || "保存失败, 请重试")
                        }
                    }
                }
            }
        }
        // 2026-09-20: 无论成功失败, 关闭后统一清空输入, 避免下次打开看到旧值.
        onClosed: {
            nameField.text = ""
            phoneField.text = ""
            relationField.text = ""
            primaryCheck.checked = false
        }
    }
}
