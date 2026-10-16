#!/bin/bash
# check_utf8.sh - 检查项目文本文件编码, 非 UTF-8 报错
#
# 用法:
#   bash scripts/check_utf8.sh            # 仅检查 (CI 用)
#   bash scripts/check_utf8.sh --fix      # 自动转 GBK → UTF-8 (无 BOM)
#
# 检查范围: src/ qml/ android/ assets/ CMakeLists.txt build_apk.sh verify_only.sh
# 排除: build/ dist/ third_party/ .gradle/

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# 收集要检查的文件 (限定文本类型, 排除二进制/构建产物)
mapfile -t FILES < <(find . -type f \
    \( -name "*.cpp" -o -name "*.h" -o -name "*.qml" -o -name "*.java" \
       -o -name "*.xml" -o -name "*.json" -o -name "*.gradle" \
       -o -name "*.properties" -o -name "*.txt" -o -name "*.md" \
       -o -name "*.sh" -o -name "CMakeLists.txt" \) \
    -not -path "./build/*" -not -path "./dist/*" \
    -not -path "./third_party/*" -not -path "./.git/*" \
    2>/dev/null | sort)

total=${#FILES[@]}
non_utf8=()
gbk_files=()
has_bom=()

for f in "${FILES[@]}"; do
    # 检查 BOM (UTF-8 BOM = 0xEF 0xBB 0xBF)
    if [ -s "$f" ]; then
        first3=$(head -c 3 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
        if [ "$first3" = "efbbbf" ]; then
            has_bom+=("$f")
        fi
    fi

    # 检查是否合法 UTF-8
    if ! iconv -f utf-8 -t utf-8 "$f" >/dev/null 2>&1; then
        non_utf8+=("$f")
        # 看是否 GBK
        if iconv -f gbk -t utf-8 "$f" >/dev/null 2>&1; then
            gbk_files+=("$f")
        fi
    fi
done

echo "检查范围: $total 个文件"
echo "BOM 文件: ${#has_bom[@]}"
echo "非 UTF-8 文件: ${#non_utf8[@]}"
echo "  其中 GBK: ${#gbk_files[@]}"

if [ ${#non_utf8[@]} -gt 0 ]; then
    echo
    echo "===== 非 UTF-8 文件清单 ====="
    for f in "${non_utf8[@]}"; do
        is_gbk=""
        for g in "${gbk_files[@]}"; do
            [ "$g" = "$f" ] && is_gbk=" (GBK)"
        done
        echo "  $f$is_gbk"
    done
fi

if [ ${#has_bom[@]} -gt 0 ]; then
    echo
    echo "===== 含 BOM 的文件 (建议用 sed 去 BOM) ====="
    for f in "${has_bom[@]}"; do
        echo "  $f"
    done
fi

# --fix 模式: 自动转 GBK → UTF-8
if [ "${1:-}" = "--fix" ]; then
    if [ ${#gbk_files[@]} -eq 0 ]; then
        echo
        echo "✅ 无 GBK 文件, 无需转码"
        exit 0
    fi
    echo
    echo "===== 自动转 GBK → UTF-8 ====="
    for f in "${gbk_files[@]}"; do
        # 备份
        cp "$f" "$f.bak.gbk"
        # 转码
        if iconv -f gbk -t utf-8 "$f.bak.gbk" > "$f"; then
            rm "$f.bak.gbk"
            echo "  ✅ $f"
        else
            echo "  ❌ 转码失败: $f"
            mv "$f.bak.gbk" "$f"  # 回滚
        fi
    done
    echo
    echo "✅ 转换完成. 重新跑: bash scripts/check_utf8.sh 验证"
fi

# 退出码
if [ ${#non_utf8[@]} -gt 0 ]; then
    exit 1
fi
exit 0
