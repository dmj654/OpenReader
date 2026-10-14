#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenReader 应用图标生成器
--------------------------
纯标准库实现（zlib + struct），不依赖 Pillow。
程序化绘制一本摊开的书 + 书签丝带，输出 1024x1024 无 Alpha 的 RGB PNG。

用法:
    python scripts/make_icon.py
输出:
    OpenReader/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""

import os
import struct
import zlib

SIZE = 1024
SS = 4  # 每个像素在垂直方向的子采样数，用于抗锯齿

# ---------------------------------------------------------------- PNG 编码


def _chunk(tag: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + tag
        + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


def write_png(path: str, width: int, height: int, rows: list) -> None:
    """rows: list[bytearray]，每行长度为 width*3（RGB）。"""
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = bytearray()
    for row in rows:
        raw.append(0)  # filter type 0 (None)
        raw.extend(row)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + _chunk(b"IEND", b"")
    )
    with open(path, "wb") as fh:
        fh.write(png)


# ------------------------------------------------------------ 多边形工具


def quad(p0, p1, p2, p3):
    return [p0, p1, p2, p3]


def shade(color, factor):
    return (
        max(0, min(255, int(round(color[0] * factor)))),
        max(0, min(255, int(round(color[1] * factor)))),
        max(0, min(255, int(round(color[2] * factor)))),
    )


def spans_at(poly, y):
    """返回该扫描线上所有被多边形覆盖的区间（even-odd 规则）。"""
    xs = []
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if y1 == y2:
            continue
        lo, hi = (y1, y2) if y1 < y2 else (y2, y1)
        if lo <= y < hi:
            t = (y - y1) / (y2 - y1)
            xs.append(x1 + t * (x2 - x1))
    xs.sort()
    out = []
    for i in range(0, len(xs) - 1, 2):
        a, b = xs[i], xs[i + 1]
        if b > a:
            out.append((a, b))
    return out


def coverage_row(poly, y_center, buf, weight):
    """把多边形在 y_center 这一条子扫描线上的覆盖度累加到 buf。"""
    for xa, xb in spans_at(poly, y_center):
        if xb <= 0 or xa >= SIZE:
            continue
        xa = max(xa, 0.0)
        xb = min(xb, float(SIZE))
        i0 = int(xa)
        i1 = int(xb - 1e-9)
        if i0 == i1:
            buf[i0] += weight * (xb - xa)
            continue
        buf[i0] += weight * (i0 + 1 - xa)
        for i in range(i0 + 1, i1):
            buf[i] += weight
        buf[i1] += weight * (xb - i1)


def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def rounded_rect(x0, y0, x1, y1, r, steps=6):
    """圆角矩形（用折线近似圆角），足够平滑。"""
    import math

    pts = []
    corners = [
        (x1 - r, y0 + r, -90, 0),
        (x1 - r, y1 - r, 0, 90),
        (x0 + r, y1 - r, 90, 180),
        (x0 + r, y0 + r, 180, 270),
    ]
    for cx, cy, a0, a1 in corners:
        for s in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * s / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# ------------------------------------------------------------------ 绘制

TOP = (0x1B, 0x33, 0x5C)      # 深海军蓝
BOTTOM = (0x0B, 0x7C, 0x78)   # 孔雀青
PAGE = (0xFC, 0xF8, 0xEF)     # 奶油白
PAGE_SHADE = (0xE2, 0xDA, 0xC8)
INK = (0x3A, 0x52, 0x7A)      # 页面上的"文字"色
RIBBON = (0xE7, 0x5B, 0x3C)   # 书签橙红


