"""
荒野手册 (OutdoorSurvival) 图标生成器 v3
- ic_launcher.png / ic_launcher_round.png: 完整图 (天空+山+帐篷+落日)
  → 旧设备 (API < 26) 使用
- ic_launcher_foreground.png: 仅中央 66% 区域的内容 (透明背景)
  → Android 8.0+ adaptive icon 用, 会被系统按 66% 居中裁剪
- ic_launcher_background color: 改为深蓝紫 (与 logo 天空呼应)
"""
import zlib
import struct
import os

# 颜色定义
SKY_TOP   = (28, 51, 89, 255)
SKY_MID   = (242, 142, 43, 255)
SUN       = (255, 220, 130, 255)
SUN_GLOW  = (255, 200, 120, 255)
MOUNTAIN_FAR  = (74, 95, 115, 255)
MOUNTAIN_NEAR = (38, 64, 51, 255)
TENT      = (228, 220, 195, 255)
TENT_DOOR = (52, 41, 30, 255)

# adaptive icon 背景色: 深蓝紫 (与天空顶部一致)
ADAPTIVE_BG = (28, 51, 89, 255)


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


def gen_full_pixels(size):
    """完整图标: 天空+山+太阳+帐篷, 方形满版"""
    w = h = size
    px = [[(0, 0, 0, 255) for _ in range(w)] for _ in range(h)]

    # 1. 天空渐变
    for y in range(h):
        t = y / h
        if t < 0.55:
            color = lerp(SKY_TOP, SKY_MID, t / 0.55)
        else:
            color = lerp(SKY_MID, MOUNTAIN_FAR, (t - 0.55) / 0.25)
        for x in range(w):
            px[y][x] = color

    # 2. 太阳
    sun_cx, sun_cy = w * 0.70, h * 0.30
    sun_r = w * 0.13
    glow_r = sun_r * 1.6
    for y in range(h):
        for x in range(w):
            dx, dy = x - sun_cx, y - sun_cy
            d2 = dx * dx + dy * dy
            r2 = sun_r * sun_r
            g2 = glow_r * glow_r
            if d2 < r2:
                px[y][x] = SUN
            elif d2 < g2:
                t = 1 - (d2 - r2) / (g2 - r2)
                px[y][x] = lerp(px[y][x], SUN_GLOW, t * 0.5)

    # 3. 远山
    far_peaks = [
        (0.0, 0.62), (0.15, 0.50), (0.30, 0.58), (0.45, 0.45),
        (0.60, 0.55), (0.75, 0.48), (0.90, 0.60), (1.0, 0.62),
    ]
    for x in range(w):
        xf = x / w
        for i in range(len(far_peaks) - 1):
            x0f, y0f = far_peaks[i]
            x1f, y1f = far_peaks[i + 1]
            if x0f <= xf <= x1f:
                t = (xf - x0f) / (x1f - x0f)
                peak_y = (y0f + (y1f - y0f) * t) * h
                for y in range(int(peak_y), h):
                    px[y][x] = MOUNTAIN_FAR
                break

    # 4. 近山
    near_peaks = [
        (0.0, 0.72), (0.20, 0.52), (0.42, 0.62), (0.58, 0.48),
        (0.78, 0.60), (1.0, 0.70),
    ]
    for x in range(w):
        xf = x / w
        for i in range(len(near_peaks) - 1):
            x0f, y0f = near_peaks[i]
            x1f, y1f = near_peaks[i + 1]
            if x0f <= xf <= x1f:
                t = (xf - x0f) / (x1f - x0f)
                peak_y = (y0f + (y1f - y0f) * t) * h
                for y in range(int(peak_y), h):
                    px[y][x] = MOUNTAIN_NEAR
                break

    # 5. 帐篷
    tent_cx = w * 0.30
    tent_top_y = h * 0.70
    tent_base_y = h * 0.86
    tent_half_w = w * 0.12
    for y in range(int(tent_top_y), int(tent_base_y)):
        rel = (tent_base_y - y) / (tent_base_y - tent_top_y)
        half = tent_half_w * rel
        for x in range(int(tent_cx - half), int(tent_cx + half)):
            if 0 <= x < w:
                px[y][x] = TENT
        if rel < 0.5:
            rel2 = rel / 0.5
            door_half = tent_half_w * 0.3 * rel2
            for x in range(int(tent_cx - door_half), int(tent_cx + door_half)):
                if 0 <= x < w:
                    px[y][x] = TENT_DOOR

    return px


