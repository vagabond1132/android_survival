#!/usr/bin/env python3
"""从 APK 的主 so 里把 Qt rcc 资源解压出来，直接查 QML 源码文本。

用法（判据口径见 doc/07-部署与发布/Docker构建APK手册.md §12.7）：
    python3 tools/apk_rcc_probe.py <apk> \\
        --must-hit='新写法 comboModel.length !== undefined' \\
        --must-be-zero='旧写法 Array.isArray(comboModel)'

不带参数时跑 0.0.5 那轮的内置清单（只打印，不置退出码）。
带 --must-hit / --must-be-zero 时逐条判定，**有任何一条判错就 exit 1**，可直接当出包门禁串。
三条已知限制（都是真撞过的）：
  ① 注释里抄了旧写法会误报 —— 本工具按行去掉 `//` 之后再计数；去注释后仍非 0，才是"旧代码还在包里"。
     新串同样按去注释判，否则一句提到新写法的注释就能造假绿。
  ② 新旧两个 needle 必须互不包含（`color: X` 含在 `border.color: X` 里），对照要挑只出现一次的那一行。
  ③ 每次跑都至少要带一条 `--must-hit` 对照串（如 `clip: true`）：解压一条都没解出来时，
     所有"期望 0"会集体假绿。本工具此时直接 exit 2。
"""
import sys, zipfile, zlib

DEFAULT_APK = '/project/dist/OutdoorSurvival-v0.0.5-release-arm64-v8a.apk'

# 内置清单 = 0.0.5 那轮的历史现场，只打印不判定
NEEDLES = [
    ('新写法 parent && parent.height > 0', b'parent && parent.height > 0 ? parent.height : 800'),
    ('旧写法 Math.max(parent…800, 800)', b'Math.max(parent ? parent.height : 800, 800)'),
    ('新注释「不兜 800 的下限」', '不兜 800 的下限'.encode()),
    ('clip: true', b'clip: true'),
    ('「夜晚配色」(MePage 末段)', '夜晚配色'.encode()),
    ('bottomClearance', b'bottomClearance'),
    ('「显示」段头', '显示'.encode()),
]

APK = DEFAULT_APK
WANT = []          # [(label, pattern_bytes, 期望)]  期望: '>0' 或 '0'
argv = sys.argv[1:]
i = 0
while i < len(argv):
    a = argv[i]
    if a in ('--must-hit', '--must-be-zero'):
        i += 1
        if i >= len(argv):
            sys.exit('%s 后面要跟 标签=文本' % a)
        label, sep, text = argv[i].partition('=')
        if not sep or not text:
            sys.exit('%s 需要 标签=文本 形式，收到 %r' % (a, argv[i]))
        WANT.append((label, text.encode(), '>0' if a == '--must-hit' else '0'))
    else:
        APK = a
    i += 1

CASES = WANT if WANT else [(lbl, pat, None) for lbl, pat in NEEDLES]

z = zipfile.ZipFile(APK)
names = [n for n in z.namelist() if n.endswith('.so') and 'OutdoorSurvival' in n and n.startswith('lib/')]
pref = [n for n in names if n.startswith('lib/arm64-v8a/')]      # 交付口径只有 arm64
if not pref:
    pref = names                                                  # 反查 x86_64 包时也能用
if len(pref) != 1:
    sys.exit('主 so 不唯一或没找到: %s' % (names,))
blob = z.read(pref[0])
print('APK = %s' % APK)
print('so = %s  %d B' % (pref[0], len(blob)))


def count_outside_comments(buf, pat):
    """数 buf 里 pat 的命中次数，但跳过落在 `//` 注释里的。
    做法：每次命中回溯到本行行首，看行首到命中点之间有没有 `//`。
    对**明文区和解压流一视同仁** —— 同一份源码在包里两处都有，本轮实测
    `Math.max(styles.pageHeadH…)` 只在明文区命中 1 次、`weatherSourceReal` 只在解压流命中 1 次，
    只查一边必漏其中一边。"""
    n = 0
    i = 0
    while True:
        i = buf.find(pat, i)
        if i < 0:
            return n
        start = buf.rfind(b'\n', 0, i) + 1
        if buf.find(b'//', start, i) < 0:
            n += 1
        i += len(pat)


plain = {lbl: blob.count(pat) for lbl, pat, _ in CASES}
plain_nc = {lbl: count_outside_comments(blob, pat) for lbl, pat, _ in CASES}
print('明文命中: %s' % ({k: v for k, v in plain.items() if v} or '无（说明 rcc 是压缩的）'))

# 找压缩块起点（zstd 魔数 / zlib 首两字节），用 find 跳跃而不是逐字节
offs = set()
i = 0
while True:
    i = blob.find(b'\x28\xb5\x2f\xfd', i)
    if i < 0:
        break
    offs.add(i); i += 1
for b0, b1 in ((0x78, 0x01), (0x78, 0x9C), (0x78, 0xDA)):
    pat = bytes([b0, b1])
    i = 0
    while True:
        i = blob.find(pat, i)
        if i < 0:
            break
        offs.add(i); i += 1
print('候选压缩块 %d 个' % len(offs))

try:
    import zstandard as zs
    dctx = zs.ZstdDecompressor()
except Exception:
    dctx = None
    print('（无 zstandard 模块，只试 zlib）')

hits = {lbl: 0 for lbl, _, _ in CASES}
hits_nc = {lbl: 0 for lbl, _, _ in CASES}
ok = 0
for off in sorted(offs):
    data = b''
    try:
        data = zlib.decompressobj().decompress(blob[off:], 128 * 1024 * 1024)
    except Exception:
        data = b''
    if not data and dctx is not None:
        try:
            data = dctx.decompress(blob[off:], max_output_size=128 * 1024 * 1024)
        except Exception:
            data = b''
    if not data:
        continue
    ok += 1
    # 给改动写说明时常常把旧写法原样抄进注释（本轮 FilterRow.qml:79 就是），
    # 所以除裸计数外，再去一次注释各算一份。
    for lbl, pat, _ in CASES:
        hits[lbl] += data.count(pat)
        hits_nc[lbl] += count_outside_comments(data, pat)
print('成功解压 %d 块\n' % ok)

raw = {lbl: plain[lbl] + hits[lbl] for lbl, _, _ in CASES}
nc = {lbl: plain_nc[lbl] + hits_nc[lbl] for lbl, _, _ in CASES}

bad = 0
for lbl, pat, want in CASES:
    if want is None:
        print('  %-46s 明文 %d + 解压 %d = %d（去注释 %d）'
              % (lbl, plain[lbl], hits[lbl], raw[lbl], nc[lbl]))
        continue
    n = nc[lbl]
    good = (n > 0) if want == '>0' else (n == 0)
    if not good:
        bad += 1
    note = ''
    if raw[lbl] != n:
        note = '（含注释的裸计数是 %d，按"去注释"判）' % raw[lbl]
    print('  %s %-46s 去注释(明文+解压) %d = %-3d 期望 %s%s'
          % ('OK  ' if good else 'FAIL', lbl, n, n, want, note))

if WANT:
    if not any(w == '>0' for _, _, w in WANT):
        print('!! 本次没带任何 --must-hit 对照串 —— 解压要是一条都没解出来，所有"期望 0"都会假绿。判据不成立。')
        sys.exit(2)
    print('\n=== 包侧反查 %s（判错 %d 条）===' % ('PASS' if bad == 0 else 'FAIL', bad))
    if bad:
        print('期望 0 的判据已按行去掉 `//` 注释；若仍非 0，说明旧写法真的还在这个包里。')
    sys.exit(1 if bad else 0)