def build_palette():
    """返回 [(polygon, (r,g,b), alpha)] —— 按绘制顺序。"""
    cx = 512.0

    # 书体几何
    book_top = 300.0
    book_bottom = 726.0
    left_x = 176.0
    right_x = 848.0

    left_page = quad(
        (cx, book_top + 26),
        (left_x, book_top - 22),
        (left_x, book_bottom - 26),
        (cx, book_bottom),
    )
    right_page = quad(
        (cx, book_top + 26),
        (right_x, book_top - 22),
        (right_x, book_bottom - 26),
        (cx, book_bottom),
    )
    # 书脊阴影（窄条，压在两页中间）
    spine = quad(
        (cx - 22, book_top + 12),
        (cx + 22, book_top + 12),
        (cx + 22, book_bottom - 6),
        (cx - 22, book_bottom - 6),
    )
    # 底部投影
    shadow = quad(
        (left_x + 18, book_top + 20),
        (right_x + 10, book_top + 24),
        (right_x - 4, book_bottom + 42),
        (left_x - 6, book_bottom + 34),
    )
    # 书签丝带（带燕尾）
    ribbon = [
        (cx + 96, book_top - 34),
        (cx + 168, book_top - 40),
        (cx + 166, book_bottom - 232),
        (cx + 132, book_bottom - 288),
        (cx + 100, book_bottom - 238),
    ]

    layers = [
        (shadow, (0x06, 0x1A, 0x2C), 0.26),
        (left_page, PAGE, 1.0),
        (spine, PAGE_SHADE, 0.85),
        (right_page, PAGE, 1.0),
    ]

    # 页面上的文字行
    rows_spec = [
        (0.00, 0.62),
        (0.13, 0.86),
        (0.26, 0.74),
        (0.39, 0.90),
        (0.52, 0.55),
    ]
    page_h = (book_bottom - 26) - (book_top - 22)
    for frac, w in rows_spec:
        yy = (book_top - 22) + page_h * (0.22 + frac)
        th = 13.0
        # 左页
        lx0 = left_x + 62
        layers.append((rounded_rect(lx0, yy - th / 2, lx0 + (cx - 78 - lx0) * w, yy + th / 2, th / 2), INK, 0.42))
        # 右页
        rx1 = right_x - 62
        layers.append((rounded_rect(rx1 - (rx1 - (cx + 78)) * w, yy - th / 2, rx1, yy + th / 2, th / 2), INK, 0.42))

    layers.append((ribbon, RIBBON, 1.0))
    return layers


def main():
    layers = build_palette()
    rows = []
    inv = 1.0 / (SIZE - 1)

    for y in range(SIZE):
        buf = bytearray(SIZE * 3)
        # 1) 背景对角渐变
        for x in range(SIZE):
            t = (x * 0.32 + y * 0.68) * inv
            t = t * t * (3 - 2 * t)  # smoothstep
            r = TOP[0] + (BOTTOM[0] - TOP[0]) * t
            g = TOP[1] + (BOTTOM[1] - TOP[1]) * t
            b = TOP[2] + (BOTTOM[2] - TOP[2]) * t
            o = x * 3
            buf[o] = int(r)
            buf[o + 1] = int(g)
            buf[o + 2] = int(b)

        # 2) 逐层合成（垂直 4 倍超采样）
        for poly, color, alpha in layers:
            cov = [0.0] * SIZE
            for s in range(SS):
                coverage_row(poly, y + (s + 0.5) / SS, cov, 1.0 / SS)
            for x in range(SIZE):
                c = cov[x]
                if c <= 0.0005:
                    continue
                a = alpha * (c if c < 1.0 else 1.0)
                o = x * 3
                ia = 1.0 - a
                buf[o] = int(buf[o] * ia + color[0] * a)
                buf[o + 1] = int(buf[o + 1] * ia + color[1] * a)
                buf[o + 2] = int(buf[o + 2] * ia + color[2] * a)

        rows.append(buf)

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(
        root, "OpenReader", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png"
    )
    os.makedirs(os.path.dirname(out), exist_ok=True)
    write_png(out, SIZE, SIZE, rows)
    print("图标已生成: %s (%d bytes)" % (out, os.path.getsize(out)))


if __name__ == "__main__":
    main()
