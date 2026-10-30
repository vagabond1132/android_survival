# qml_checks —— qmllint 管不到的那一半门禁

`tools/qml_lint.sh` 跑的是 qmllint，但 qmllint **解析不了 `CommonOptions` 和各个
`xxxService`**（它们是 `main.cpp` 用 `setContextProperty` 注入的上下文属性），
拼错属性名它一声不吭。这一半由本目录的 JS 检查器兜着。

- 默认扫描根目录 = 本文件所在目录的 `../../qml`（数据类检查器是 `../../assets/data`），
  所以从仓库任何位置都能跑；也可以传第一个参数指定别的根目录。
- 判读：`pragma/layout_prop/mono_cjk/crossfile_id/undefined_id/component_id_scope/int_prop/bound_model/singleton_import/controls_import/layout_collapse/delegate_shape/coord_metadata/filter_rebuild`
  这 14 个是 **pass/fail 门禁，期望 0 条**；
  后 3 个是**打印诊断**，不给出退出码结论。
- 逐条判读规则与对账表见 `doc/08-索引与概念/全代码索引.md` §18.1。

## 怎么跑

Windows 主机上没有 node，用 Qoder 自带的 Electron 当 node：

```bash
cd /d/build_docker/app/tools/qml_checks
export ELECTRON_RUN_AS_NODE=1
"/c/Users/Administrator/AppData/Local/Programs/Qoder/Qoder.exe" pragma_check.js
```

传根目录时**必须给 Windows 看得懂的路径**（`D:/build_docker/...`），不要给
`/tmp/...` 或 `/d/...` —— Electron 是原生 Windows 进程，`/d/x` 会被它当成
`D:\d\x`，`fs.existsSync` 直接 false，检查器一声不响地报 0 条，看起来像"全绿"。
这个坑实测踩过：拿一个故意写坏的 fixture 验 `int_prop_check.js`，前两次都返回 0，
以为脚本坏了，其实是根目录压根没被读到。**任何"0 条"结论都要先用一个已知命中的
样例反证脚本是活的。**

两个容器 (`outdoor-survival-builder` 和 compose 起的 `unit-test` 服务) 里都**没有 node**
(`which node` 空)，所以下面 20 个脚本只在 Windows 主机跑 —— 其中 **17 个带退出码** (0 干净 / 1 有命中 / 2 自己没跑成)，
另外 3 个 (`nav_reach_check.js` 与 `route_list_logic_check.js`、`travel_list_logic_check.js`) 不带退出码，
是人工核对 / 逻辑取证 dump。
2026-10-28 #156 之前有 5 道 (跨组件/跨文件 id、mono_cjk、pragma、悬空 id) 只打印"命中 N 处"而**永远 exit 0** ——
写成脚本串起来跑时那就是假绿，现已补齐退出码。
搬进仓库是为了进版本控制、并且根目录不再写死绝对路径；哪天容器装了 node，
直接 `node tools/qml_checks/pragma_check.js` 即可（仓库挂载在 `/project`）。

需要真正**实例化**组件树才能暴露的那一类（见下一节），不在这里，在
`tools/qml_load_check.sh`（只能在 compose 的 `unit-test` 服务里跑 —— builder 镜像的桌面 Qt
缺 QtLocation/QtPositioning，会在 MapPage 上整支失败；用法见该脚本头部）。

## 清单

