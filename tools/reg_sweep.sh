#!/usr/bin/env bash
# 全功能走查 (回归用), Windows 侧 Git Bash + adb 打 x86_64 模拟器。
#
# 判据不是"截图好看", 而是三条可机读的:
#   1) 走查期间 app 自己的落盘日志里 WARN/CRIT/FATAL 的**增量** (Logger 链路见 doc §4.13)
#   2) 每一步点击都要看到画面**换帧**; 5 个根格截出 5 种不同画面。
#      "没换帧"(swiftshader 吐陈旧帧) 和 "没切页"(真 bug) 是两回事, 分开报。
#   3) 每张截图的体积下限 —— 黑屏 PNG 压出来 ~22 KB, 真渲染的页面 100 KB+
#
# 用法:  bash tools/reg_sweep.sh <tag> ["x y" | "x y 名字" ...]
#        tag 例如 004_base / 005_base, 产物落 tmp_reg/<tag>/
#        后面的坐标是额外要点开的地方 (子页/抽屉条目/六项反馈路径),
#        带第三个字段就给这一屏起名, 产物是 <名字>.png; 不带则 extra_N.png
#
# ⚠️ 铁律 A: 绝不点拨号 / SOS 长按 / 短信发送。SOS 格只"进页面看一眼"就退回营地格。
# ⚠️ 铁律 B: **跑走查时容器里不能有编译**。本机 8 逻辑核, 容器一编译模拟器就饿死:
#    实测 `EGL_emulation app_time_stats: avg=2338ms` + 整屏黑 + 截图 22 KB 全同,
#    看起来像"App 白屏 bug", 其实是抢不到 CPU。判据 2/3 就是为拦这个而写的。
set -uo pipefail

TAG=${1:?用法: reg_sweep.sh <tag> ["x y"...]}
shift || true
EXTRA=("$@")   # 必须在下面任何 `set --` 之前存下来: 根格循环用 set -- 会覆盖位置参数
SERIAL=${SERIAL:-emulator-5554}
PKG=com.outdoor.survival
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/tmp_reg/$TAG"
MIN_PNG=${MIN_PNG:-40000}

ADB=(adb -s "$SERIAL")
mkdir -p "$OUT"

shot() { "${ADB[@]}" exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; }
sh()   { "${ADB[@]}" shell "$1" 2>/dev/null | tr -d '\r'; }

# 2026-11-02: 定长 sleep + 截图在模拟器上不可信 —— swiftshader 会连着几秒回同一张
#   陈旧帧, 于是"这一格没切页"和"画面没重绘"混成一回事 (scan2 把 7 格全判成没动,
#   scan3 换成"每步都确认换帧"才知道导航条其实是好的)。tap 改成: 记下点之前的帧,
#   轮询到帧变了才落盘; 12 秒没变就把最后一帧存下来并记一笔 STALE。
PREV_MD5=""
STALE=0
STEP=0
STALE_LIST=()
tap() {   # tap <x> <y> [名字]
  local cur name=${3:-_noname}
  STEP=$((STEP+1))
  cur=$("${ADB[@]}" exec-out screencap -p 2>/dev/null | md5sum | cut -c1-12)
  "${ADB[@]}" shell input tap "$1" "$2"
  local i=0
  while [ "$i" -lt 12 ]; do
    sleep 1
    local nxt
    nxt=$("${ADB[@]}" exec-out screencap -p 2>/dev/null | md5sum | cut -c1-12)
    if [ "$nxt" != "$cur" ]; then cur="$nxt"; break; fi
    i=$((i+1))
  done
  if [ "$i" -ge 12 ]; then
    STALE=$((STALE+1))
    STALE_LIST+=("$name")
  fi
  PREV_MD5="$cur"
  "${ADB[@]}" exec-out screencap -p > "$OUT/$name.png" 2>/dev/null
  printf '  %-16s %s (等帧 %ss)\n' "$name" "$( [ "$i" -ge 12 ] && echo 未换帧 || echo 换帧 )" "$i"
}

# 日志名按日期滚 (app_YYYYMMDD.log), 写死今天会让明天的走查静默拿到空文件
LOG=$(sh "ls -t /data/data/$PKG/files/logs/app_*.log 2>/dev/null | head -1")
[ -z "$LOG" ] && { echo "!! 设备上找不到落盘日志, Logger 链路可能又断了" >&2; exit 1; }

