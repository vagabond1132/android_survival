/**
 * @file EmergencyContactsPage.qml
 * @brief SOS 收件人名册管理 (2026-10-20 v9 F1 目录母版 + 写操作, 丁骨架二级页)
 *
 * 入口: SOSPage 的「紧急联系人 · 添加」与 MePage 的功能入口 (都是 push, 所以标题条
 *       右上留 26px 方角返回).
 * 数据: emergencyService 的 emergency_contacts 表 (id / name / phone / relation /
 *       is_primary), getContacts 是 Result 包装, 顺序 = is_primary DESC, id ASC.
 *
 * 版式 (同 FieldGuidePage / EquipmentPage 的目录母版):
 *   标题条 54px: SOS RECIPIENTS 微标签 / 「紧急联系人」21px / 读数行 + 方角返回.
 *   读数带  3 格 (名册 N / 主联系人 / 关系已填), 数字全是数组计数.
 *   名册    一行一个人: 姓名 + 「主」方块 + 关系 / 等宽号码 / 两枚 32px 动作方块.
 *   底栏    1px 墨线 + colorSurfaceAlt: 常驻 note + 左「返回」88px, 右实心「添加」.
 *   弹层    添加/编辑共用一张表单 (dlgMode 决定走 addContact 还是 updateContact);
 *           删除单独一张确认 Dialog —— 三张 Dialog 的按钮文案都是中文.
 *
 * 三条不能破的规则:
 *   ① 这一页只写名册, 不拨号也不发短信. 号码在这里是纯读数; 真要拨号/发定位短信,
 *      只有⑤求助页那两颗 HoldConfirmRow (长按 2~3 秒) 一个入口. 这是全站铁律,
 *      所以本页连一行"点号码就拨"都没有.
 *   ② 「主」只决定顺序. sendSosSMSToAll 给名单里**每一个人**发同一条定位短信,
 *      is_primary 在 C++ 侧只进 ORDER BY, 不参与收件人筛选. 改版前一个"设为主要"
 *      的按钮加"主联系人"胶囊很容易读成"先打给他" —— 读数行与说明行把这件事写明.
 *   ③ 写操作的结果常驻, 不弹 3 秒就走. 新增/编辑/删除/读取失败都写进 note,
 *      由底栏上方那一行显示 (与 EquipmentPage 同一口径); 因此本页不再引用 toast,
 *      也不再需要 ServiceListModel 的 notifier 注入 —— 名单自己 load(), 才能拿到
 *      Result 里的 error.message 原文.
 */

