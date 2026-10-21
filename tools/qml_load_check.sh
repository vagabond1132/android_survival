#!/usr/bin/env bash
# tools/qml_load_check.sh —— 不打 APK、不进真机, 就把 Main.qml 整棵组件树**真加载一遍**.
#
# 为什么需要它 (2026-10-21 真机启动即退的复盘):
#   qml_lint.sh 全绿 + qmlcachegen 全绿 + ctest 24/24, 结果装上手机 rootObjects 是空的,
#   整个 app 起不来. 漏掉的是这一类:
#       PositionReadout.qml:128  font.pixelSize: 13.5
#   `pixelSize` 是 int, **字面小数**在加载期是硬错误 ("Invalid property assignment:
#   int expected"), 但:
#     - qmllint 不报 —— 它按 qml_lint.sh 现拼的假 qmldir 解析, 且不做字面量类型收窄;
#     - qmlcachegen 不报 —— 它只保证能编译成 C++, 类型收窄发生在运行期写属性时;
#     - ctest 不报 —— 单测只测 C++ service, 一个 QML 文件都不 load.
#   只有真的把组件树实例化一次才会炸出来. 这里用桌面 gcc_64 的 qml + offscreen 平台
#   在容器里跑, 一次几秒钟, 不用等 28 分钟的 APK.
#
# 用法 (在 ut 容器内, 仓库挂在 /project):
#   bash tools/qml_load_check.sh            # 退出码 0 = 组件树能加载; 1 = 有致命错误
#   VERBOSE=1 bash tools/qml_load_check.sh  # 连非致命的 ReferenceError 一起打出来
#
# 噪声与判据 (重要, 别误读):
#   App / CommonOptions / xxxService 全是 main.cpp 里 setContextProperty + 单例注入的
#   **上下文属性**, 裸 qml 二进制没有它们, 所以一定会刷一堆
#       ReferenceError: CommonOptions is not defined
#       QML Connections: Detected function "onDataChanged" ... no signal of the target
#   后一条尤其容易误判成 bug —— target 是 undefined, 所以扫不到信号, 不代表信号不存在
#   (mapService.dataChanged / emergencyService.locationUpdated 实测都在).
#   因此本脚本只对 FATAL_RE 里的模式判失败, 其余一律当噪声.
#
# 已知盖不住的: 需要真实 C++ 后端才能暴露的问题 (属性类型收窄之外的 JS 逻辑、
#   布局尺寸、图片/字体加载、传感器), 仍然只能靠真机 + stage0.log.
set -uo pipefail

QML_BIN=${QML_BIN:-/opt/Qt/6.7.2/gcc_64/bin/qml}
ROOT=${ROOT:-/project}
MODDIR=${MODDIR:-/tmp/osw-loadcheck}

[ -x "$QML_BIN" ] || { echo "找不到 $QML_BIN (ut 容器里的桌面 Qt)"; exit 2; }

# 裸 qml 只认 <importPath>/<ModuleName>/qmldir 这层目录结构, 所以要把整棵 qml/
# 摆成 OutdoorSurvival/ 再写一份"文件名=类型名"的 qmldir. 只动 /tmp, 不碰仓库.
rm -rf "$MODDIR"
mkdir -p "$MODDIR/OutdoorSurvival"
cp -r "$ROOT/qml" "$MODDIR/OutdoorSurvival/qml"
( cd "$MODDIR/OutdoorSurvival" && {
    echo "module OutdoorSurvival"
    echo "Main 1.0 qml/Main.qml"
    find qml -mindepth 1 -name '*.qml' | while read -r f; do
        n=$(basename "$f" .qml)
        [ "$n" = "Main" ] && continue
        echo "$n 1.0 $f"
    done
  } > qmldir )

# 加载期致命错误: 组件树根本没建起来. 只要命中任意一条, 真机就是白屏/秒退.
FATAL_RE='Invalid property assignment|Type [A-Za-z].* unavailable|was not found|is not installed|failed to load component|Cannot assign|Cannot change after use'

run_qml() {  # $1 = 相对 $MODDIR 的 .qml 路径
    # 20s 上限: Main.qml 是 ApplicationWindow, 加载成功后会一直待在事件循环里,
    # 只能靠 timeout 收 (页探针自己有 Qt.exit, 秒级就回).
    (cd "$MODDIR" && QT_QPA_PLATFORM=offscreen timeout -s KILL 20 "$QML_BIN" \
        -I "$MODDIR" "$1" 2>&1) 2>/dev/null
}

OUT=$(run_qml OutdoorSurvival/qml/Main.qml)
[ -z "$OUT" ] && { echo "⚠️  Main.qml 探针没有任何输出 —— 可能 timeout 或进程崩了, 不等于通过"; exit 1; }
[ -n "${VERBOSE:-}" ] && printf '%s\n' "$OUT"

# 只跑 Main.qml 覆盖不到多少东西: Main 里真正被立刻实例化的只有 HomePage,
# 其余 23 个页都是 navBus.navigateTo(名字) 走 Loader **按需**建的 —— 那些页里的
# 加载期硬错误 (PositionReadout 那一类) 只有导航到该页才会炸.
# 所以给每个页生成一个探针. 页全部是 Page (实测 25/25, 没有 ApplicationWindow),
# 可以当子对象塞进 Item; 那个 Timer 是为了跑完就退 —— qml 二进制没有 --exit 选项,
# 不主动 Qt.exit 的话成功加载的页会一直待在事件循环里, 只能等 timeout, 25 个页就是
# 25 分钟. 用 Timer 而不是页上的 Component.onCompleted, 是为了不覆盖页自己的
# onCompleted (它照样会跑, 里面的初始化异常也算数).
FAILS=""
for f in "$ROOT"/qml/pages/*.qml; do
    n=$(basename "$f" .qml)
    printf 'import QtQuick\nimport OutdoorSurvival\nItem {\n    width: 400\n    height: 800\n    Timer { interval: 400; running: true; onTriggered: Qt.exit(0) }\n    %s { anchors.fill: parent }\n}\n' "$n" \
        > "$MODDIR/OutdoorSurvival/probe_$n.qml"
    PHITS=$(run_qml "OutdoorSurvival/probe_$n.qml" | grep -E "$FATAL_RE" || true)
    [ -n "$PHITS" ] && FAILS="${FAILS}${n}
${PHITS}
"
done
PROBE_N=$(ls "$ROOT"/qml/pages/*.qml | wc -l)

HITS=$(printf '%s\n' "$OUT" | grep -E "$FATAL_RE" || true)
if [ -n "$HITS" ]; then
    FAILS="Main.qml
${HITS}
${FAILS}"
fi

if [ -n "$FAILS" ]; then
    echo "❌ QML 加载失败 (致命, 真机会白屏或秒退):"
    printf '%s\n' "$FAILS"
    exit 1
fi

echo "✅ 组件树加载通过: Main.qml + ${PROBE_N} 个页全部可实例化"
echo "   非致命噪声 $(printf '%s\n' "$OUT" | grep -c 'ReferenceError' || true) 条 (上下文属性未注入, 属预期)"
exit 0
