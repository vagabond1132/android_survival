#!/bin/bash
# 真机二级页面回归驱动: 每步 = 点一个实测坐标 -> 等换帧 -> 截图 + 抓 logcat。
# 坐标一律来自 png_probe.js 实测或 uiautomator bounds, 不许拍脑袋。
# 用法: bash reg_tap_device.sh <outDir> <stepFile>
#   stepFile 每行: name|x|y   (name 里不能有空格)
set -u
export PATH="$PATH:/d/build_docker/android_sdk/platform-tools"
OUT=${1:?outDir}
STEPS=${2:?stepFile}
PKG=com.outdoor.survival
MIN_PNG=${MIN_PNG:-60000}
mkdir -p "$OUT"

snap() { timeout 30 adb exec-out screencap -p > "$1" 2>/dev/null < /dev/null; }

md5of() { [ -f "$1" ] && md5sum "$1" | cut -c1-12 || echo none; }

wait_change() {  # 轮询到画面稳定, 返回是否相对 prev 变了
    local prev=$1 dst=$2 base changed=0
    for _ in $(seq 1 6); do
        sleep 0.8
        snap "$dst"
        base=$(md5of "$dst")
        if [ "$base" != "$prev" ]; then changed=1; fi
        if [ "$changed" = 1 ]; then
            sleep 0.6
            snap "$dst"
            [ "$(md5of "$dst")" = "$base" ] && break
            prev=$base
        fi
    done
    echo $changed
}

PID=$(adb shell pidof -s $PKG | tr -d '\r')
if [ -z "$PID" ]; then echo "!! 进程不在, 先冷启动"; exit 1; fi
echo "pid=$PID"
adb logcat -c 2>/dev/null

snap "$OUT/00_start.png"
PREV=$(md5of "$OUT/00_start.png")

while IFS='|' read -r name x y <&3; do
    [ -z "$name" ] && continue
    case "$name" in \#*) continue;; esac
    adb shell input tap "$x" "$y" < /dev/null
    CH=$(wait_change "$PREV" "$OUT/$name.png")
    CUR=$(md5of "$OUT/$name.png")
    SZ=$(stat -c %s "$OUT/$name.png" 2>/dev/null || echo 0)
    printf '%-22s tap(%4s,%4s) 换帧=%s  md5=%s  bytes=%s\n' "$name" "$x" "$y" "$CH" "$CUR" "$SZ"
    PREV=$CUR
done 3< "$STEPS"

adb logcat -d --pid="$PID" > "$OUT/logcat_pass2.txt" 2>/dev/null
echo "--- WARN/CRIT/FATAL ---"
grep -cE '^[EWF]/' "$OUT/logcat_pass2.txt" 2>/dev/null || true
grep -E '^[EF]/' "$OUT/logcat_pass2.txt" | head -20
echo "--- 疑似黑屏 (<${MIN_PNG}B) ---"
find "$OUT" -name '*.png' -size -"${MIN_PNG}"c -printf '%f %s\n'
