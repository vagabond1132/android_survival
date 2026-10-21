# qml_checks —— qmllint 管不到的那一半门禁

`tools/qml_lint.sh` 跑的是 qmllint，但 qmllint **解析不了 `CommonOptions` 和各个
`xxxService`**（它们是 `main.cpp` 用 `setContextProperty` 注入的上下文属性），
拼错属性名它一声不吭。这一半由本目录的 JS 检查器兜着。

- 默认扫描根目录 = 本文件所在目录的 `../../qml`（数据类检查器是 `../../assets/data`），
  所以从仓库任何位置都能跑；也可以传第一个参数指定别的根目录。
- 判读：`pragma/layout_prop/mono_cjk/crossfile_id/int_prop/bound_model/singleton_import`
  这 7 个是 **pass/fail 门禁，期望 0 条**；
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

`ut` 容器里**没有 node**（`which node` 空），所以这 10 个检查器只在 Windows 主机跑。
搬进仓库是为了进版本控制、并且根目录不再写死绝对路径；哪天容器装了 node，
直接 `node tools/qml_checks/pragma_check.js` 即可（仓库挂载在 `/project`）。

需要真正**实例化**组件树才能暴露的那一类（见下一节），不在这里，在
`tools/qml_load_check.sh`（跑在 ut 容器里，用桌面 Qt 的 `qml` + offscreen）。

## 清单

| 脚本 | 守什么 | 期望 |
|---|---|---|
| `pragma_check.js` | delegate 里引用外层 id 却没写 `pragma ComponentBehavior: Bound` —— qmlcachegen 静态编译下真机静默 ReferenceError | 0 条 |
| `layout_prop_check.js` | 布局子项上写 `width:/height:/anchors:`，或写 `Layout.visible`（Qt6.7 的 `QQuickLayoutAttached` 没这个属性，是加载期硬错误，整页白屏） | 0 条 |
| `mono_cjk_check.js` | `styles.monoFont` / `Material Icons` 字形对象里混进汉字（该字体没有 CJK 字形，回退失败出方框） | 0 条 |
| `crossfile_id_check.js` | 跨文件抓别的 QML 的 id（`mapPage.x` 之类）—— id 是文件级作用域，运行期 ReferenceError，只能靠宿主透传属性 | 0 条 |
| `int_prop_check.js` | **int 属性写了字面小数**，如 `font.pixelSize: 13.5`。加载期硬错误 `Invalid property assignment: int expected`，整棵组件树建不起来、app 启动即退；qmllint / qmlcachegen / ctest 三道都不报（2026-10-21 真机就是这么炸的）。只报值本身带小数的字面量：`2.0` 放过，`styles.fsXs`（real 绑定，Qt round-half-up：8.5→9）放过 | 0 条 |
| `bound_model_check.js` | 写了 `pragma ComponentBehavior: Bound` 的文件里，delegate 继续用视图注入的 `model` / `index` / `modelData`。Bound 语义会**移除**这三个上下文属性，必须改成 `required property`；不改就是真机整行静默画空（Main.qml 抽屉 13 行全空）。字符串字面量与注释都先换成等量空白再匹配，所以文案里出现 "model" 不误报，行号也不移位 | 0 条 |
| `singleton_import_check.js` | 用了 `CommonOptions` / `App` / `ImageColorExtractor` 却没写 `import OutdoorSurvival 1.0`。这三个是 `qmlRegisterSingletonInstance` 的**模块单例**，与 `xxxService` / `styles`（`setContextProperty` 上下文属性，不需要 import）不同来源，缺 import 就每次求值抛 `ReferenceError` 并静默画空——2026-10-21 全站图标 100% 方框、绳结难度梯整体变黑都是这一条。只匹配 `<单例>.` 成员访问，同名属性定义不误报。**新增模块单例时要同步改脚本里的 `SINGLETONS`** | 0 条 |
| `nav_reach_check.js` | 每页被谁 `navigateTo`，反查孤儿页。**有盲区**：URL 是算出来的那几页（HomePage / MePage / FieldGuidePage / TrackDetailPage）会误报"无人调用" | 人工核对 |
| `route_list_logic_check.js` | 把 `RouteListPage.rebuild()` 照搬到 JS，对真数据跑一遍，打印分组数/条数/月份分布，用来肉眼看筛选语义有没有跑偏 | 人工核对 |
| `travel_list_logic_check.js` | 同上，针对 `TravelListPage`。当前会报「编号撞车 5 对」—— plateCode 全局唯一只是好看，组内不重复才影响阅读；数据本轮冻结不动 | 人工核对 |

## 加新检查器的规矩

只准读文件、打印结论，**不写任何文件**；根目录一律走 `__dirname` 相对定位，
不要写 `D:/build_docker/...` 这种绝对路径（这条就是本目录从仓库外的
`_scratch_debug/` 搬进来的原因 —— 搬进来它们才进得了版本控制）。
