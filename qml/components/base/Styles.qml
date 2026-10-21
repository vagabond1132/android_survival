/**
 * @file Styles.qml
 * @brief 设计 token — 间距 / 字号 / 圆角 / 控件尺寸 / 图标字体 (2026-09-14 建立, 2026-10-16 补全)
 *
 * CommonOptions 装颜色, Styles 装布局尺寸.
 * 不是一个 QML 单例 (避免上次 qmlcachegen 静态编译 + pragma Singleton 的坑),
 * 而是普通 Item. 在 Page 顶部 `Styles { id: styles; visible: false }` 实例化, 然后 styles.spLg 用.
 *
 * 所有属性 readonly, 多实例不会冲突, 也不会有运行时开销.
 *
 * 2026-10-16 改版补全的三组:
 *   ① 页面骨架 (页边距 / header / 底栏) — 之前各页自己写 8/12/16 混用
 *   ② 控件尺寸 (卡片 / 列表行 / 按钮 / chip) — 之前同一组件在不同页 44/48/56/72 都有
 *   ③ iconFont — Material Icons 字体族名收口. 全 App 的 PUA 码位图标必须走
 *      `font.family: styles.iconFont`, 之前 132 处里有 1 处漏设导致真机显示方框.
 *
 * 2026-10-20 「地物图例」改版 (底色方案 A 已锁定, 骨架 = 丁 罗盘 + 第 5 格「我」):
 *   ④ 字号收成 5 档. 原来 8 档 (10/12/14/16/18/22/28/48) 在同一屏里会出现
 *      14 与 16 这种"差一档但看不出差别"的相邻字号, 层级就糊了.
 *      现在: 21 / 15 / 12.5 / 10.5 / 8.5, 相邻档差 ≥1.5x 或语义明确.
 *      fsXl 与 fsLg 同值 (区块标题靠加粗 + 描边分级, 不靠字号). 最大的一档就是
 *      fs2xl(21): 版面上更大的数字是"读数", 由详情页自己按 34px 写死, 不占字号梯.
 *      类型从 int 改成 real: 12.5 / 10.5 / 8.5 是半档, QML 的 pixelSize 收 real.
 *   ⑤ 间距网格 4 / 8 / 12 / 16 / 22.
 *   ⑥ 三级描边 (--rule-soft 组线 / --rule 普通卡 / --ink 强调).
 *      描边粗细都是 1px, 分级靠颜色, 所以这里是颜色 token (CommonOptions) 而不是尺寸.
 *      一屏最多 2 处强调描边 —— 等粗描边等于没有强调.
 *   ⑦ monoFont: 所有数字/坐标/编号/等宽读数走等宽字族. CJK 一律不加 letterSpacing
 *      (拉开字距的中文像假字, 那是上一版最大的败笔之一).
 *   ⑧ 丁骨架新增尺寸: 盘 (dialSize) / 5 方位导航条 (navBandH) / 方位列 (bearingColW)
 *      / 图版角标 (plateW) / 危险斜纹带 (hazardBandW).
 */

import QtQuick

