#!/usr/bin/env python3
"""从 APK 的主 so 里把 Qt rcc 资源解压出来，直接查 QML 源码文本。"""
import sys, zipfile, zlib

APK = sys.argv[1] if len(sys.argv) > 1 else \
    '/project/dist/OutdoorSurvival-v0.0.5-release-arm64-v8a.apk'
NEEDLES = [
    ('新写法 parent && parent.height > 0', b'parent && parent.height > 0 ? parent.height : 800'),
    ('旧写法 Math.max(parent…800, 800)', b'Math.max(parent ? parent.height : 800, 800)'),
    ('新注释「不兜 800 的下限」', '不兜 800 的下限'.encode()),
    ('clip: true', b'clip: true'),
    ('「夜晚配色」(MePage 末段)', '夜晚配色'.encode()),
    ('bottomClearance', b'bottomClearance'),
    ('「显示」段头', '显示'.encode()),
]

z = zipfile.ZipFile(APK)
names = [n for n in z.namelist() if n.startswith('lib/arm64-v8a/') and 'OutdoorSurvival' in n]
blob = z.read(names[0])
print('so = %s  %d B' % (names[0], len(blob)))

plain = {lbl: blob.count(pat) for lbl, pat in NEEDLES}
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

hits = {lbl: 0 for lbl, _ in NEEDLES}
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
    for lbl, pat in NEEDLES:
        hits[lbl] += data.count(pat)
print('成功解压 %d 块\n' % ok)
for lbl, _ in NEEDLES:
    print('  %-40s 明文 %d + 解压 %d = %d' % (lbl, plain[lbl], hits[lbl], plain[lbl] + hits[lbl]))
