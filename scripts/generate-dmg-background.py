#!/usr/bin/env python3
"""Generate a styled DMG background image for AgentBar installer.

Output: docs/assets/dmg-background@2x.png (1200x800, Retina 2x for 600x400 window)

Two-step visual guide:
  1. Drag AgentBar to Applications (chevron arrow between icons)
  2. Then open AgentBar from Applications (nudge text below)
"""

import os
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1200, 800
TOP_COLOR = (15, 23, 42)       # #0F172A (slate-900)
BOTTOM_COLOR = (30, 41, 59)    # #1E293B (slate-800)


def lerp(a, b, t):
    return int(a + (b - a) * t)


def load_font(size):
    for path in (
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNSText.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def draw_centered_text(draw, text, y, font, fill):
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    x = (WIDTH - text_w) // 2
    draw.text((x, y), text, fill=fill, font=font)


def main():
    img = Image.new("RGBA", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(img)

    # Vertical gradient background
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        r = lerp(TOP_COLOR[0], BOTTOM_COLOR[0], t)
        g = lerp(TOP_COLOR[1], BOTTOM_COLOR[1], t)
        b_val = lerp(TOP_COLOR[2], BOTTOM_COLOR[2], t)
        draw.line([(0, y), (WIDTH - 1, y)], fill=(r, g, b_val, 255))

    # --- Chevron arrow (between app icon and Applications) ---
    # Icons at y=165 (1x) → y=330 (2x). Center chevron on same line.
    chevron_x = WIDTH // 2
    chevron_y = 330
    arm_len = 40
    chevron_alpha = 60

    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    ov_draw = ImageDraw.Draw(overlay)

    for dx in range(-4, 5):
        ov_draw.line(
            [(chevron_x - arm_len + dx, chevron_y - arm_len),
             (chevron_x + dx, chevron_y)],
            fill=(226, 232, 240, chevron_alpha), width=6,
        )
        ov_draw.line(
            [(chevron_x + dx, chevron_y),
             (chevron_x - arm_len + dx, chevron_y + arm_len)],
            fill=(226, 232, 240, chevron_alpha), width=6,
        )

    img = Image.alpha_composite(img, overlay)

    # --- Text overlays ---
    text_overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    text_draw = ImageDraw.Draw(text_overlay)

    font = load_font(26)
    text_color = (255, 255, 255, 100)  # ~40% white

    # Step 1: drag instruction — y=580 (2x) → 290 (1x)
    draw_centered_text(
        text_draw,
        "1. Drag AgentBar to Applications",
        580,
        font,
        text_color,
    )

    # Step 2: launch nudge — y=640 (2x) → 320 (1x)
    draw_centered_text(
        text_draw,
        "2. Open AgentBar to get started",
        640,
        font,
        text_color,
    )

    img = Image.alpha_composite(img, text_overlay)

    # Save
    out_dir = os.path.join(os.path.dirname(__file__), "..", "docs", "assets")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "dmg-background@2x.png")
    img.save(out_path, "PNG")
    print(f"Generated: {out_path}")


if __name__ == "__main__":
    main()
