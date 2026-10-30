#!/usr/bin/env bash
# tools/qml_lint.sh — 让 qmllint 能把组件类型解析出来的门禁脚本 (2026-10-20 #61)
#
# 为什么要单独写这个脚本:
#   直接 `qmllint -I qml <文件>` 时, OutdoorSurvival 这个 module 里的类型一个都解析不了
#   —— 类型注册表 (qmldir + qmltypes) 是 qt_add_qml_module 在**构建期**生成的, 源码树里
#   没有. 于是 Styles / SectionTitle / ListRow / IconLabel 全部报 "was not found",
#   每个文件几百条噪声; 真正要紧的错误 (例如给 OutlineButton 写了它没有的 iconName,
#   或 TapHandler 无参信号写了带参 handler) 就被完全盖住.
#   这里用当前源码临时拼一个模块目录: 每个 .qml 按"文件名 = 类型名"写进 qmldir,
#   C++ 侧类型的 qmltypes 从最近一次构建产物里取. 不改动仓库里任何 QML.
#
# 用法 (容器内; 2026-10-28 实测 outdoor-survival-builder 与 unit-test 服务都能跑,
#   前者告警多 130 行是因为它的桌面 Qt 缺 QtLocation/QtPositioning, 两侧 ^Error 都是 0):
#   docker exec outdoor-survival-builder bash -c "cd /project && bash tools/qml_lint.sh"
#   bash tools/qml_lint.sh qml/pages/MapPage.qml qml/components/MapOverlay/*.qml
#   不给参数 = 全量 qml/
#
# 已知解析不了的: CommonOptions 和 xxxService 都是 setContextProperty 注入的上下文属性,
#   qmllint 拿不到它们的类型, 所以对它们的属性名/方法名拼错一概不报. 那部分靠
#   tools/qml_checks/ 下的 JS 检查脚本 (清单见同目录 README 与 doc/08-索引与概念/全代码索引.md §18.1)
#   + 真机 stage0.log. 那 15 个脚本要 node, 两个容器里都没有, 只能在 Windows 主机用 Qoder 自带
#   的 Electron 当 node 跑 (§18.1 给了命令).
set -uo pipefail

QMLLINT=${QMLLINT:-/opt/Qt/6.7.2/gcc_64/bin/qmllint}
MODDIR=${MODDIR:-/tmp/osw-lintmod/OutdoorSurvival}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

rm -rf "$(dirname "$MODDIR")"
mkdir -p "$MODDIR"
cp -r "$ROOT/qml" "$MODDIR/qml"

# C++ 侧类型的 qmltypes 不参与: 本项目所有服务与 CommonOptions 都是 setContextProperty
# 注入的上下文属性, 构建产物里那份 OutdoorSurvival.qmltypes 内容就是空的 "Module {}",
# 引用它只会让 qmldir 解析报 "Expected token numeric literal".
{
    echo "module OutdoorSurvival"
    (cd "$MODDIR/qml" && find . -name '*.qml' | sed 's|^\./||' | while read -r rel; do
        echo "$(basename "$rel" .qml) 1.0 qml/$rel"
    done)
} > "$MODDIR/qmldir"

cd "$ROOT"
FILES=${*:-$(find qml -name '*.qml')}

# 只留人话: 去掉模块解析噪声与源码回显行
# 注意 -I 要给"模块的父目录" (里面有个叫 OutdoorSurvival 的子目录); 给到模块目录自身
# 反而一个类型都解析不出来 —— 第一版就栽在这里.
"$QMLLINT" -I "$(dirname "$MODDIR")" $FILES 2>&1 \
    | grep -vE "Ambiguous type|Are your import paths|Failed to import|^ *\^+$|^---$|^ *$" \
    | grep -E "^(Error|Warning|Info)"
