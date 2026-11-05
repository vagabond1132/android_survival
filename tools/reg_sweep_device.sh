#!/usr/bin/env bash
# 真机走查 第一轮: 只跑坐标已核实的路径 (5 个根格 + 地图页工作台四格)。
# 二级入口的坐标要从截图量出来后在第二轮补, 不在这轮瞎点 —— 瞎点既可能改状态
# (开始录轨迹 / 开相机), 拍出来的图也不能当证据。
# 与 tools/reg_sweep.sh 的唯一区别: 真机读不到 /data/data/.../files/logs (无 root、
# release 不可 run-as), 判据只剩截图换帧 + 按 pid 过滤的 logcat。
set -u
export MSYS_NO_PATHCONV=1
PKG=com.outdoor.survival
OUT=/d/build_docker/app/tmp_reg/device006
mkdir -p "$OUT"
BAND_Y=2489          # (2556 - 48dp*2.8) + 134/2, 见 doc 12 §4.23
MIN_PNG=60000

shot() { adb exec-out screencap -p > "$1" 2>/dev/null; }
md5of() { md5sum "$1" 2>/dev/null | awk '{print $1}'; }

STALE=0; STALE_LIST=(); STEP=0
tap() { # x y name
  local x=$1 y=$2 name=$3 prev i=0 cur
  STEP=$((STEP+1))
  prev=$(md5of "$OUT/last.png")
  adb shell input tap "$x" "$y" >/dev/null 2>&1
  while [ "$i" -lt 12 ]; do
    sleep 1.2
    shot "$OUT/last.png"
    cur=$(md5of "$OUT/last.png")
    [ "$cur" != "$prev" ] && break
    i=$((i+1))
  done
  cp -f "$OUT/last.png" "$OUT/$name.png"
  if [ "$i" -ge 12 ]; then STALE=$((STALE+1)); STALE_LIST+=("$name"); fi
  printf '  %-20s %s (等帧 %s 轮)\n' "$name" "$( [ "$i" -ge 12 ] && echo 未换帧 || echo 换帧 )" "$i"
}

adb shell am force-stop "$PKG" >/dev/null 2>&1; sleep 1
adb logcat -c >/dev/null 2>&1
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null 2>&1
sleep 10
PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
[ -z "$PID" ] && { echo "!! 起不来, pidof 为空" >&2; exit 1; }
echo "pid=$PID"

# 五格 (x = 1224/10 的 1/3/5/7/9 倍)
tap 122  $BAND_Y r1_base
tap 367  $BAND_Y r2_res
tap 612  $BAND_Y r3_map
tap 857  $BAND_Y r4_sos_view   # 只看求助页布局; 拨号/SOS 长按/短信一律不代按
tap 1102 $BAND_Y r5_me
tap 122  $BAND_Y r6_base_again  # 回营地, 兼作"换页可逆"的证据

# 地图页工作台: 先进地图, 再点拖把看展开态
tap 612  $BAND_Y m1_map
adb shell uiautomator dump /sdcard/m.xml >/dev/null 2>&1
adb shell cat /sdcard/m.xml > "$OUT/map_dump.xml" 2>/dev/null

adb logcat -d --pid="$PID" > "$OUT/logcat_pass1.txt" 2>/dev/null

echo "=== 汇总 ==="
printf '步数 %s / 未换帧 %s:%s\n' "$STEP" "$STALE" " ${STALE_LIST[*]:-}"
for lvl in WARN CRIT FATAL; do
  printf '%-6s %s\n' "$lvl" "$(grep -cE "\[$lvl\]|[[:space:]]$lvl[[:space:]]" "$OUT/logcat_pass1.txt" 2>/dev/null)"
done
echo "OutdoorDiag 行数: $(grep -c OutdoorDiag "$OUT/logcat_pass1.txt" 2>/dev/null)"
SMALL=0
for f in "$OUT"/r?_*.png "$OUT"/m1_*.png; do
  [ -f "$f" ] || continue
  s=$(stat -c %s "$f" 2>/dev/null || echo 0)
  [ "$s" -lt "$MIN_PNG" ] && { echo "  疑似黑屏: $(basename "$f") ($s B)"; SMALL=$((SMALL+1)); }
done
echo "疑似黑屏 $SMALL 张"