BEFORE=$(sh "wc -c < $LOG" | tr -d '[:space:]')
"${ADB[@]}" shell input keyevent KEYCODE_BACK >/dev/null 2>&1
"${ADB[@]}" shell am force-stop "$PKG"; sleep 1
"${ADB[@]}" shell am start -W -n "$PKG/.MainActivity" >/dev/null 2>&1
sleep 14   # App::initialize 在模拟器上要 ~17s, 别在初始化中途截图

# 5 个根格 (底栏 5 方位带, 中心 x = 108/324/540/756/972, y≈2210)
for pair in "base 108" "res 324" "map 540" "sos 756" "me 972"; do
  set -- $pair
  tap "$2" 2210 "band_$1"
done
tap 108 2210 "band_back"   # SOS 格只看不按, 立刻回营地格

i=0
for t in "${EXTRA[@]}"; do
  i=$((i+1))
  set -- $t
  [ "$#" -ge 2 ] || { echo "!! 额外坐标 '$t' 不是 'x y' 两个数, 跳过" >&2; continue; }
  # 第三个字段是给这一屏起的名字 ("x y name"), 没起就退回 extra_N —— 20 张
  # extra_N.png 事后根本认不出谁是紧急联系人页, 走查记录等于没留。
  tap "$1" "$2" "${3:-extra_$i}"
done

AFTER=$(sh "wc -c < $LOG" | tr -d '[:space:]')
"${ADB[@]}" exec-out "tail -c +$((BEFORE+1)) $LOG" > "$OUT/delta.log" 2>/dev/null
"${ADB[@]}" exec-out "cat $LOG" > "$OUT/app.log" 2>/dev/null

# ---- 判据 2/3 -------------------------------------------------------------
# 判据 2 改写 (2026-11-02): 原来"任意两张根格截图相同 → 本轮作废"是错的。
#   ① band_back 是**故意**回到营地格, 和 band_base 同图是正常结果;
#   ② swiftshader 会连着几秒吐同一张陈旧帧, 于是截图相同既可能是"没切页",
#      也可能只是"没重绘"—— 这两件事必须分开判, 分开判的办法就是 tap() 里
#      轮询换帧, 拿到 STALE 计数。只有"所有步都没换帧"才是整轮作废。
ROOTBANDS=""
for n in base res map sos me; do
  [ -f "$OUT/band_$n.png" ] && ROOTBANDS="$ROOTBANDS $OUT/band_$n.png"
done
DISTINCT=$(md5sum $ROOTBANDS 2>/dev/null | awk '{print $1}' | sort -u | wc -l)
SMALL=0
for f in "$OUT"/band_*.png; do
    [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -lt "$MIN_PNG" ] && SMALL=$((SMALL+1))
done

echo "=== $TAG ==="
echo "log: $BEFORE -> $AFTER bytes (delta $((AFTER-BEFORE)))"
# 两种格式都要数: diag handler 的 `[WARN] xxx` 与 Logger 自己的 `... WARN  xxx`
for lvl in WARN CRIT FATAL; do
  printf '%-6s %s\n' "$lvl" "$(grep -cE "\[$lvl\]|[[:space:]]$lvl[[:space:]]" "$OUT/delta.log" 2>/dev/null)"
done
printf '5 个根格截出 %s 种不同画面 (期望 5) / 疑似黑屏 %s (期望 0)\n' "$DISTINCT" "$SMALL"
if [ "$STALE" != "0" ]; then
  printf '未换帧 %s/%s 步:%s — 这几张图不能当证据, 需单独重拍\n' \
    "$STALE" "$STEP" " $(printf '%s ' "${STALE_LIST[@]}")"
fi

RC=0
[ "$STALE" = "$STEP" ] && [ "$STEP" != "0" ] && \
  { echo "!! $STEP 步点击没有一步换帧 → App 或模拟器没在跑, 本轮作废" >&2; RC=2; }
[ "$DISTINCT" = "1" ]  && \
  { echo "!! 5 个根格截图全同 → 画面没切页, 本轮作废" >&2; RC=2; }
[ "$SMALL" != "0" ] && { echo "!! 有根格截图 < ${MIN_PNG}B → 疑似黑屏/模拟器饿死, 本轮作废" >&2; RC=3; }
[ "$((AFTER-BEFORE))" -lt 1000 ] && { echo "!! 日志增量 < 1 KB → 走查期间 App 可能没在跑" >&2; RC=4; }
[ "$RC" = "0" ] && echo "→ 走查有效, 产物在 $OUT"
exit "$RC"