| 脚本 | 守什么 | 期望 |
|---|---|---|
| `pragma_check.js` | delegate 里引用外层 id 却没写 `pragma ComponentBehavior: Bound` —— qmlcachegen 静态编译下真机静默 ReferenceError | 0 条 |
| `layout_prop_check.js` | 布局子项上写 `width:/height:/anchors:`，或写 `Layout.visible`（Qt6.7 的 `QQuickLayoutAttached` 没这个属性，是加载期硬错误，整页白屏） | 0 条 |
| `mono_cjk_check.js` | `styles.monoFont` / `Material Icons` 字形对象里混进汉字（该字体没有 CJK 字形，回退失败出方框） | 0 条 |
| `icon_glyph_check.js` | **图标名不在 `IconLabel._iconMap` 的码位表里**（2026-10-28 #156 加）。`_iconMap` 是全站唯一码位来源：写了字体里没有的名字，桌面上只是那一格空着，真机上就是动作带/筛选行缺图 + 一句 `console.warn`，而 release 包 logcat 全空。这一轮 #156 新加的四枚图标里有两枚当场中招（`layers_clear`、`restart_alt` → 换成表内已有的 `delete`），说明这事靠肉眼不可持续。查三个图标槽：`IconLabel { name: "…" }`（**限定在 IconLabel 块内**，避开地图图层列表 `{ name: "osm" }` 这种同名不同义）、组件透传的 `iconName:`、动作带/筛选行数据里的 `icon:`；`x.name : "y"` 这类三元取属性靠"前面不许是点"排除。`icon: modelData.icon` 这种变量表达式静态验不了，由写那份字面量的 .qml 兜住。**盖不住**：图标语义对不对（`delete` 画在"清空"上好看吗）仍靠真机逐张判 | 0 处（93 码位 / 63 个 .qml / 157 图标槽；双向反证：fixture 里 3 个坏名全命中，同 fixture 的合法 `place` 与两处非图标 `name:` 不误报） |
| `layout_collapse_check.js` | **没有 implicitHeight 的纯 Item 系**（`Rectangle`/`Item`/`Flickable`…）直接当 `ColumnLayout`/`RowLayout`/`GridLayout` 的子项，自己不给任何高度来源，块内又 `anchors.fill: parent` —— 布局分配高度 0，卡片塌陷、内容溢出压住后面几行。真机上像"数据把文字叠乱了"，人眼极难归因（2026-10-22 巡检抓到 `EquipmentPage.qml:1040` 与 `RouteGearRecommendPage.qml:762` 两处同一份复制体）。**`StackLayout` 已排除**：它强制把子项拉成自己的尺寸，不给高度也不塌 | 0 条 |
| `crossfile_id_check.js` | 跨文件抓别的 QML 的 id（`mapPage.x` 之类）—— id 是文件级作用域，运行期 ReferenceError，只能靠宿主透传属性 | 0 条 |
| `undefined_id_check.js` | 绑定**全工程从没声明过的 id**（2026-10-23 #113 加）。`crossfile_id_check.js` 只报"这名字在别的文件里有 id"，全工程查无此名的它直接放过 —— 于是 `FieldGuideDetailPage.qml` 里那句 `implicitHeight: markRowCol.implicitHeight + ...`（`markRowCol` 从来不存在）一路活到真机：绑定求值即抛 ReferenceError，`implicitHeight` 停在默认 0，46 行标注塌成 0 高叠成一团黑字，而 release 包 logcat 全空。判据只认"小写名字 + . + 几何/可见性属性"的形状，先收齐本文件能起名的位置（id/property/var/形参/lambda/catch），再扣掉 `setContextProperty` 注入的服务名和 Qt 全局名。**当前干净树报"悬空 id 引用 0 处"，该"0 条"已拿故意悬空 id 的 fixture 反证过脚本是活的（本目录通用规矩，见上文"怎么跑"）** | 0 条 |
| `component_id_scope_check.js` | **id 声明在别的组件里，本处却跨作用域引用**（2026-10-27 #134 加）。`id` 的作用域是**组件**（每个 `delegate` / `Component` 各一份），不是文件；`undefined_id_check.js` 的判定是"全工程查无此名"，名字在同文件别处声明过就被它放过了。真机现场：MapPage 的**轨迹**行 delegate 里写 `color: hoverArea.containsMouse ? …`，而 `hoverArea` 声明在**路线**行 delegate 里 —— 绑定求值抛 ReferenceError 被吞，`color` 停在 `color` 的类型默认 `#FFFFFF`，于是「轨迹」Tab 每一行都是白底白字，看着像"轨迹色彩标注坏了"。脚本单遍扫花括号给每个字节标上所属组件（`delegate`/`Component` 才算边界，`Styles { id: styles; }` 这种普通对象块不算），再把 `id: X` 记到**最近的外层组件**，最后要求每处 `X.prop` 的引用点沿组件链上溯能找到声明处。**已拿故意改回 `hoverArea` 的 MapPage 副本反证：正好命中 1 处** | 0 条 |
| `int_prop_check.js` | **int 属性写了字面小数**，如 `font.pixelSize: 13.5`。加载期硬错误 `Invalid property assignment: int expected`，整棵组件树建不起来、app 启动即退；qmllint / qmlcachegen / ctest 三道都不报（2026-10-21 真机就是这么炸的）。只报值本身带小数的字面量：`2.0` 放过，`styles.fsXs`（real 绑定，Qt round-half-up：8.5→9）放过 | 0 条 |
| `bound_model_check.js` | 写了 `pragma ComponentBehavior: Bound` 的文件里，delegate 继续用视图注入的 `model` / `index` / `modelData`。Bound 语义会**移除**这三个上下文属性，必须改成 `required property`；不改就是真机整行静默画空（Main.qml 抽屉 13 行全空）。字符串字面量与注释都先换成等量空白再匹配，所以文案里出现 "model" 不误报，行号也不移位 | 0 条 |
| `singleton_import_check.js` | 用了 `CommonOptions` / `App` / `ImageColorExtractor` 却没写 `import OutdoorSurvival 1.0`。这三个是 `qmlRegisterSingletonInstance` 的**模块单例**，与 `xxxService` / `styles`（`setContextProperty` 上下文属性，不需要 import）不同来源，缺 import 就每次求值抛 `ReferenceError` 并静默画空——2026-10-21 全站图标 100% 方框、绳结难度梯整体变黑都是这一条。只匹配 `<单例>.` 成员访问，同名属性定义不误报。**新增模块单例时要同步改脚本里的 `SINGLETONS`** | 0 条 |
| `controls_import_check.js` | **裸 `import QtQuick.Controls`**（不带 `.Material` 后缀）。androiddeployqt 只打包真正被 import 到的插件，本项目基座是 Material，所以包里只有 `..._Controls_Material_*` 与 impl，**基座的 `qtquickcontrols2plugin` 不在 APK 里**。这行在桌面上跑得通，到真机就是 `StackView: push: MePage.qml:17 module "QtQuick.Controls" plugin ... not found` —— push 不出对象、页体一句不画，而 release 包 logcat 全空（2026-10-23「我」页整页空白，#106）。修法是按那句报错**删掉**裸 import：`Page`/`ScrollView`/`Switch` 在 `QtQuick.Controls.Material` 的 qmldir 里逐个列过，不需要基座插件，也别为这一行多塞 12KB。注释与字符串先换成等量空白再匹配，所以 MePage 里讲解这条坑的注释本身不误报 | 0 条 |
| `typed_member_check.js` | **在能被 qmllint 解析出类型的 Qt 类型上读写它没有的成员**（2026-10-28 #156 加）。三类的共同点是一条都不报：绑定求成 `undefined`，分支永远走 else，功能"看起来实现了、其实一条没生效"。① `HoverHandler` 没有 `containsMouse`（那是 `MouseArea` 的）→ 悬停要用 `hovered`；② Qt 6.7 的 `StackLayout` 没有 `currentItem`（那是 `StackView` 的，容器内 offscreen 实测 `"currentItem" in stack` === false）→ 按 `currentIndex` 从 id 表自己取；③ `Popup`/`Drawer`/`Menu`/`Dialog` **自身**写了 `y:`/`x:`/`position:` 声明式绑定 → 绑定优先级压过开合动画，`open()`/`close()` 只改数值、卡片纹丝不动（块内深度 1 才算，子项自己的 `y:` 不管）。真机现场：`MapBottomSheet._syncTabHeight()` 用 `stack.currentItem` 取当前面 → 永远 `undefined` → 抽屉高度永远退回 409，「记录」面按内容自报高度那条改动整条静默失效；`MapPage` 两个清单行读 `hoverArea.containsMouse` → 悬停高亮永远不亮。**qmllint 本来就报这三类（`[missing-property]`），但 2000 行 `unqualified` 噪声里没人逐条看**，所以要一道只为此存在的门禁；跑完 lint 至少要 `grep missing-property` 一遍自己本轮改过的文件。**盖不住**：`ApplicationWindow.window.navBus` 这类拿不到静态类型的成员（qmllint 也只能报 QObject，属噪声），那部分靠 `tools/qml_load_check.sh` 真实例化 | 0 处（65 个 .qml / 3 个具名块；双向反证：`qml/_gate_fixture_bad.qml` 里四条坏写法全命中、exit 1，fixture 已删） |
| `delegate_shape_check.js` | head/item 混排列表行：delegate 里 `visible: modelData.kind === "head"` 二选一，但 **`visible:false` 不阻止绑定求值**，所以只要两支 model 字面量的键集合不齐，真机就一路刷 `Unable to assign [undefined] to QString/QColor/int`（进一次列表页 206 条）。只查 delegate **真的读了**的 `modelData.X`；注释先剥掉；别的 Repeater（读数格之类）不算。当前 9 个页 / 11 处用这个 pattern | 0 个文件 |
| `coord_metadata_check.js` | **端点精度元数据与轨迹结构与数据自洽**（2026-10-27 #131c 加）。查六件事：`coord_precision_m`/`coordPrecisionM` 不许比坐标字面量的量化下限还准（虚报）· `coord_source`/`coordSource` 在认可集合内且与 `waypoints` 互证（标成 GPS 实测却没轨迹 = 图上那条线其实是起终点直线）· 端点缺坐标必须带 `coord_unavailable`/`endCoordUnavailable` 且保住地名 · E1/E2 两条可证伪规则没复发 · `waypoints` 的类型/`sequence`/坐标/海拔/命名 · travel.json 不出现蛇形键（解析端读驼峰，混用=全站读数静默消失）。**精度按"量化下限"而不是"相等"判**：两步路 KML 打印 5 位小数（±1 m），但手机 GPS 实际 3~10 m，`kml_to_routes.js` 标 ±10 m 是对的保守值。真实库 0 处；已拿 11 类破坏的 fixture 反证（`_scratch_debug/qmlcheck_neg_coord_data`，命中 12 处、exit 1） | 0 处 |
| `filter_rebuild_check.js` | **筛选器改了状态但列表不重算**（2026-10-27 A36 加）。链条：根上 `property` P 被**输入处理器**（onClicked/onActivated/onComboActivated/onToggled/…）赋值 → 某个函数 F 读了 P 且 F 给"喂 `model:` 的属性"赋过值（= 列表是命令式拼的，不是声明式绑定）→ 那必须要么本文件有 `on<P>Changed:`，要么那个处理器自己调 F，否则报。真机现场：急救页点「环境急症 3」chip 变选中态、下面 35 条一行没少 —— `rows` 只在 `reload()` 里赋值，而 `reload()` 只挂在 `Component.onCompleted` 和 `firstAidService.dataChanged` 上。**同一份复制体在 急救/绳结/野外生活 三页各一份**，逐页排查时才发现，所以补了这道门禁。两个已判过的口径：① **赋值左值不算读**（`RouteDetailPage._load()` 里 `entity = routeService.getById(...)` 是取数不是分支，早版把它报成缺陷）；② **显式提交式设计豁免** `MapPageComponents/SearchTab.qml`（选完省份/难度要按「搜索」才查库，是设计不是漏触发，理由写死在脚本的 `EXEMPT` 里）。**不覆盖**：函数读了 P 但不给 model 属性赋值的（装备推荐页换月份后气候读数不重算 A37 就是这一类，静态上判不出"该不该跟着变"），那类仍靠真机 + stage0.log | 0 处 |
| `bottom_clearance_check.js` | **吸底条把列表末行切一半**（2026-10-28 A41 加，2026-10-28 #157 扩）。两遍判定：**标记口径**（A41 原样）—— 凡写了 `// --- 底栏` 标记，标记所在父块内、标记之前必须有 ① 滚动区（`Layout.fillHeight: true` / `anchors.fill: parent` / `ScrollView`/`ListView`/`GridView`/`Flickable`）② `styles.bottomClearance`。**结构口径**（#157 加，不靠注释也不靠组件名名单）—— `ColumnLayout`/`Drawer` 的**最后一个可见直接子项**，高度钉在 `styles.*` 且该 token 实测 >= 44 逻辑（数值表从 Styles.qml 现场解析，明天新条带组件按规矩钉 `styles.<token>` 就不用改门禁），或是"根块自带这种钉高"的组件实例（SheetActionBand 的钉高写在组件根块里，实例处什么都不写 —— 就靠这张表认；SheetPanelHead 同为 44 钉高行但永远是首子项，靠"最后一个可见子项"排除）→ 认定为吸底条。让位判法分形状：钉高在本文件子项块上的仍按最严口径（同层必须 bottomClearance/bottomMargin）；组件根钉高的带子老老实实当布局子项 → 布局分配即让位（#156 工作端口径），一旦 `anchors.bottom` 逃出布局浮在视口上且同层没让位 → 报。**扫描面**（#157 ①）：`qml/pages/` 与 `qml/components/` 全树递归（旧版只 readdirSync pages/ 一层，MapPageComponents/ 四个工作台 Tab 与整个 components/ 从来不在面上 —— 旧门禁的绿是"没看"不是"没得查"），并打印**逐目录文件数**；根下找不到 pages/ 与 components/ 或 GLOB 过滤后 0 文件直接 exit 2，绝不静默 0 条。第 2 个参数是**范围过滤**（相对路径子串匹配，只收窄检查面，数据表仍全量建），专门用来拿 scratch fixture 反证。**标记锚也修了**：旧正则 `①-⑩]*\s*底栏` 匹配不到 `// --- ④ 固定底栏`（FieldGuideDetailPage:1521 从 A41 到 #157 之间从没被标记口径查过，就是 README 上面说的"锚太紧的静默绿"第三例）。**盖不住**：`KnotPage`/`FirstAidPage` 让位量写在 `ListView.footer` 高度里的（不在同层，结构上看不到），仍靠真机逐张判 | 0 处（当前底栏标记 13 处 + 结构吸底条 2 处全覆盖；已拿 `D:/build_work_ai_dir/bcc157/fixture_qml/` 的已知命中反证：`NegTabOverlay.qml`（ColumnLayout 里 ListView fillHeight + SheetActionBand 改 anchors 浮层、无 bottomClearance）**新口径 exit 1 命中、旧口径同目录跑 exit 0 一条不报** —— 双向都证了） |
| `nav_reach_check.js` | 每页被谁 `navigateTo`，反查孤儿页。**有盲区**：URL 是算出来的那几页（HomePage / MePage / FieldGuidePage / TrackDetailPage）会误报"无人调用" | 人工核对 |
| `route_list_logic_check.js` | 把 `RouteListPage.rebuild()` 照搬到 JS，对真数据跑一遍，打印分组数/条数/月份分布，用来肉眼看筛选语义有没有跑偏 | 人工核对 |
| `travel_list_logic_check.js` | 同上，针对 `TravelListPage`。当前会报「编号撞车 5 对」—— plateCode 全局唯一只是好看，组内不重复才影响阅读；数据本轮冻结不动 | 人工核对 |

## 加新检查器的规矩

只准读文件、打印结论，**不写任何文件**；根目录一律走 `__dirname` 相对定位，
不要写 `D:/build_docker/...` 这种绝对路径（这条就是本目录从仓库外的
`_scratch_debug/` 搬进来的原因 —— 搬进来它们才进得了版本控制）。
