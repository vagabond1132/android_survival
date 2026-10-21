/**
 * @file IconLabel.qml
 * @brief Material Icons 字体图标组件 (2026-09-14 建立, 2026-10-16 改版精简)
 *
 * 用法:
 *   IconLabel { name: "home"; size: 24; tintColor: CommonOptions.colorText }
 *
 * 2026-10-16 精简掉三样东西 (原先 145 行 → 60 行):
 *   ① emoji / ASCII 兜底表. 字体是 main.cpp 在 QML 引擎启动前 addApplicationFont
 *      同步注册的, 正常构建下必然就绪; 真失败时 emoji 在部分 Android 上也没有字形
 *      (这正是当初"图标变方框"的现场), 兜底表并没有救回来, 只是把问题延后.
 *      现在改为: 字体没就绪时把 tintColor 画成 colorDanger 的告警色不现实, 所以
 *      只保留 console.warn 一次性提示, 由 CommonOptions.iconFontReady 驱动.
 *   ② 三处重复的 fontReady 计算. 它引用 Main.qml 里的 id materialIconsFont —
 *      QML 的 id 不跨文件可见, 该判断恒为 false, 于是每次都退化成
 *      Qt.fontFamilies() 全量枚举 (每个 IconLabel 实例、每次 text/font.family
 *      求值各扫一遍). 改读 C++ 常量 CommonOptions.iconFontReady, 零开销.
 *   ③ "Material Icons" 字族名硬编码. 统一走 styles.iconFont 同源值.
 */

import QtQuick

