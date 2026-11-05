/**
 * @file SOSPage.qml
 * @brief ⑤ 求助 — 先读数, 再决定动作 (2026-10-20 「地物图例」丁骨架 v8)
 *
 * 版式逐块对应已评审的 mock (review-ding-v8.html 「丁 ⑤」):
 *   墨底仪表   左边嵌 74px 迷你盘 + 坐标/海拔/精度/读取 (与①同一件 PositionReadout)
 *   两个次级动作 复制位置文本 / 生成短信草稿 —— 都只加工文本, 不发出去
 *   紧急号码   120 / 110 / 119 三行, 每行右侧一条 52x9 长按进度条
 *   一键求救   长按 3 秒才 triggerSOS(); 进行中换成状态条 + 取消
 *   先做这一步 急救卡来自 firstAidService.getCritical(), 不写死条目
 *   紧急联系人 每位一行, 同样长按 2 秒才拨号
 *
 * 这一页最要紧的一条规则: 页面上没有任何一处"点一下就拨出去".
 *   改版前这里是三颗 tap-to-dial 的 QuickCallButton + 一颗联系人直接 callNumber,
 *   口袋里误触就把 120 拨出去了. 现在全部走 HoldConfirmRow: 按住 2 秒进度条填满
 *   才算确认, 中途松手 / 手指滑出都清零. 号码行之外, triggerSOS() 也进了长按门 ——
 *   它内部会 call120() 并群发短信, 是整页后果最重的一次操作.
 *   真机验证时这些行一律不许按满 (项目记忆: 真机绝不触发拨号/短信).
 *
 * 读数不许编: 没定位时坐标位写 "--", 状态位写 "未定位" (坐标走等宽字体, 塞不进汉字),
 * 海拔没给就是 "--"; 「生成短信草稿」未定位时交给 service 的 "GPS 位置未获取到" 文案, 不拼假坐标.
 *
 * 坏消息不许过期: 复制/草稿两条失败写进页面常驻的 note 行, 不用 3 秒就消失的
 * toast (成功侧仍用 toast —— 那是一次性确认, 不值得占版面).
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

// delegate 里要读 sosPage / styles 这些外层 id, qmlcachegen 静态编译下必须 Bound,
// 否则真机静默 ReferenceError (2026-10-19 同类 bug 一批).
pragma ComponentBehavior: Bound

Page {
    id: sosPage

    Styles { id: styles; visible: false }

    // 2026-10-20: 不再直接引用 Main.qml 的 id "toast" -- QML 语义上 id 只在声明文件里
    //   可见, 跨文件取得到只是"创建上下文链"的巧合 (实测: qmlcachegen 编译下 StackView
    //   页面仍可解析, 所以旧写法确实弹过; 但改成动态 createObject 或被别处嵌就变 undefined).
    //   显式从 Window 上的 alias 取 (Main.qml: readonly property alias toastBox).
    readonly property var toast: ApplicationWindow.window
                                 ? ApplicationWindow.window.toastBox : null

    title: "求助"
    // 不兜 800 下限: 内容区不足 800 逻辑时 Page 会比视口高, 多出来那一截画在底部导航条上 (12 §4.20b)
    height: parent && parent.height > 0 ? parent.height : 800
    width: parent ? parent.width : 360

    background: Rectangle { color: CommonOptions.colorBg }

    function navigateTo(page, props) {
        ApplicationWindow.window.navBus.navigateTo(page, props || {})
    }

    // === 数据来源 ===========================================================
    readonly property bool hasFix: emergencyService ? emergencyService.hasLocation : false
    readonly property real curLat: emergencyService ? emergencyService.currentLatitude : 0
    readonly property real curLon: emergencyService ? emergencyService.currentLongitude : 0
    readonly property real accM: emergencyService ? emergencyService.currentAccuracy : -1
    readonly property real altM: emergencyService ? emergencyService.currentAltitude : Number.NaN

    readonly property bool hasHeading: compassSensor ? compassSensor.valid : false
    readonly property real headingDeg: hasHeading ? compassSensor.heading : 0
    // 2026-10-26: 第二朝向来源 = GPS 行进方向 (EmergencyService.currentCourse).
    //   与 ①营地 / ④地图 同一套口径; 两者都没有就不画针、读数给 "--" (不给 0° 假方向).
    readonly property real courseDeg: emergencyService
        ? emergencyService.currentCourse : Number.NaN
    readonly property bool hasCourse: isFinite(courseDeg)
    readonly property real effHeadingDeg: hasHeading ? headingDeg
                                                     : (hasCourse ? courseDeg : 0)
    readonly property bool hasEffHeading: hasHeading || hasCourse

    // 最后一次定位的读取时刻. 只有 locationUpdated 会改写它, 所以显示的是"读取"而不是"现在".
    property string fixTime: "--:--"

    // 2026-10-21 #65: 失败原因常驻在这一行, 不走 toast. 求助页上的"复制失败"/
    //   "短信应用打不开"如果 3 秒后自己消失, 用户会以为草稿已经生成好了 —— 这一页
    //   不许有会过期的坏消息. 成功侧仍用 toast (一次性确认, 越短越好, 别占版面).
    property string note: ""

    // 坐标与右上状态都画在墨底仪表的等宽 Text 里, 只许拉丁和数字 (见 Styles ⑦)
    readonly property string coordText: hasFix
        ? curLat.toFixed(5) + (curLat >= 0 ? " N" : " S") + " / "
          + curLon.toFixed(5) + (curLon >= 0 ? " E" : " W")
        : "--"
    readonly property string altText: (hasFix && isFinite(altM))
        ? CommonOptions.formatElevation(altM) : "--"
    // 精度: 2026-10-22 #98 起未知是 NaN (以前是 0, 会画成 "±0 m" 这种假数)
    readonly property string accText: (hasFix && isFinite(accM) && accM > 0)
        ? "\u00b1" + Math.round(accM) + " m" : "--"
    readonly property string headingText: hasEffHeading
        ? Math.round(effHeadingDeg) + "°" : "--"

    // 读数空着的原因 (C++ 侧翻好的中文). 求助页上这一行尤其不能省: 救援方最需要的
    // 就是知道"坐标是实的、精度还不知道".
    readonly property string fixDiag: emergencyService ? emergencyService.locationDiag : ""
    readonly property string readoutHint:
        (hasFix && !isFinite(altM))
            ? "本次定位不带高程（网络定位常见），海拔读不出" : fixDiag

    // 「先做这一步」+「紧急联系人」: 两个 service 方法都没有 NOTIFY, 只能手动取数
    property var triage: []
    property var contacts: []

    // === 文本加工 ===========================================================
    // 复制/草稿共用同一句话 (来自 service, 页面不自己拼坐标格式)
    function locationText() {
        if (!emergencyService) return ""
        return emergencyService.formatLocationMessage(curLat, curLon)
    }

    function copyLocation() {
        var t = sosPage.locationText()
        if (!androidPlatform || !androidPlatform.copyToClipboard(t)) {
            sosPage.note = "复制失败 · 这台设备上没有可用剪贴板"
            return
        }
        sosPage.note = ""
        toast.success("位置文本已复制")
    }

    // 只拉起系统短信编辑页 (收件人留空, 正文填好), 发送键在用户手里.
    // 走 sendSMS() 就是 SmsManager 直接发送 —— 野外误触等于真发一条, 这条路不给开.
    function draftSms() {
        var t = sosPage.locationText()
        if (!androidPlatform || !androidPlatform.openSmsDraft("", t)) {
            sosPage.note = "短信草稿打不开 · 这台设备没有可用短信应用"
            return
        }
        sosPage.note = ""
        toast.success("草稿已放进短信应用 · 请自己确认后再发送")
    }

    // === 取数 ===============================================================
    // 危急优先度高的先上, 同档按 id 排 (getCritical 遍历 QHash, 不排序的话每进
    // 一次页面顺序都不一样). 先排序再取 steps/donts: 库里 urgency>=4 有几十条,
    // 每条 getById 都会重建一份完整 QVariantMap, 只为了排完就丢掉不划算.
    function refreshTriage() {
        if (!firstAidService) { triage = []; return }
        var raw = firstAidService.getCritical()
        var picked = []
        for (var i = 0; i < raw.length; ++i) picked.push(raw[i])
        picked.sort(function (a, b) {
            var ua = Number(a.urgency), ub = Number(b.urgency)
            if (ub !== ua) return ub - ua
            return a.id < b.id ? -1 : 1
        })
        var out = []
        for (var j = 0; j < picked.length && j < 3; ++j) {
            var d = firstAidService.getById(picked[j].id)
            out.push({
                id: picked[j].id,
                title: picked[j].title,
                urgency: Number(picked[j].urgency),
                steps: (d && d.steps) ? d.steps.length : 0,
                donts: (d && d.donts) ? d.donts.length : 0
            })
        }
        triage = out
    }

    function refreshContacts() {
        if (!emergencyService) { contacts = []; return }
        // getContacts 返回 Result 包装 {ok, value:[...]}, 失败时当空列表处理
        var r = emergencyService.getContacts()
        contacts = (r && r.value !== undefined) ? r.value : []
    }

    Component.onCompleted: {
        if (emergencyService) emergencyService.requestLocationUpdate()
        if (compassSensor) compassSensor.active = true
        refreshTriage()
        refreshContacts()
    }
    Component.onDestruction: {
        if (compassSensor) compassSensor.active = false
    }
    onVisibleChanged: {
        if (visible) {
            if (emergencyService) emergencyService.requestLocationUpdate()
            refreshTriage()
            refreshContacts()
        }
    }

    Connections {
        target: emergencyService
        function onLocationUpdated(lat, lon, accuracy) {
            var d = new Date()
            sosPage.fixTime = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
        }
        function onContactsChanged() { sosPage.refreshContacts() }
        function onSosTriggered() { toast.success("SOS 已触发 · 正在通知联系人") }
        function onSosCancelled() { toast.info("SOS 已取消") }
    }

    // === 版面 ===============================================================
    ScrollView {
        anchors.fill: parent
        // A41 (pass6 b02): 这一页自己没有吸底条, 折边就是底部导航条 (NavBands) 的上描边 ——
        //   最下面的 SOS 长按条被切掉半截, 看不出是"还能滚"还是"被盖住"。留一格让位。
        anchors.bottomMargin: styles.bottomClearance
        contentWidth: parent.width
        clip: true                              // 同上: 视口默认不裁剪, 末段会画进底部导航条

        ColumnLayout {
            width: parent.width
            spacing: styles.spMd

            // --- 标题条 ---
            // 2026-11-03 #42 (L3/L13): 原来是复制体之一, 右缘让位写死 64 (照着一屏数出来的)。
            //   这一页右上角是"119/120"而不是返回方块 —— PageHeadBand 用 plateCode 非空来表达
            //   "放角标、不放返回", 让位按角标实际宽现算。
            PageHeadBand {
                eyebrowText: "求助"
                titleText: "求助"
                statusText: sosPage.hasFix
                            ? (sosPage.hasHeading
                               ? "定位就绪 · 朝向 " + sosPage.headingText
                               : (sosPage.hasCourse
                                  ? "定位就绪 · 按行进方向 " + sosPage.headingText
                                  : "定位就绪 · 无朝向来源, 按正北读"))
                            : "尚未定位 · 草稿里只有时间没有坐标"
                statusSize: styles.fsSm
                statusColor: CommonOptions.colorTextMuted
                plateCode: "119/120"
                plateTone: CommonOptions.colorHazard
            }

            // --- 墨底仪表 + 迷你盘 (全站两处墨底之二) ---
            PositionReadout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                showDial: true
                label: "实时位置"
                trailing: sosPage.hasFix ? "已定位" : "未定位"
                trailingColor: sosPage.hasFix
                               ? CommonOptions.colorForest : CommonOptions.colorLegendAmber
                coordText: sosPage.coordText
                hint: sosPage.readoutHint
                cells: [
                    { v: sosPage.altText,   k: "海拔" },
                    { v: sosPage.accText,   k: "精度" },
                    { v: sosPage.fixTime,   k: "读取" }
                ]
                dialValue: sosPage.headingText
                dialLabel: "方位"
                dialHeading: sosPage.effHeadingDeg
                // 与 ①营地 同: 这个属性在 Dial 里的意思是"指针可画", 不是"有定位".
                //   有定位但两个朝向来源都没数时画一根 0° 的针 = 假方向.
                dialHasFix: sosPage.hasEffHeading
            }

            // --- 两个次级动作: 只加工文本, 不发出去 ---
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                spacing: styles.spSm

                OutlineButton {
                    Layout.fillWidth: true
                    text: "复制位置文本"
                    onClicked: sosPage.copyLocation()
                }
                OutlineButton {
                    Layout.fillWidth: true
                    text: "生成短信草稿"
                    onClicked: sosPage.draftSms()
                }
            }

            // 失败常驻行 (见上面 note 属性注释)
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                visible: sosPage.note.length > 0
                text: sosPage.note
                font.pixelSize: styles.fsSm
                color: CommonOptions.colorLegendAmber
                wrapMode: Text.WordWrap
            }

            // --- 紧急号码: 三行, 长按 2 秒 ---
            SectionTitle {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.topMargin: 2
                text: "紧急号码"
                trailing: "长按 2 秒"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.preferredHeight: numbersCol.implicitHeight
                color: CommonOptions.colorSurface
                border.color: CommonOptions.colorRule
                border.width: styles.lineHair

                ColumnLayout {
                    id: numbersCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 0

                    Repeater {
                        model: [
                            { code: "120", title: "医疗急救", sub: "不自动拨号 · 长按进度条确认" },
                            { code: "110", title: "警务", sub: "山地搜救通常由 110 联动" },
                            { code: "119", title: "消防救援", sub: "山火 / 困锁 / 高处救援" }
                        ]
                        delegate: ColumnLayout {
                            id: numberCell
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 0

                            // 行间 1px 组线: 第一行不画, 卡片上描边已经是第一条
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: styles.lineHair
                                visible: numberCell.index > 0
                                color: CommonOptions.colorRuleSoft
                            }
                            HoldConfirmRow {
                                Layout.fillWidth: true
                                code: numberCell.modelData.code
                                title: numberCell.modelData.title
                                subtitle: numberCell.modelData.sub
                                onConfirmed: {
                                    if (!emergencyService) return
                                    if (numberCell.modelData.code === "120") emergencyService.call120()
                                    else if (numberCell.modelData.code === "110") emergencyService.call110()
                                    else emergencyService.call119()
                                }
                            }
                        }
                    }
                }
            }

            // --- 一键求救 / 进行中状态 ---
            SectionTitle {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.topMargin: 2
                text: "一键求救"
                trailing: "SOS"
            }

            // triggerSOS() 内部会拨 120 并给所有联系人群发位置短信, 是本页后果最重
            // 的一次动作, 所以它和号码行用同一个门, 只是拉到 3 秒.
            // 2026-11-03 真机 (F7 / L11): 一个联系人都没有时, 旧文案写"群发位置给 0 位
            // 联系人"却仍画成可用入口 —— 用户读到的是"这条链路是通的", 而 triggerSOS()
            // 实际只做两件事: 拨 120 + 开始上报位置, 短信一条也发不出去.
            //   这里**不许**改成禁用: 名单空着不该挡住拨 120 (那是这一页存在的理由),
            //   要修的是"话要说准" —— 没联系人就直说没有, 并给出补救入口.
            HoldConfirmRow {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                visible: !(emergencyService && emergencyService.isSosActive)
                code: "SOS"
                title: "触发 SOS"
                subtitle: {
                    var n = emergencyService ? emergencyService.contactCount : 0
                    return n > 0
                           ? ("拨 120 · 同时给 " + n + " 位联系人发位置短信")
                           : ("拨 120 · 开始上报位置 · 名单为空, 不会发短信")
                }
                holdMs: 3000
                accent: CommonOptions.colorBlaze
                onConfirmed: {
                    if (emergencyService) emergencyService.triggerSOS()
                }
            }

            // 名单为空时把"缺什么"摆在按钮正下方 (旧版只有页尾那块 EmptyState,
            // 用户在按钮上看不到补救入口, 只能猜).
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                visible: !(emergencyService && emergencyService.isSosActive)
                         && (!emergencyService || emergencyService.contactCount === 0)
                text: "添加紧急联系人后, 触发时会把坐标与伤情一并发出去"
                font.pixelSize: styles.fsXs
                color: CommonOptions.colorDanger
                wrapMode: Text.WordWrap
            }

            // SOS 进行中: hazard 实心条, 不占墨底名额.
            //   全站墨底仪表只有两处 (①与上面那块), 这是设计约定里"高优先级仪表"的
            //   信号, 再出现第三块就贬值了; colorHazard 的语义本来就是"危险 / SOS".
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.preferredHeight: styles.rowH
                visible: emergencyService ? emergencyService.isSosActive : false
                color: CommonOptions.colorHazard
                border.color: CommonOptions.colorDangerDeep
                border.width: styles.lineHair

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: styles.cardPad
                    anchors.rightMargin: styles.cardPad
                    spacing: styles.spSm

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: "SOS 已触发 · 正在等待救援"
                            color: CommonOptions.colorTextOnAccent
                            font.pixelSize: styles.fsMd
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: sosPage.hasFix
                                  ? "位置持续更新中 · " + sosPage.coordText
                                  : "尚未定位 · 到达开阔处重取一次"
                            color: CommonOptions.withAlpha(CommonOptions.colorTextOnAccent, 0.82)
                            font.pixelSize: styles.fsXs
                            elide: Text.ElideRight
                        }
                    }
                    // 取消不设门: 误触发之后"停手"必须是本页最容易做到的一次点击
                    OutlineButton {
                        Layout.alignment: Qt.AlignVCenter
                        text: "取消"
                        tone: CommonOptions.colorHazard
                        onClicked: {
                            if (emergencyService) emergencyService.cancelSOS()
                        }
                    }
                }
            }

            // --- 先做这一步 (急救卡, 全部来自 service) ---
            SectionTitle {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.topMargin: 2
                text: "先做这一步"
                trailing: "分级"
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                spacing: styles.spSm

                Repeater {
                    model: sosPage.triage
                    delegate: Rectangle {
                        id: triageCard
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: styles.rowHTall
                        color: CommonOptions.colorSurface
                        border.color: CommonOptions.colorRule
                        border.width: styles.lineHair

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: styles.lineAccent
                            color: triageCard.modelData.urgency >= 5
                                   ? CommonOptions.colorHazard : CommonOptions.colorAmber
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: styles.lineAccent + 6
                            anchors.rightMargin: styles.cardPad
                            spacing: styles.spSm

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: triageCard.modelData.title
                                    font.pixelSize: styles.fsMd
                                    font.bold: true
                                    color: CommonOptions.colorText
                                    elide: Text.ElideRight
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: styles.spXs
                                    // 编号是拉丁数字才进 monoFont, 后面的中文另起一个
                                    // Text: monospace 族没汉字字形, 混在一句里真机会出方框.
                                    Plate {
                                        entryId: triageCard.modelData.id
                                        prefix: "FA"
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: triageCard.modelData.steps + " 步"
                                              + (triageCard.modelData.donts > 0
                                                 ? " · 含 " + triageCard.modelData.donts + " 条禁忌" : "")
                                        font.pixelSize: styles.fsXs
                                        color: CommonOptions.colorTextDim
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            IconLabel {
                                Layout.alignment: Qt.AlignVCenter
                                name: "chevron_right"
                                size: styles.icMd
                                tintColor: CommonOptions.colorInk3
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sosPage.navigateTo("FirstAidDetailPage",
                                                          { entryId: triageCard.modelData.id })
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: sosPage.triage.length === 0
                    text: "急救库没读到危急条目 · 可在急救页按类别查"
                    font.pixelSize: styles.fsSm
                    color: CommonOptions.colorTextDim
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }
            }

            // --- 紧急联系人 ---
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                Layout.topMargin: 2
                spacing: styles.spSm

                SectionTitle {
                    Layout.fillWidth: true
                    text: "紧急联系人 " + sosPage.contacts.length + " 位"
                    trailing: "清单"
                }
                OutlineButton {
                    Layout.alignment: Qt.AlignVCenter
                    text: "添加"
                    tone: CommonOptions.colorBlaze
                    onClicked: sosPage.navigateTo("EmergencyContactsPage", {})
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                spacing: styles.spSm
                visible: sosPage.contacts.length > 0

                Repeater {
                    model: sosPage.contacts
                    delegate: HoldConfirmRow {
                        id: contactRow
                        required property var modelData
                        Layout.fillWidth: true
                        // 每位联系人自己就是一张描边卡 (HoldConfirmRow 自带),
                        // 不再套一层 Rectangle: 双层描边只会让 1px 线糊成 2px.
                        code: String(contactRow.modelData.phone || "").slice(-4)
                        title: contactRow.modelData.name
                               + (contactRow.modelData.isPrimary ? " \u00b7 主" : "")
                        subtitle: (contactRow.modelData.phone || "")
                                  + " " + (contactRow.modelData.relation || "")
                        accent: CommonOptions.colorPlum
                        confirmable: String(contactRow.modelData.phone || "").length > 0
                        onConfirmed: {
                            if (emergencyService)
                                emergencyService.callNumber(contactRow.modelData.phone)
                        }
                    }
                }
            }

            // 一个联系人都没有时说明原因 (空白列表分不清"没加"还是"没读到")
            EmptyState {
                Layout.fillWidth: true
                Layout.leftMargin: styles.pageMargin
                Layout.rightMargin: styles.pageMargin
                visible: sosPage.contacts.length === 0
                iconName: "list"
                text: "还没有紧急联系人"
                hint: "添加后触发 SOS 会把位置和伤情短信发给 TA"
                actionText: "去添加"
                onActionTriggered: sosPage.navigateTo("EmergencyContactsPage", {})
            }

            Item { Layout.preferredHeight: styles.spLg }
        }
    }
}
