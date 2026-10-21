# qml_checks —— qmllint 管不到的那一半门禁

`tools/qml_lint.sh` 跑的是 qmllint，但 qmllint **解析不了 `CommonOptions` 和各个
`xxxService`**（它们是 `main.cpp` 用 `setContextProperty` 注入的上下文属性），
拼错属性名它一声不吭。这一半由本目录的 JS 检查器兜着。

- 默认扫描根目录 = 本文件所在目录的 `../../qml`（数据类检查器是 `../../assets/data`），
  所以从仓库任何位置都能跑；也可以传第一个参数指定别的根目录。
- 判读：`pragma/layout_prop/mono_cjk/crossfile_id` 这 4 个是 **pass/fail 门禁，期望 0 条**；
  后 3 个是**打印诊断**，不给出退出码结论。
- 逐条判读规则与对账表见 `doc/08-索引与概念/全代码索引.md` §18.1。

## 怎么跑

Windows 主机上没有 node，用 Qoder 自带的 Electron 当 node：

```bash
cd /d/build_docker/app/tools/qml_checks
export ELECTRON_RUN_AS_NODE=1
"/c/Users/Administrator/AppData/Local/Programs/Qoder/Qoder.exe" pragma_check.js
```

`ut` 容器里**没有 node**（`which node` 空），所以这 7 个检查器只在 Windows 主机跑。
搬进仓库是为了进版本控制、并且根目录不再写死绝对路径；哪天容器装了 node，
直接 `node tools/qml_checks/pragma_check.js` 即可（仓库挂载在 `/project`）。

## 清单

| 脚本 | 守什么 | 期望 |
|---|---|---|
| `pragma_check.js` | delegate 里引用外层 id 却没写 `pragma ComponentBehavior: Bound` —— qmlcachegen 静态编译下真机静默 ReferenceError | 0 条 |
| `layout_prop_check.js` | 布局子项上写 `width:/height:/anchors:`，或写 `Layout.visible`（Qt6.7 的 `QQuickLayoutAttached` 没这个属性，是加载期硬错误，整页白屏） | 0 条 |
| `mono_cjk_check.js` | `styles.monoFont` / `Material Icons` 字形对象里混进汉字（该字体没有 CJK 字形，回退失败出方框） | 0 条 |
| `crossfile_id_check.js` | 跨文件抓别的 QML 的 id（`mapPage.x` 之类）—— id 是文件级作用域，运行期 ReferenceError，只能靠宿主透传属性 | 0 条 |
| `nav_reach_check.js` | 每页被谁 `navigateTo`，反查孤儿页。**有盲区**：URL 是算出来的那几页（HomePage / MePage / FieldGuidePage / TrackDetailPage）会误报"无人调用" | 人工核对 |
| `route_list_logic_check.js` | 把 `RouteListPage.rebuild()` 照搬到 JS，对真数据跑一遍，打印分组数/条数/月份分布，用来肉眼看筛选语义有没有跑偏 | 人工核对 |
| `travel_list_logic_check.js` | 同上，针对 `TravelListPage`。当前会报「编号撞车 5 对」—— plateCode 全局唯一只是好看，组内不重复才影响阅读；数据本轮冻结不动 | 人工核对 |

## 加新检查器的规矩

只准读文件、打印结论，**不写任何文件**；根目录一律走 `__dirname` 相对定位，
不要写 `D:/build_docker/...` 这种绝对路径（这条就是本目录从仓库外的
`_scratch_debug/` 搬进来的原因 —— 搬进来它们才进得了版本控制）。