Text {
    id: root

    // 公共属性
    property string name: ""
    property int size: 24
    property color tintColor: CommonOptions.colorText

    // Material Icons 字体 codepoint (PUA 0xE000-0xF8FF)
    // 2026-10-19 全量重核: 之前只核过"码位有没有字形", 没核"字形是不是那个图标",
    //   结果一批条目语义是错的 (真机截图里蛇画成垃圾桶、日历画成省略号).
    //   这次把 102 个在用的码位全部渲染成对照表逐格看过
    //   (tools/dump_glyph_names.py + glyph_sheet 渲染, 见 doc 记录).
    //   另: 本字体 post 表是 v3.0 无字形名, 且 U+F000-F0FF 整段缺字,
    //   所以 snake / mushroom / insect / skull / tent 这类图标根本不存在,
    //   不要给它们编码位 —— 需要表达这些概念时用文字 chip, 不用图标.
    readonly property var _iconMap: ({
        // --- 导航 / 操作 ---
        "home":         "\ue88a",
        "menu":         "\ue5d2",
        "search":       "\ue8b6",
        "back":         "\ue5c4",
        "close":        "\ue5cd",
        "add":          "\ue145",
        "remove":       "\ue15b",
        "check":        "\ue5ca",
        "error":        "\ue000",
        "chevron_left": "\ue5cb",
        "chevron_right":"\ue5cc",
        "expand_more":  "\ue5cf",
        "expand_less":  "\ue5ce",
        "dropdown":     "\ue5c5",
        "more_vert":    "\ue5d4",
        "more_horiz":   "\ue5d3",
        "refresh":      "\ue5d5",
        "settings":     "\ue8b8",
        "share":        "\ue80d",
        "send":         "\ue163",
        "edit":         "\ue3c9",
        "delete":       "\ue872",
        "info":         "\ue88e",
        "help":         "\ue8fd",   // 圆圈问号 (原表把它当 "list" 用了)
        "list":         "\ue8ef",   // view_list
        "sort":         "\ue164",
        "filter":       "\ue152",
        "calendar":     "\ue878",   // 原表用 \ue5d3, 那是省略号
        "clock":        "\ue924",
        "note_add":     "\ue89c",
        "play":         "\ue037",
        "stop":         "\ue047",
        "flag":         "\ue153",
        "star":         "\ue838",
        "favorite":     "\ue87d",
        "favorite_off": "\ue87e",
        "bookmark":     "\ue8e6",
        "bookmark_off": "\ue8e7",
        "thumb_up":     "\ue8dc",
        "shield":       "\ue8e8",   // verified_user 盾牌
        "visibility":   "\ue8f4",
        "visibility_off":"\ue8f5",
        // --- 地图 / 轨迹 ---
        "map":          "\ue55b",
        "layers":       "\ue53b",
        "place":        "\ue0c8",
        "pin_drop":     "\ue55e",
        "navigation":   "\ue55d",
        "my_location":  "\ue55c",
        "explore":      "\ue568",   // 指南针罗盘
        "terrain":      "\ue564",
        "zoom_in":      "\ue8ff",
        "route":        "\ue55d",   // 本字体无 route, 用导航箭头
        "timeline":     "\ue16d",
        "trending_up":  "\ue8e5",   // 原表 \ue8a4 是别的东西
        "show_chart":   "\ue922",
        "lens":         "\ue03f",
        // --- 户外 / 图鉴 ---
        "hiking":       "\ue536",
        "bike":         "\ue91b",
        "car":          "\ue531",
        "train":        "\ue56f",
        "truck":        "\ue558",
        "fuel":         "\ue989",
        "restaurant":   "\ue56c",
        "cafe":         "\ue541",
        "store":        "\ue563",
        "equalizer":    "\ue01d",
        "drop":         "\ue91c",   // water_drop (湿度/降水)
        "plant":        "\ue545",   // local_florist 花
        "animal":       "\ue91d",   // pets 爪印
        "backpack":     "\ue53f",   // 注: 实为 admission 票券形, 只当"清单"抽象用
        "book":         "\ue54b",   // menu_book (原表 \ue54e 是价签)
        "photo":        "\ue412",
        "camera":       "\ue557",
        "add_a_photo":  "\ue8fc",
        "broken_image": "\ue562",   // 图裂, 用于"加载失败"占位
        // --- 急救 / 危险 ---
        "warning":      "\ue002",
        "alert":        "\ue002",
        "firstaid":     "\ue548",
        "call":         "\ue0cd",
        "call_add":     "\ue0e7",
        "safety":       "\ue8e8",
        // --- 2026-10-19 补: 页面在用但本字体没有对应物的概念, 全部换成实测存在的字形.
        //     旧映射是"猜"的: snake→垃圾桶, sos→平板设备, fieldguide→插图片,
        //     cpr→error, hypothermia→半圆, 真机上全是错的.
        "fieldguide":   "\ue54b",   // menu_book
        "firstaidbook": "\ue548",   // 急救箱
        "dangerspecies":"\ue002",   // 无蛇形, 用警告三角
        "sos":          "\ue0cd",   // 无 sos 形, 紧急求助用电话
        "cpr":          "\ue87d",   // 心形
        "bleeding":     "\ue000",   // 无止血形, 用醒目告警
        "snakebite":    "\ue002",
        "hypothermia":  "\ue8e8",   // 无体温计形, 用盾牌表"防护/保温"
        "pack":         "\ue53f",
        "knot":         "\ue5d2",   // 三道横纹, 视觉上接近绳股
        "shelter":      "\ue563",   // 雨棚形
        "build":        "\ue89c"    // note_add (应急清单), 旧值 \ue14c 其实是关闭叉
    })

    text: _iconMap[name] || ""
    // 字体未注册时清空 family 走系统字体 (至少不画 PUA 方框), 但这是降级路径,
    // 正常构建不会命中 — main.cpp 加载失败会打 qWarning.
    font.family: CommonOptions.iconFontReady ? "Material Icons" : ""
    font.pixelSize: size
    color: root.tintColor
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    onNameChanged: {
        if (name && !_iconMap[name])
            console.warn("IconLabel: unknown icon name '" + name + "'")
    }
    Component.onCompleted: {
        if (!CommonOptions.iconFontReady)
            console.warn("IconLabel: Material Icons 字体未注册, 所有图标将缺字")
    }
}
