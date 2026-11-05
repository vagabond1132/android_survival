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
 *   名册    一行一个人: 第一行 姓名 + 「主」方块, 第二行 等宽号码 + 关系 / 行尾两枚动作方块.
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
 *
 * 2026-10-29 (用户问题5: 紧急联系人排版):
 *   ① 名册行拆成两行 —— 姓名 + 「主」在上, 号码 (等宽) + 关系在下. 原来号码横插在
 *      RowLayout 中间与姓名抢宽度: 窄屏上姓名一 elide 就剩一个字, 号码还把两枚动作格
 *      顶向行外. 现在姓名 fillWidth + elide, 号码单独一行, 动作格永远钉在行尾.
 *   ② 手搓 ActionCell (Rectangle + MouseArea) 换成共用 IconActionCell: 那颗 MouseArea
 *      按下即独占抓握, 名单一长就在行里拖不动 (与 #105 目标列表同族, 见
 *      [[qml-taphandler-exclusive-grab]]).
 *   ③ 添加/编辑弹窗: 三个只有 placeholder 的输入框 (一敲字标签就没了) → 每格上方一行
 *      小字标签 + focus 时描墨线的输入框, 与 EquipmentPage 的表单同一套. 号码格保持
 *      数字键盘. 软键盘的让位不用自己做: manifest 是 adjustResize, 窗口变矮、居中弹窗
 *      跟着上移; 给 Popup 写 x:/y: 位置绑定反而压过开合动画 (见 typed_member_check).
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

    // === 版面 ==============================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- 标题条 (54px) ---
        // 2026-11-03 #42 (L3/L13): 原来这一条是 12 个二级页各一份的复制体, 数写死在页里
        //   (54 / 40 / 26 / 9)。几何收进 PageHeadBand + Styles.pageHead*, 这里只留文案与回退动作。
        PageHeadBand {
            eyebrowText: "求助收件人"
            titleText: "紧急联系人"
            statusText: contactsPage.contactCount > 0
                ? (contactsPage.contactCount + " 人 · 触发 SOS 全员收到同一条定位短信")
                : "名单是空的 · 触发 SOS 时发不出短信"
            onBackClicked: contactsPage.goBack()
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
                        text: "名册"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorInk3
                    }
                    Item { Layout.fillWidth: true }
                    // 规则 ②: 「主」的语义在这一行交代, 不靠按钮暗示
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "「主」只排最前 · 拨号在求助页长按"
                        font.pixelSize: styles.fsXs
                        color: CommonOptions.colorTextDim
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: [
                            { label: "名册", v: String(contactsPage.contactCount) },
                            { label: "主联系人", v: String(contactsPage.primaryCount) },
                            { label: "关系已填", v: String(contactsPage.relationCount) }
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
        // 2026-10-22 巡检: 0 联系人时这一格漂在整页空白正中, 看着像页面坏了 —— 当时的
        //   修法是"空态不占满" (fillHeight 只在有列表时为真) + 空态改 anchors.top。
        // 2026-11-03 F5 复量 (真机 0.0.6): 那个条件句才是病根。空名单时整棵根
        //   ColumnLayout 一个 fillHeight 子项都没有, Qt Quick Layouts 于是把剩余空间
        //   摊到子项之间而不是留在末尾, 结果 54px 标题条被顶下 67 逻辑 px —— 同一屏的
        //   返回方块从 device y=266 跑到 454, 用户按 266 点两次都退不出去。
        //   空态本来就 anchors.top, 所以 fillHeight 恒真既保住 2026-10-22 的意图
        //   (空态贴上边缘), 又让页根永远有一个吃满剩余高度的子项。见 page_fill_check。
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: emptyBox.implicitHeight
            Layout.topMargin: styles.spSm

            ListView {
                id: rosterView
                anchors.fill: parent
                anchors.leftMargin: styles.pageMargin
                anchors.rightMargin: styles.pageMargin
                anchors.bottomMargin: styles.bottomClearance   // A41: 末行给下面的吸底条让位
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
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            // 第一行: 姓名 + 「主」. 姓名 fillWidth + elide, 名字再长也只缩
                            //   自己, 不会把行尾两枚动作格顶出去 (2026-10-29 问题5).
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: styles.spXs
                                Text {
                                    Layout.fillWidth: true
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

                            // 第二行: 号码 (等宽) + 关系. 号码从中间挪到单独一行之后不再
                            //   和姓名抢宽度; 关系没填就直说, 不拿姓名凑一行.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: styles.spXs
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData.phone
                                    font.family: styles.monoFont
                                    font.pixelSize: styles.fsSm
                                    color: CommonOptions.colorTextMuted
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData.relation.length > 0
                                          ? modelData.relation : "关系未填"
                                    font.pixelSize: styles.fsXs
                                    color: modelData.relation.length > 0
                                           ? CommonOptions.colorInk3 : CommonOptions.colorTextDim
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // 共用 IconActionCell (2026-10-29): 原来是手搓 Rectangle + MouseArea,
                        //   按下即独占抓握, 名单一长就在行里拖不动 (#105 同族).
                        IconActionCell {
                            Layout.alignment: Qt.AlignVCenter
                            cellSize: styles.icBoxSm
                            iconName: "edit"
                            tone: CommonOptions.colorText
                            onTriggered: contactsPage.openEdit(index)
                        }
                        IconActionCell {
                            Layout.alignment: Qt.AlignVCenter
                            cellSize: styles.icBoxSm
                            iconName: "delete"
                            tone: CommonOptions.colorDanger
                            onTriggered: {
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
                id: emptyBox
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                visible: contactsPage.contactCount === 0
                iconName: "call"
                text: "名单里还没有人"
                hint: contactsPage.note.length > 0
                      ? contactsPage.note
                      : "添加之后, 在求助页长按触发 SOS 会给名单里每个人都发一条含位置的短信"
                // 出口只有一个: 底栏那颗「添加联系人」主按钮.
                // 原来这里也放了一颗同名按钮, 空态一个 + 底栏一个, 两个入口一件事.
                actionText: ""
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
        // 软键盘不会盖住它: AndroidManifest 里 windowSoftInputMode="adjustResize"
        //   (android/AndroidManifest.xml:97), IME 弹起时窗口自己变矮, 居中弹窗跟着上移.
        //   不要给 Popup 写 x:/y: 位置绑定 —— 会压过开合动画, 也是 typed_member_check 的门禁项.
        anchors.centerIn: parent
        width: Math.min(420, contactsPage.width - 2 * styles.pageMargin)
        padding: styles.spMd
        Material.background: CommonOptions.colorSurface
        Material.foreground: CommonOptions.colorText
        standardButtons: Dialog.NoButton

        contentItem: ColumnLayout {
            spacing: styles.spSm

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "姓名"
                    color: CommonOptions.colorInk3
                    font.pixelSize: styles.fsXs
                }
                TextField {
                    id: nameField
                    Layout.fillWidth: true
                    Layout.preferredHeight: styles.btnH
                    color: CommonOptions.colorText
                    placeholderText: "如: 张三"
                    placeholderTextColor: CommonOptions.colorTextDim
                    font.pixelSize: styles.fsMd
                    leftPadding: styles.spSm
                    rightPadding: styles.spSm
                    topPadding: 0
                    bottomPadding: 0
                    background: Rectangle {
                        color: nameField.activeFocus
                               ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                        border.color: nameField.activeFocus
                                      ? CommonOptions.colorText : CommonOptions.colorRule
                        border.width: styles.lineHair
                        radius: styles.rSm
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "电话"
                    color: CommonOptions.colorInk3
                    font.pixelSize: styles.fsXs
                }
                TextField {
                    id: phoneField
                    Layout.fillWidth: true
                    Layout.preferredHeight: styles.btnH
                    color: CommonOptions.colorText
                    placeholderText: "如: 13800001111"
                    placeholderTextColor: CommonOptions.colorTextDim
                    // 只收可拨号字符; 这一页不拨号 (规则 ①), 号码写错要去⑤求助页才发现
                    inputMethodHints: Qt.ImhDialableCharactersOnly
                    font.pixelSize: styles.fsMd
                    leftPadding: styles.spSm
                    rightPadding: styles.spSm
                    topPadding: 0
                    bottomPadding: 0
                    background: Rectangle {
                        color: phoneField.activeFocus
                               ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                        border.color: phoneField.activeFocus
                                      ? CommonOptions.colorText : CommonOptions.colorRule
                        border.width: styles.lineHair
                        radius: styles.rSm
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "关系"
                    color: CommonOptions.colorInk3
                    font.pixelSize: styles.fsXs
                }
                TextField {
                    id: relationField
                    Layout.fillWidth: true
                    Layout.preferredHeight: styles.btnH
                    color: CommonOptions.colorText
                    placeholderText: "如: 家人 / 队友"
                    placeholderTextColor: CommonOptions.colorTextDim
                    font.pixelSize: styles.fsMd
                    leftPadding: styles.spSm
                    rightPadding: styles.spSm
                    topPadding: 0
                    bottomPadding: 0
                    background: Rectangle {
                        color: relationField.activeFocus
                               ? CommonOptions.colorSurface : CommonOptions.colorSurfaceDim
                        border.color: relationField.activeFocus
                                      ? CommonOptions.colorText : CommonOptions.colorRule
                        border.width: styles.lineHair
                        radius: styles.rSm
                    }
                }
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

        footer: DialogFooter {
            kind: "primary"
            cancelText: "算了"
            confirmText: contactsPage.dlgMode === "edit" ? "保存" : "写进名册"
            confirmIcon: "check"
            onCancel: addDialog.close()
            onConfirm: contactsPage.acceptDialog()
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

        // L15: Dialog 的 contentItem 是裸 Item, 不把宽度传给子项 —— 正文要有宽度约束才 wrap。
        contentItem: ColumnLayout {
            spacing: styles.spSm

            Text {
                Layout.fillWidth: true
                text: "把「" + (contactsPage.rows[confirmDeleteDialog.delIndex]
                                ? contactsPage.rows[confirmDeleteDialog.delIndex].name : "")
                      + "」从名单里移出去？移走后触发 SOS 不再给这个号码发定位短信。"
                color: CommonOptions.colorText
                font.pixelSize: styles.fsMd
                wrapMode: Text.WordWrap
            }
        }

        footer: DialogFooter {
            kind: "danger"
            cancelText: "留着"
            confirmText: "移出"
            confirmCode: "不可撤"
            onCancel: confirmDeleteDialog.close()
            onConfirm: contactsPage.removeContact()
        }
    }

    Connections {
        target: emergencyService
        // 名册在任何一处被改 (含⑤求助页) 都重读一次
        function onContactsChanged() { contactsPage.load() }
    }
}
