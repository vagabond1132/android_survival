/**
 * @file IconLabel.qml
 * @brief Material Icons 字体图标组件 (2026-09-14)
 *
 * 依赖: assets/fonts/MaterialIcons-Regular.ttf (Google 官方)
 * 大小写: TTF 里是 "Material Icons" (空格)
 *
 * 用法:
 *   IconLabel { name: "home"; size: 24; tintColor: "white" }
 *
 * 字体加载失败时自动回退到 emoji (避免空白方框)
 */

import QtQuick
import QtQuick.Controls.Material
import OutdoorSurvival 1.0

Text {
    id: root

    // 公共属性
    property string name: ""
    property int size: 24
    property color tintColor: CommonOptions.colorText

    // Material Icons 字体 codepoint (PUA 0xE000-0xF8FF)
    readonly property var _iconMap: ({
        "home":         "\ue88a",
        "firstaid":     "\ue548",
        "warning":      "\ue002",
        "sos":          "\ue1b1",
        "photo":        "\ue412",
        "fire":         "\ue25d",
        "shelter":      "\ue563",
        "build":        "\ue14c",
        "knot":         "\ue5d2",
        "route":        "\ue558",
        "snake":        "\ue92b",
        "pack":         "\ue53f",
        "cpr":          "\ue000",
        "bleeding":     "\ue43c",
        "snakebite":    "\ue92b",
        "hypothermia":  "\ue427",
        "firstaidbook": "\ue548",
        "fieldguide":   "\ue1db",
        "map":          "\ue55b",
        "camera":       "\ue412",
        "dangerspecies":"\ue002",
        // 2026-09-19: 修 - 之前 \ue52f 是 directions_bike (自行车), 用户报徒步线路图标
        //   显示成自行车, 应改成 \ue536 (hiking 登山鞋)
        "hiking":       "\ue536",
        "car":          "\ue531",
        "backpack":     "\ue53f",
        "ambulance":    "\ue548",
        "alert":        "\ue002",
        "terrain":      "\ue564",
        "place":        "\ue0c8",
        // 2026-09-29: TravelListPage 列表行需要 (calendar / refresh),
        //   之前这两个码位直接写在 Text 里硬编码 font.family, 导致与中文混排.
        "calendar":     "\ue878",
        "refresh":      "\ue028"
    })

    // 字体未加载时用的 emoji 兜底
    readonly property var _emojiFallback: ({
        "home":         "🏠",
        "firstaid":     "🚑",
        "warning":      "⚠️",
        "sos":          "🆘",
        "photo":        "📷",
        "fire":         "🔥",
        "shelter":      "⛺",
        "build":        "🔧",
        "knot":         "🪢",
        "route":        "📍",
        "snake":        "🐍",
        "pack":         "🎒",
        "cpr":          "❤️",
        "bleeding":     "🩸",
        "snakebite":    "🐍",
        "hypothermia":  "❄️",
        "firstaidbook": "🚑",
        "fieldguide":   "📚",
        "map":          "🗺️",
        "camera":       "📷",
        "dangerspecies":"⚠️",
        "hiking":       "🥾",
        "car":          "🚗",
        "backpack":     "🎒",
        "ambulance":    "🚑",
        "alert":        "⚠️"
    })

    // 2026-09-16: 终极兜底 - 单字符 ASCII, 用于 emoji 也不显示的情况
    readonly property var _asciiFallback: ({
        "home":         "H",
        "firstaid":     "+",
        "warning":      "!",
        "sos":          "S",
        "photo":        "P",
        "fire":         "F",
        "shelter":      "T",
        "build":        "B",
        "knot":         "K",
        "route":        "R",
        "snake":        "~",
        "pack":         "B",
        "cpr":          "+",
        "bleeding":     "B",
        "snakebite":    "~",
        "hypothermia":  "*",
        "firstaidbook": "+",
        "fieldguide":   "F",
        "map":          "M",
        "camera":       "C",
        "dangerspecies":"!",
        "hiking":       "H",
        "car":          "C",
        "backpack":     "B",
        "ambulance":    "+",
        "alert":        "!"
    })

    // 2026-09-16: 检测系统是否有 emoji 字体 (Noto Color Emoji / Apple Color Emoji)
    readonly property bool _emojiAvailable: {
        var families = Qt.fontFamilies()
        for (var i = 0; i < families.length; i++) {
            var f = families[i].toLowerCase()
            if (f.indexOf("emoji") >= 0) return true
        }
        return false
    }

    // 2026-09-17: 检测 Material Icons 字体是否已注册到系统
    // 之前用 Qt.fontFamilies() 静态查询, 但 readonly bool 求值后不会重算 —
    // 在 IconLabel 第一次实例化时如果 FontLoader 还在 loading, _fontAvailable
    // 会被锁死成 false, 之后即便字体已注册也仍走 emoji / ASCII 兜底,
    // 而 emoji 字体在部分 Android 系统上不存在, 最终显示为方框.
    // 修法: 改成"绑定到 Main.qml 的 materialIconsFont.status", status 是
    // FontLoader 的属性, QML binding 会在 Loading→Ready 时自动重算, 实时.
    readonly property bool _fontAvailable: {
        var loader = (typeof materialIconsFont !== "undefined" && materialIconsFont)
                     ? materialIconsFont
                     : null
        if (loader && loader.status === FontLoader.Ready) return true
        // 兜底: 某些场景下 Main.qml 未实例化 (如 qml scene preview 工具),
        //   用 Qt.fontFamilies() 查一下
        var families = Qt.fontFamilies()
        for (var i = 0; i < families.length; i++) {
            if (families[i] === "Material Icons") return true
        }
        return false
    }

    // 渲染
    // 2026-09-20 修: 之前 _fontAvailable 取决于 Qt.fontFamilies() 是否含 "Material Icons",
    //   但 FontLoader 是异步的, IconLabel 首次 evaluate 时若 Main.qml 的 FontLoader
    //   还在 Loading, _fontAvailable 锁死 false → 走 emoji / ASCII 兜底 → 系统的
    //   PUA codepoint (\ue536 等) 又被默认字体画方框.
    //
    //   真正可靠的修法: 把 _fontAvailable 绑定到 Main.qml 的 materialIconsFont.status
    //   (FontLoader 的属性, 是 binding 依赖, Loading→Ready 时自动重算).
    //   若字体加载成功, 用 PUA codepoint 直接画 (Material Icons 字体内部就是 PUA 区);
    //   若失败, 改用 emoji 或 ASCII, 并把 font.family 清空 (走系统字体画 emoji).
    text: {
        var loader = (typeof materialIconsFont !== "undefined" && materialIconsFont)
                     ? materialIconsFont : null
        var fontReady = (loader && loader.status === FontLoader.Ready)
                        || (function() {
                            var families = Qt.fontFamilies()
                            for (var i = 0; i < families.length; i++) {
                                if (families[i] === "Material Icons") return true
                            }
                            return false
                        })()
        if (fontReady) return _iconMap[name] || ""
        // 字体没就绪, 用 emoji 兜底 (前提是系统有 emoji 字体, 如 Noto Color Emoji)
        if (_emojiAvailable) {
            return _emojiFallback[name] || _iconMap[name] || "?"
        }
        return _asciiFallback[name] || "?"
    }
    // 关键: 字体就绪时 family 必须 = "Material Icons" 才能让 PUA codepoint 出图.
    //   字体未就绪时 family = "" 让系统字体去画 emoji / ASCII (避免 PUA 在默认字体下变方框).
    font.family: {
        var loader = (typeof materialIconsFont !== "undefined" && materialIconsFont)
                     ? materialIconsFont : null
        var fontReady = (loader && loader.status === FontLoader.Ready)
                        || (function() {
                            var families = Qt.fontFamilies()
                            for (var i = 0; i < families.length; i++) {
                                if (families[i] === "Material Icons") return true
                            }
                            return false
                        })()
        return fontReady ? "Material Icons" : ""
    }
    font.pixelSize: size
    color: root.tintColor
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    onNameChanged: {
        if (name && !_iconMap[name]) {
            console.warn("IconLabel: unknown icon name '" + name + "'")
        }
    }
}