// delegate 里读 contactsPage 与 cell.enabled, qmlcachegen 静态编译下必须 Bound.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Page {
    id: contactsPage

    Styles { id: styles; visible: false }

    title: "紧急联系人"
    background: Rectangle { color: CommonOptions.colorBg }

    property var rows: []
    property string note: ""
    // "add" = 新增, "edit" = 改 rows[dlgIndex]
    property string dlgMode: "add"
    property int dlgIndex: -1

    readonly property int contactCount: rows.length
    readonly property int primaryCount: {
        var n = 0
        for (var i = 0; i < rows.length; ++i) if (rows[i].primary) ++n
        return n
    }
    readonly property int relationCount: {
        var n = 0
        for (var k = 0; k < rows.length; ++k)
            if (rows[k].relation.length > 0) ++n
        return n
    }

    function goBack() {
        var win = ApplicationWindow.window
        if (win && win.navBus) win.navBus.back()
    }
    function _toArr(v) { return (v && v.length !== undefined) ? v : [] }
    // getContacts 返回 Result{ok, value:[{id,name,phone,relation,isPrimary}]}
    function load() {
        if (!emergencyService) { contactsPage.rows = []; return }
        var r = emergencyService.getContacts()
        if (r && r.ok === false) {
            contactsPage.rows = []
            contactsPage.note = "名单没读到: " + ((r.error && r.error.message) || "未知错误")
            return
        }
        var src = contactsPage._toArr(r && r.value !== undefined ? r.value : r)
        var out = []
        for (var i = 0; i < src.length; ++i) {
            var c = src[i]
            out.push({
                // 顺序即 service 顺序: deleteContact/updateContact 只认位置 index
                name: String(c.name || ""),
                phone: String(c.phone || ""),
                relation: String(c.relation || ""),
                primary: c.isPrimary === true
            })
        }
        contactsPage.rows = out
    }

    // 写操作统一收口: 拿到 Result 就照抄 error.message, 成功就重读名册
    function _report(r, fallback) {
        if (r && r.ok === false) {
            contactsPage.note = fallback + ": " + ((r.error && r.error.message) || "未知错误")
            return false
        }
        contactsPage.note = ""
        contactsPage.load()
        return true
    }

    function openAdd() {
        contactsPage.dlgMode = "add"
        contactsPage.dlgIndex = -1
        contactsPage.note = ""
        addDialog.open()
    }

    function openEdit(idx) {
        var c = contactsPage.rows[idx]
        if (!c) return
        contactsPage.dlgMode = "edit"
        contactsPage.dlgIndex = idx
        contactsPage.note = ""
        nameField.text = c.name
        phoneField.text = c.phone
        relationField.text = c.relation
        primaryCheck.checked = c.primary
        addDialog.open()
    }

    function acceptDialog() {
        var nm = nameField.text.trim()
        var ph = phoneField.text.trim()
        if (!emergencyService) { contactsPage.note = "急救服务还没就绪, 写不进去"; return }
        if (nm.length === 0 || ph.length === 0) {
            contactsPage.note = "姓名和号码都不能空 —— 空号收不到定位短信"
            return
        }
        var r
        if (contactsPage.dlgMode === "edit" && contactsPage.dlgIndex >= 0)
            r = emergencyService.updateContact(contactsPage.dlgIndex, nm, ph,
                                               relationField.text.trim(),
                                               primaryCheck.checked)
        else
            r = emergencyService.addContact(nm, ph, relationField.text.trim(),
                                            primaryCheck.checked)
        if (contactsPage._report(r, contactsPage.dlgMode === "edit" ? "保存失败" : "添加失败"))
            addDialog.close()
    }

    function removeContact() {
        var idx = confirmDeleteDialog.delIndex
        confirmDeleteDialog.close()
        if (!emergencyService || idx < 0 || idx >= contactsPage.rows.length) return
        var nm = contactsPage.rows[idx].name
        contactsPage._report(emergencyService.deleteContact(idx), "移除失败 (" + nm + ")")
    }

    // 行内动作方块: 32px 面 + 外扩 6px 热区 = 44 (戴手套). 内联组件看不到外层 styles
    //   id, 自带一个 (与 EquipmentPage 的同名件同构).
    component ActionCell: Rectangle {
        id: cell
        property string iconName: ""
        property color tone: CommonOptions.colorText
        signal clicked()

        Styles { id: cellStyles; visible: false }

        implicitWidth: 32
        implicitHeight: 32
        radius: cellStyles.rSm
        color: CommonOptions.colorSurface
        border.color: CommonOptions.colorRule
        border.width: cellStyles.lineHair

        IconLabel {
            anchors.centerIn: parent
            name: cell.iconName
            size: cellStyles.icSm
            tintColor: cell.tone
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            enabled: cell.enabled
            cursorShape: cell.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: cell.clicked()
        }
    }

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- 标题条 (54px) ---
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
                    text: "SOS RECIPIENTS"
                    font.family: styles.monoFont
                    font.pixelSize: styles.fsXs
                    font.letterSpacing: 1.8
                    color: CommonOptions.colorInk3
                }
                Text {
                    width: parent.width
                    text: "紧急联系人"
                    font.pixelSize: styles.fs2xl
                    font.bold: true
                    color: CommonOptions.colorText
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: contactsPage.contactCount > 0
                          ? (contactsPage.contactCount + " 人 · 触发 SOS 全员收到同一条定位短信")
                          : "名单是空的 · 触发 SOS 时发不出短信"
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
                    onClicked: contactsPage.goBack()
                }
            }
        }

        // --- 读数带 (3 格) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: readoutCol.implicitHeight + 2 * styles.spSm
            Layout.topMargin: styles.spSm
            visible: contactsPage.contactCount > 0
            color: CommonOptions.colorSurface

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: styles.lineHair
                color: CommonOptions.colorRule
            }

            ColumnLayout {
                id: readoutCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                spacing: styles.spSm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spSm
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "ROSTER"
                        font.family: styles.monoFont
                        font.pixelSize: styles.fsXs
                        font.letterSpacing: 1.4
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    // 规则 ②: 「主」的语义在这一行交代, 不靠按钮暗示
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "「主」只排最前 · 拨号在⑤求助页长按"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: [
                            { k: "N", label: "名册", v: String(contactsPage.contactCount) },
                            { k: "PRIM", label: "主联系人", v: String(contactsPage.primaryCount) },
                            { k: "REL", label: "关系已填", v: String(contactsPage.relationCount) }
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle {
                                visible: index > 0
                                Layout.preferredWidth: styles.lineHair
                                Layout.fillHeight: true
                                color: CommonOptions.colorRuleSoft
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.v
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fs2xl
                                    color: CommonOptions.colorText
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.pixelSize: styles.fsXs
                                    color: CommonOptions.colorInk3
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- 名册 ---
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: styles.spSm

            ListView {
                id: rosterView
                anchors.fill: parent
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: contactsPage.rows
                visible: contactsPage.contactCount > 0

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: rosterView.width
                    height: styles.rowHTall

                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: styles.spXs
                        spacing: styles.spSm

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: styles.spXs
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData.name
                                    font.pixelSize: styles.fsMd
                                    font.bold: true
                                    color: CommonOptions.colorText
                                    elide: Text.ElideRight
                                }
                                // 「主」方块: 只有 is_primary=true 才出现
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    visible: modelData.primary
                                    radius: styles.rSm
                                    color: CommonOptions.colorSurfaceDim
                                    border.color: CommonOptions.colorText
                                    border.width: styles.lineHair
                                    Text {
                                        anchors.centerIn: parent
                                        text: "主"
                                        font.pixelSize: styles.fsXs
                                        color: CommonOptions.colorText
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                // 关系没填就直说, 不拿姓名凑一行
                                text: modelData.relation.length > 0
                                      ? modelData.relation : "关系未填"
                                font.pixelSize: styles.fsXs
                                color: modelData.relation.length > 0
                                       ? CommonOptions.colorInk3 : CommonOptions.colorTextDim
                                elide: Text.ElideRight
                            }
                        }

                        // 号码是本页唯一的等宽读数 (纯拉丁数字, 不混汉字)
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: modelData.phone
                            font.family: styles.monoFont
                            font.pixelSize: styles.fsMd
                            color: CommonOptions.colorText
                        }

                        ActionCell {
                            Layout.alignment: Qt.AlignVCenter
                            iconName: "edit"
                            tone: CommonOptions.colorText
                            onClicked: contactsPage.openEdit(index)
                        }
                        ActionCell {
                            Layout.alignment: Qt.AlignVCenter
                            iconName: "delete"
                            tone: CommonOptions.colorDanger
                            onClicked: {
                                confirmDeleteDialog.delIndex = index
                                confirmDeleteDialog.open()
                            }
                        }
                    }

                    Rectangle {
                        visible: index < contactsPage.rows.length - 1
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: styles.lineHair
                        color: CommonOptions.colorRuleSoft
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: contactsPage.contactCount === 0
                iconName: "call"
                text: "名单里还没有人"
                hint: contactsPage.note.length > 0
                      ? contactsPage.note
                      : "添加之后, ⑤求助页长按触发 SOS 会给名单里每个人都发一条含位置的短信"
                actionText: "添加联系人"
                onActionTriggered: contactsPage.openAdd()
            }
        }

        // --- 底栏 ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: bottomCol.implicitHeight + 2 * styles.spSm
            color: CommonOptions.colorSurfaceAlt

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: styles.lineHair
                color: CommonOptions.colorText
            }

            ColumnLayout {
                id: bottomCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: styles.spLg
                anchors.rightMargin: styles.spLg
                spacing: styles.spXs

                Text {
                    Layout.fillWidth: true
                    visible: contactsPage.note.length > 0
                    text: contactsPage.note
                    font.pixelSize: styles.fsXs
                    color: CommonOptions.colorLegendAmber
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: styles.spMd

                    OutlineButton {
                        Layout.preferredWidth: 88
                        Layout.preferredHeight: styles.btnHSm
                        Layout.alignment: Qt.AlignVCenter
                        // 文案只说"返回": 这一页可能从⑤求助进来, 也可能从「我」进来,
                        //   写死"回⑤求助"就成了假承诺
                        text: "返回"
                        tone: CommonOptions.colorTextMuted
                        textSize: styles.fsSm
                        onClicked: contactsPage.goBack()
                    }
                    PrimaryButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: styles.btnHSm
                        Layout.alignment: Qt.AlignVCenter
                        text: "添加联系人"
                        iconName: "call_add"
                        tone: CommonOptions.colorAccent
                        textSize: styles.fsSm
                        onClicked: contactsPage.openAdd()
                    }
                }
            }
        }
    }

    Component.onCompleted: contactsPage.load()

    // === 弹层 ==============================================================
    Dialog {
        id: addDialog
        title: contactsPage.dlgMode === "edit" ? "编辑联系人" : "添加联系人"
        modal: true
        anchors.centerIn: parent
        width: Math.min(420, contactsPage.width - 2 * styles.pageMargin)
        padding: styles.spMd
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        standardButtons: Dialog.NoButton

        contentItem: ColumnLayout {
            spacing: styles.spMd

            TextField {
                id: nameField
                Layout.fillWidth: true
                Layout.preferredHeight: styles.fieldH
                color: CommonOptions.colorText
                placeholderText: "姓名"
                placeholderTextColor: CommonOptions.colorTextDim
                font.pixelSize: styles.fsMd
            }
            TextField {
                id: phoneField
                Layout.fillWidth: true
                Layout.preferredHeight: styles.fieldH
                color: CommonOptions.colorText
                placeholderText: "电话"
                placeholderTextColor: CommonOptions.colorTextDim
                // 只收可拨号字符; 这一页不拨号 (规则 ①), 号码写错要去⑤求助页才发现
                inputMethodHints: Qt.ImhDialableCharactersOnly
                font.pixelSize: styles.fsMd
            }
            TextField {
                id: relationField
                Layout.fillWidth: true
                Layout.preferredHeight: styles.fieldH
                color: CommonOptions.colorText
                placeholderText: "关系 (如: 家人 / 队友)"
                placeholderTextColor: CommonOptions.colorTextDim
                font.pixelSize: styles.fsMd
            }
            CheckBox {
                id: primaryCheck
                text: "排在名单第一行"
                Material.foreground: CommonOptions.colorText
                font.pixelSize: styles.fsMd
            }
            Text {
                Layout.fillWidth: true
                text: "勾不勾都照样收到短信 —— 这只决定谁在第一行。"
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorTextDim
                wrapMode: Text.WordWrap
            }
        }

        footer: RowLayout {
            spacing: styles.spSm
            Item { Layout.fillWidth: true }
            OutlineButton {
                Layout.preferredWidth: 72
                Layout.preferredHeight: styles.btnHSm
                Layout.alignment: Qt.AlignVCenter
                text: "算了"
                tone: CommonOptions.colorTextMuted
                textSize: styles.fsSm
                onClicked: addDialog.close()
            }
            PrimaryButton {
                Layout.preferredWidth: 88
                Layout.preferredHeight: styles.btnHSm
                Layout.alignment: Qt.AlignVCenter
                text: contactsPage.dlgMode === "edit" ? "保存" : "写进名册"
                iconName: "check"
                tone: CommonOptions.colorAccent
                textSize: styles.fsSm
                onClicked: contactsPage.acceptDialog()
            }
        }

        // 关窗清字段: 否则下次打开看到上一个人的号码 (2026-09-20 起就有这条)
        onClosed: {
            nameField.text = ""
            phoneField.text = ""
            relationField.text = ""
            primaryCheck.checked = false
        }
    }

    Dialog {
        id: confirmDeleteDialog
        property int delIndex: -1
        title: "移出名单"
        modal: true
        anchors.centerIn: parent
        width: Math.min(420, contactsPage.width - 2 * styles.pageMargin)
        padding: styles.spMd
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        standardButtons: Dialog.NoButton

        contentItem: Text {
            text: "把「" + (contactsPage.rows[confirmDeleteDialog.delIndex]
                            ? contactsPage.rows[confirmDeleteDialog.delIndex].name : "")
                  + "」从名单里移出去？移走后触发 SOS 不再给这个号码发定位短信。"
            color: CommonOptions.colorText
            font.pixelSize: styles.fsMd
            wrapMode: Text.WordWrap
        }

        footer: RowLayout {
            spacing: styles.spSm
            Item { Layout.fillWidth: true }
            OutlineButton {
                Layout.preferredWidth: 72
                Layout.preferredHeight: styles.btnHSm
                Layout.alignment: Qt.AlignVCenter
                text: "留着"
                tone: CommonOptions.colorTextMuted
                textSize: styles.fsSm
                onClicked: confirmDeleteDialog.close()
            }
            OutlineButton {
                Layout.preferredWidth: 88
                Layout.preferredHeight: styles.btnHSm
                Layout.alignment: Qt.AlignVCenter
                text: "移出"
                tone: CommonOptions.colorDanger
                textSize: styles.fsSm
                onClicked: contactsPage.removeContact()
            }
        }
    }

    Connections {
        target: emergencyService
        // 名册在任何一处被改 (含⑤求助页) 都重读一次
        function onContactsChanged() { contactsPage.load() }
    }
}