Item {
    id: styleRoot

    // === 间距 (2026-10-20 网格 4/8/12/16/22) ===
    readonly property int spXs: 4     // 极小, 标签内边距
    readonly property int spSm: 8     // 小, 卡片内边距 / 控件间距
    readonly property int spMd: 12    // 中, 行间距
    readonly property int spLg: 16    // 大, 区块外边距
    readonly property int spXl: 22    // 超大, section 分隔

    // === 字号 (5 档, 见文件头 ④) ===
    readonly property real fsXs: 8.5      // 微标签 / 单位 / 编号 (只给拉丁与数字加 letterSpacing)
    readonly property real fsSm: 10.5     // 等宽数据 / 副标题
    readonly property real fsMd: 12.5     // 正文
    readonly property real fsLg: 15       // 卡片标题 / 主操作文案 / 区块标题
    readonly property real fsXl: 15       // 区块标题 = 与 fsLg 同值, 靠字重与描边分级
    readonly property real fs2xl: 21      // 页面 hero / 大号等宽读数
    // 2026-10-20: fsOversized(48) / fsDisplay(72) 随 SOS 大圆盘与倒计时一起删除.
    //   ⑤改版后求救触发也走 HoldConfirmRow 的 44px 行, 页面里没有需要 48px 以上
    //   字号的地方; 留着只会有下一个页面照着它抄出一个超大字.

    // === 圆角 ===
    // 「地物图例」是印刷场卡, 角是"切"的不是"糊"的: 卡片一律 0 圆角,
    // 只有 chip 保留胶囊. 圆角半径与 rMd/rLg/rXl 一起降到 2/0/0, 避免 Material 味.
    readonly property int rSm: 2     // 小, 标签 / chip 方角
    readonly property int rMd: 0     // 卡片 — 直角
    readonly property int rLg: 0     // 弹窗 / 主卡片 — 直角
    readonly property int rXl: 0     // hero 卡片 — 直角
    readonly property int rPill: 999 // 胶囊 (chip 专用, 全站只有 chip 用圆)

    // === 描边 (三级, 粗细同 1px, 分级看 CommonOptions 颜色) ===
    readonly property int lineHair: 1     // 分隔线 / 卡片描边
    readonly property int lineAccent: 3   // 主操作左侧橙条 / 危险左色条
    readonly property int hazardBandW: 6  // 危险斜纹带: 只占左侧 6px, 文字永远压在干净卡面上

    // === 图标 ===
    // Material Icons 字体族名 (= assets/fonts/MaterialIcons-Regular.ttf 内部字族名).
    // 凡 text 里出现 PUA 码位 (\ue000-\uf8ff) 的 Text/Label 都必须绑这个, 否则真机出方框.
    readonly property string iconFont: "Material Icons"
    // 数字/坐标/编号的等宽字族. 站内没打包 IBM Plex Mono (国内取不到且 APK 已经
    // 49MB), 用 Android 系统的 monospace 族. 真机若回退成比例字体, 只改这一行.
    // 铁律: 绑了这个族的一个 Text 只许装拉丁与数字. 汉字交给 monospace 会走字形
    // 回退, 真机上回退失败就是方框 (Dial 盘心副行、①的"最近 N · 右前方"都踩过).
    // 一句读数里既要等宽数字又要中文说明时, 拆成两个 Text 并排, 别写进同一个.
    readonly property string monoFont: "monospace"
    readonly property int icSm: 16
    readonly property int icMd: 20
    readonly property int icLg: 24
    readonly property int icXl: 32
    readonly property int icBoxSm: 32   // 图标底板 (小)
    readonly property int icBox: 40     // 图标底板 (列表行)
    readonly property int icBoxLg: 48   // 图标底板 (功能入口)

    // === 页面骨架 ===
    readonly property int pageMargin: 14      // 页面左右安全边距 (mock 的 .bd padding)
    readonly property int pageGap: 12         // 页面纵向区块间距
    readonly property int titleHeight: 44     // 窗口顶部标题条 (菜单 / 标题 / 搜索)
    readonly property int chartH: 160         // 内嵌图表卡片 (海拔剖面 / 速度曲线)
    readonly property int bottomSheetPeek: 80 // 地图底栏折叠时露出高度
    // sosSize(200) 已删: SOS 圆盘换成 HoldConfirmRow, 见上面字号那条评论.

    // === 控件尺寸 ===
    readonly property int rowH: 52        // 标准列表行
    readonly property int rowHTall: 60    // 带副标题的列表行
    readonly property int rowHSm: 36      // 紧凑行 (筛选行的 combo/chip/stepper 三模式同高)
    readonly property int cardPad: 10     // 卡片内边距 (全站固定 10, 不再 8/11/12 混用)
    readonly property int cardGap: 8      // 卡片内元素间距
    readonly property int btnH: 44        // 主按钮 (Android 最小可点击高度)
    readonly property int btnHSm: 32      // 次级 / 行内按钮
    readonly property int chipH: 24       // 筛选 chip (原 28 在浅色底上显胖)
    readonly property int fieldH: 44      // 输入框
    readonly property int touchMin: 44    // 可点击元素最小热区

    // === 「地物图例」丁骨架专用 ===
    readonly property int navBandH: 48        // 底部 5 方位导航条 (BASE/RES/ROUTE/SOS/我)
    readonly property int dialSize: 130       // 罗盘外径: ①营地用的小盘 (整屏只有一个主角)
    readonly property int dialSizeLg: 200     // ⑤求助 / 地图页展开用的大盘
    readonly property int dialHub: 58         // 盘心读数圆 (小盘 58 / 大盘 92)
    readonly property int dialHubLg: 92
    readonly property int dialPip: 6          // 盘上目标点 (小盘 6px, 只作发现不作点击热区)
    readonly property int dialPipLg: 9
    readonly property int bearingColW: 50     // 列表行左侧方位列 (图标 + 角度)
    readonly property int plateW: 46          // 图鉴编号角标宽度 ("SV-007" 等宽 8.5px)
    readonly property int readoutPad: 6       // 墨底仪表内边距 (①与⑤共用 PositionReadout)
    readonly property int readoutCellGap: 11  // 仪表四格读数间距
    // ⑤求助墨底仪表里的迷你盘: mock 给的是 74px —— 130 的盘塞进 92px 高的仪表
    // 会把整块顶开, 而仪表是"读数", 不该比号码列表更占屏幕.
    readonly property int dialSizeMini: 74
    readonly property int numChip: 24         // 紧急号码方块 (120/110/119)
    readonly property int holdBarW: 52        // 长按确认进度条 (52×9)
    readonly property int holdBarH: 9
}
