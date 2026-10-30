#!/usr/bin/env python3
"""JNI 方法名/描述符存在性审计 —— 查"编译期不报错、真机才 NoSuchMethodError"的那类写法。

C++ 侧 `QJniObject::callObjectMethod(name, signature, ...)` 的方法名和签名描述符都是
**运行期**才解析的字符串: 写错不报编译错, 交叉编译也不报, 到真机上抛 NoSuchMethodError,
JNI 返回 null → 调用方判"失败"并静默降级。已经踩过两次:
  - 2026-10-19 `InputStream.readAll()` (Java 9 API, ART 的 AutoCloseInputStream 没实现)
    → 拍照检索整条链路拿不到字节, 见 AndroidPlatform.cpp:1035 那段复盘。
  - 2026-10-28 `ContentResolver.query(Uri, String[])` —— 这支重载**从来不存在**,
    android-34 只有 (Uri,String[],String,String[],String) / (…,CancellationSignal) /
    (Uri,String[],Bundle,CancellationSignal)。写两参 = #149 的 DISPLAY_NAME 兜底整条是死代码。
    同一次审计还查出 `PackageManager.resolveActivity(Intent)` 单参 (API 21 起移除) 与
    `WindowManager$LayoutParams.setScreenBrightness(F)` (那是 public 字段, 没有 setter)。

判据: android.jar 每个 class 的常量池里有 CONSTANT_Utf8 条目 (2 字节大端长度 + 内容),
方法名与描述符都以原样字符串躺在里面。所以按「长度定界的精确匹配」判定"这个字符串在不在",
不做前缀匹配 —— 否则 5 参那支会被当成 2 参的命中放过。本脚本只判"查无", 不判
"这个方法名与该描述符是否属于同一个类/配对正确": 配对要人看 (javap 那个类)。

用法 (只在构建容器里跑, 需要 SDK 的 android.jar):
    MSYS_NO_PATHCONV=1 docker exec -i outdoor-survival-builder \\
        python3 /project/scripts/jni_descriptor_audit.py
    # 可覆盖: python3 .../jni_descriptor_audit.py <src_dir> <android.jar>
退出码 0 = 全部命中; 1 = 有存疑项 (逐条打印 文件:行 / 方法名 / 描述符 / 缺的是名还是签名)。
"""
import os
import re
import struct
import sys
import zipfile

# ("name", "desc"  或  ("a/b/C", "name", "desc" —— 描述符可能被拆成相邻的多个字面量跨行拼接,
# 所以 method 之后再吃掉一整串连续字面量。
CALL_RE = re.compile(
    r'\(\s*(?:(?P<cls>"[^"]*")\s*,\s*)?'
    r'"(?P<method>[A-Za-z_][A-Za-z0-9_]*)"\s*,\s*'
    r'(?P<desc>(?:"[^"]*"\s*)+)',
)


def join_literals(text, start):
    out = []
    i = start
    while i < len(text):
        while i < len(text) and text[i] in " \t\r\n":
            i += 1
        if i >= len(text) or text[i] != '"':
            break
        j = text.index('"', i + 1)
        out.append(text[i + 1:j])
        i = j + 1
    return "".join(out)


def collect(src_dir):
    """返回 [(path, line, method, descriptor)] —— 只收形如 (…)… 的 JNI 签名串。"""
    sites = []
    for root, _, files in os.walk(src_dir):
        for fn in sorted(files):
            if not fn.endswith((".cpp", ".h", ".inl")):
                continue
            path = os.path.join(root, fn)
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            for m in CALL_RE.finditer(text):
                desc = join_literals(text, m.start("desc"))
                if not (desc.startswith("(") and ")" in desc):
                    continue
                sites.append((path, text[:m.start()].count("\n") + 1,
                              m.group("method"), desc))
    return sites


def pool_strings(jar):
    """android.jar 里所有 .class 的常量池 UTF8 条目 (精确字符串集合)。"""
    found = set()
    with zipfile.ZipFile(jar) as z:
        for name in z.namelist():
            if not name.endswith(".class"):
                continue
            blob = z.read(name)
            i = 8                                # magic(4) + minor(2) + major(2)
            count = struct.unpack_from(">H", blob, i)[0]
            i += 2
            n = 1
            while n < count:                      # 索引 0 不用, 有效条目是 1..count-1
                tag = blob[i]
                i += 1
                if tag == 0:                      # long/double 之后那个空槽位
                    n += 2
                    continue
                if tag == 1:                      # CONSTANT_Utf8
                    ln = struct.unpack_from(">H", blob, i)[0]
                    i += 2
                    found.add(blob[i:i + ln].decode("utf-8", "replace"))
                    i += ln
                elif tag in (7, 8, 16, 19, 20):    # Class/String/MethodType/Module/Package
                    i += 2
                elif tag == 15:                   # MethodHandle
                    i += 3
                elif tag in (3, 4, 9, 10, 11, 12, 17, 18):   # 定长 4 字节的那些
                    i += 4
                elif tag in (5, 6):               # Long/Double: 占两个索引
                    i += 8
                    n += 1
                else:
                    break                         # 认不出来就放弃这个 class, 别乱走
                n += 1
    return found


def find_jar():
    home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not home:
        return None
    for api in sorted(os.listdir(os.path.join(home, "platforms")), reverse=True) \
            if os.path.isdir(os.path.join(home, "platforms")) else []:
        cand = os.path.join(home, "platforms", api, "android.jar")
        if os.path.exists(cand):
            return cand
    return None


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(repo, "src")
    jar = sys.argv[2] if len(sys.argv) > 2 else find_jar()
    if not jar:
        print("找不到 android.jar (不在容器里? 设 ANDROID_HOME 或直接传第二个参数)")
        return 2
    sites = collect(src_dir)
    pool = pool_strings(jar)
    bad = [(p, l, m, d, m in pool, d in pool)
           for (p, l, m, d) in sites if not (m in pool and d in pool)]
    print("审计 %d 处 JNI 调用点 (jar=%s, 常量池 %d 条)" % (len(sites), jar, len(pool)))
    if not bad:
        print("RESULT: 0 处方法名/描述符在 android.jar 里查无")
        return 0
    print("!! %d 处存疑 (方法名和描述符都要能单独查到; 配对是否正确仍需 javap 那个类人工核):"
          % len(bad))
    for p, l, m, d, ok_m, ok_d in bad:
        print("  %s:%d  %s%s  [%s]" % (
            p, l, m, d, " + ".join(
                x for x, ok in (("方法名查无", ok_m), ("描述符查无", ok_d)) if not ok)))
    return 1


if __name__ == "__main__":
    sys.exit(main())