def gen_foreground_pixels(size):
    """
    Adaptive icon foreground: 透明背景 + 中央 66% 区域的山+帐篷+太阳
    Android 系统会按 66% 居中裁剪 (mask), 周边透明区域用于动效 (视差/脉冲)

    我们把 logo 绘制在中心 66% 区域, 周边全透明 (alpha=0)
    """
    w = h = size
    # 全部透明
    px = [[(0, 0, 0, 0) for _ in range(w)] for _ in range(h)]

    # 在 66% 中心区域内绘制, 坐标按 (1.0 = 66% 区域边长)
    # 实际像素 = center + (rel - 0.5) * 0.66 * size
    cx = w / 2
    cy = h / 2
    s = w * 0.66  # 66% 区域大小

    def to_px(rel_x, rel_y):
        """rel in [0,1], 映射到中心 66% 区域"""
        return cx + (rel_x - 0.5) * s, cy + (rel_y - 0.5) * s

    # 1. 太阳 (右上, 半径小一些)
    sun_cx_r, sun_cy_r = 0.70, 0.30
    sun_r_r = 0.13
    spx_x, spx_y = to_px(sun_cx_r, sun_cy_r)
    sun_r_px = sun_r_r * s
    glow_r_px = sun_r_px * 1.6
    for y in range(h):
        for x in range(w):
            dx, dy = x - spx_x, y - spx_y
            d2 = dx * dx + dy * dy
            r2 = sun_r_px * sun_r_px
            g2 = glow_r_px * glow_r_px
            if d2 < r2:
                px[y][x] = SUN
            elif d2 < g2:
                t = 1 - (d2 - r2) / (g2 - r2)
                px[y][x] = lerp((0, 0, 0, 0), SUN_GLOW, t * 0.5)

    # 2. 远山 (取 [0,1] 坐标中的山峰, 转像素)
    far_peaks = [
        (0.0, 0.62), (0.15, 0.50), (0.30, 0.58), (0.45, 0.45),
        (0.60, 0.55), (0.75, 0.48), (0.90, 0.60), (1.0, 0.62),
    ]
    for x in range(w):
        xf = x / w
        for i in range(len(far_peaks) - 1):
            x0f, y0f = far_peaks[i]
            x1f, y1f = far_peaks[i + 1]
            if x0f <= xf <= x1f:
                t = (xf - x0f) / (x1f - x0f)
                peak_y_rel = y0f + (y1f - y0f) * t
                peak_x_px, peak_y_px = to_px(xf, peak_y_rel)
                for y in range(int(peak_y_px), h):
                    if 0 <= y < h:
                        px[y][x] = MOUNTAIN_FAR
                break

    # 3. 近山
    near_peaks = [
        (0.0, 0.72), (0.20, 0.52), (0.42, 0.62), (0.58, 0.48),
        (0.78, 0.60), (1.0, 0.70),
    ]
    for x in range(w):
        xf = x / w
        for i in range(len(near_peaks) - 1):
            x0f, y0f = near_peaks[i]
            x1f, y1f = near_peaks[i + 1]
            if x0f <= xf <= x1f:
                t = (xf - x0f) / (x1f - x0f)
                peak_y_rel = y0f + (y1f - y0f) * t
                _, peak_y_px = to_px(xf, peak_y_rel)
                for y in range(int(peak_y_px), h):
                    if 0 <= y < h:
                        px[y][x] = MOUNTAIN_NEAR
                break

    # 4. 帐篷 (居中靠左)
    tent_cx_r = 0.32
    tent_top_r = 0.68
    tent_base_r = 0.86
    tent_half_w_r = 0.13
    tpx, ttop_y = to_px(tent_cx_r, tent_top_r)
    _, tbase_y = to_px(tent_cx_r, tent_base_r)
    tent_half_w_px = tent_half_w_r * s

    for y in range(int(ttop_y), int(tbase_y)):
        if not (0 <= y < h):
            continue
        rel = (tbase_y - y) / (tbase_y - ttop_y)
        half = tent_half_w_px * rel
        for x in range(int(tpx - half), int(tpx + half)):
            if 0 <= x < w:
                px[y][x] = TENT
        if rel < 0.5:
            rel2 = rel / 0.5
            door_half = tent_half_w_px * 0.3 * rel2
            for x in range(int(tpx - door_half), int(tpx + door_half)):
                if 0 <= x < w:
                    px[y][x] = TENT_DOOR

    return px


def write_png(path, pixels):
    h = len(pixels)
    w = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter: None
        for r, g, b, a in row:
            raw.append(r)
            raw.append(g)
            raw.append(b)
            raw.append(a)
    compressed = zlib.compress(bytes(raw), 9)

    def chunk(ctype, data):
        return struct.pack('>I', len(data)) + ctype + data + struct.pack(
            '>I', zlib.crc32(ctype + data) & 0xFFFFFFFF)

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    png = sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', compressed) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


densities = {
    'mipmap-mdpi':    48,
    'mipmap-hdpi':    72,
    'mipmap-xhdpi':   96,
    'mipmap-xxhdpi':  144,
    'mipmap-xxxhdpi': 192,
}

base = 'android/res'

print("生成荒野手册图标 v3...")
for dirname, size in densities.items():
    # 完整图 (旧设备)
    full = gen_full_pixels(size)
    for name in ('ic_launcher.png', 'ic_launcher_round.png'):
        out_path = os.path.join(base, dirname, name)
        write_png(out_path, full)
        print(f"  {out_path} ({size}x{size}, {os.path.getsize(out_path)} bytes)")
    # adaptive icon foreground (Android 8+, 透明背景 + 居中 logo)
    fg = gen_foreground_pixels(size)
    out_path = os.path.join(base, dirname, 'ic_launcher_foreground.png')
    write_png(out_path, fg)
    print(f"  {out_path} ({size}x{size}, {os.path.getsize(out_path)} bytes) [foreground, transparent]")

print("完成!")
print()
print(f"adaptive icon 背景色建议: {ADAPTIVE_BG[:3]} (=#{ADAPTIVE_BG[0]:02X}{ADAPTIVE_BG[1]:02X}{ADAPTIVE_BG[2]:02X})")
