/**
 * @file DangerChip.qml
 * @brief 统一危险等级色条 (5 阶段架构重构 Phase 3 建立, 2026-10-16 接 token)
 *
 * 背景: 5 处 species 显示 danger level, 各自写 5 段 if-else, 色值/阈值不一致.
 *       抽成统一组件后色值阈值一处定义.
 * 2026-10-16: 那 5 段色值从本文件的局部数组上移到 CommonOptions::dangerColor(),
 *   因为图鉴列表 / 地图 marker / 详情页警示也要用同一套色, 不能只活在 chip 里.
 *   色值本身一字未改 (绿/黄/橙/深橙/红 + 未知=中性灰), 避免既有观感漂移.
 *
 * 等级映射 (1-5): 1 安全 / 2 低度 / 3 中度 / 4 高度 / 5 致命
 */
import QtQuick
import OutdoorSurvival 1.0

Rectangle {
    id: root

    property int level: 1         // 1-5
    property bool compact: false  // 小尺寸 (用于列表项)
    property string label: ""     // 自定义标签 (默认按 level 翻译)

    readonly property var _labels: ["安全", "低度", "中度", "高度", "致命"]

    readonly property color _bg: CommonOptions.dangerColor(level)
    // 2026-10-19 真机 (103_guide.png): 图鉴里荠菜/蒲公英/马齿苋这类可食野菜全被打成
    //   灰色"未知". 但 danger_level=0 在数据侧不是"缺失" —— FieldGuideIndex.h 明确写
    //   "0=无害可食", 四个 field_guide_*.json 里共 365 条是 0. 一个采食 App 把"无害"
    //   显示成"未知"是语义错误, 用户无法区分"数据说安全"和"数据没填".
    //   0 单独给"无危险", 颜色仍走 dangerColor(0) 的中性灰 (与 1=安全的绿区分开),
    //   只有真正越界 (<0 / >5) 才叫"未知".
    readonly property string _text: label !== "" ? label
        : (level === 0 ? "无危险"
           : (level >= 1 && level <= 5 ? _labels[level - 1] : "未知"))

    Styles { id: styles; visible: false }

    color: _bg
    radius: compact ? styles.rSm : styles.rMd
    implicitHeight: compact ? 18 : 24
    implicitWidth: txt.implicitWidth + (compact ? styles.spSm + styles.spXs
                                                : styles.spLg)

    Text {
        id: txt
        anchors.centerIn: parent
        text: root._text
        color: CommonOptions.colorTextOnAccent
        font.pixelSize: root.compact ? styles.fsXs : styles.fsSm
        font.bold: !root.compact
    }
}
