#!/usr/bin/env python3
"""生成 ikshell 应用图标（18 个尺寸）"""
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("错误: 需要安装 Pillow")
    print("运行: pip3 install pillow")
    sys.exit(1)

SIZES = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
OUTPUT_DIR = Path(sys.argv[1] if len(sys.argv) > 1 else "ikshell/Resources/Assets.xcassets/AppIcon.appiconset")

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

def draw_icon(size):
    """绘制暗色终端图标"""
    img = Image.new('RGB', (size, size), color=(17, 17, 27))
    draw = ImageDraw.Draw(img)

    # 绿色边框
    border = max(2, size // 64)
    draw.rectangle([border, border, size-border, size-border],
                   outline=(0, 255, 128), width=border)

    # 绘制 ">_" 符号
    font_size = size // 3
    x = size // 4
    y = size // 2 - font_size // 2

    # 简单的 > 符号（三角形）
    triangle = [(x, y), (x + font_size//2, y + font_size//2), (x, y + font_size)]
    draw.polygon(triangle, fill=(0, 255, 128))

    # _ 符号（下划线）
    x2 = x + font_size
    y2 = y + font_size - font_size//6
    draw.rectangle([x2, y2, x2 + font_size, y2 + font_size//8], fill=(0, 255, 128))

    return img

# 生成所有尺寸
for size in SIZES:
    icon = draw_icon(size)
    filename = f"icon-{size}.png"
    icon.save(OUTPUT_DIR / filename)
    print(f"✓ {filename}")

# 生成 Contents.json
contents = {
    "images": [
        {"size": "20x20", "idiom": "ipad", "filename": "icon-20.png", "scale": "1x"},
        {"size": "20x20", "idiom": "ipad", "filename": "icon-40.png", "scale": "2x"},
        {"size": "29x29", "idiom": "ipad", "filename": "icon-29.png", "scale": "1x"},
        {"size": "29x29", "idiom": "ipad", "filename": "icon-58.png", "scale": "2x"},
        {"size": "40x40", "idiom": "ipad", "filename": "icon-40.png", "scale": "1x"},
        {"size": "40x40", "idiom": "ipad", "filename": "icon-80.png", "scale": "2x"},
        {"size": "76x76", "idiom": "ipad", "filename": "icon-76.png", "scale": "1x"},
        {"size": "76x76", "idiom": "ipad", "filename": "icon-152.png", "scale": "2x"},
        {"size": "83.5x83.5", "idiom": "ipad", "filename": "icon-167.png", "scale": "2x"},
        {"size": "1024x1024", "idiom": "ios-marketing", "filename": "icon-1024.png", "scale": "1x"}
    ],
    "info": {"version": 1, "author": "xcode"}
}

import json
(OUTPUT_DIR / "Contents.json").write_text(json.dumps(contents, indent=2))
print(f"\n生成完成: {len(SIZES)} 个图标 → {OUTPUT_DIR}")
