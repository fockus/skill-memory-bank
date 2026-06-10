#!/usr/bin/env python3
"""Generate site/og-image.png (1200x630) in the landing-page palette.

Usage: python3 site/tools/generate_og_image.py
Requires Pillow. Fonts fall back gracefully across macOS/Linux system fonts.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parent.parent / "og-image.png"

W, H = 1200, 630
BG = (244, 239, 227)
BG_SOFT = (251, 247, 239)
INK = (31, 36, 48)
INK_MUTED = (94, 101, 95)
DARK = (16, 22, 33)
LIME = (181, 214, 91)
SAND = (255, 177, 109)
ROSE = (226, 118, 104)
CREAM = (255, 249, 241)


def find_font(candidates: list[str], size: int, want_bold: bool = False) -> ImageFont.FreeTypeFont:
    for path in candidates:
        p = Path(path)
        if not p.is_file():
            continue
        for index in range(12):
            try:
                font = ImageFont.truetype(str(p), size, index=index)
            except (OSError, ValueError):
                break
            family, style = font.getname()
            style_l = style.lower()
            if want_bold and "bold" in style_l and "italic" not in style_l:
                return font
            if not want_bold and style_l in ("regular", "book", "roman", "medium"):
                return font
        try:
            return ImageFont.truetype(str(p), size)
        except (OSError, ValueError):
            continue
    return ImageFont.load_default(size)


SANS = [
    "/System/Library/Fonts/Avenir Next.ttc",
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]
MONO = [
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/Monaco.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
]


def main() -> None:
    img = Image.new("RGB", (W, H), BG)

    # Soft color blobs like the landing background gradients.
    blobs = Image.new("RGB", (W, H), BG)
    bd = ImageDraw.Draw(blobs)
    bd.ellipse((-200, -260, 420, 320), fill=(225, 233, 196))
    bd.ellipse((880, -220, 1420, 240), fill=(247, 222, 209))
    bd.ellipse((420, 470, 1100, 900), fill=(238, 230, 210))
    blobs = blobs.filter(ImageFilter.GaussianBlur(120))
    img = Image.blend(img, blobs, 0.55)

    d = ImageDraw.Draw(img)

    brand_font = find_font(SANS, 34, want_bold=True)
    meta_font = find_font(SANS, 26)
    headline_font = find_font(SANS, 84, want_bold=True)
    sub_font = find_font(SANS, 31)
    mono_font = find_font(MONO, 27)
    chip_font = find_font(SANS, 22)
    mark_font = find_font(SANS, 36, want_bold=True)

    margin = 80

    # Brand row: dark MB mark + name + version chip.
    mark = 76
    d.rounded_rectangle((margin, 64, margin + mark, 64 + mark), radius=20, fill=DARK)
    mb_box = d.textbbox((0, 0), "MB", font=mark_font)
    d.text(
        (
            margin + mark / 2 - (mb_box[2] - mb_box[0]) / 2,
            64 + mark / 2 - (mb_box[3] - mb_box[1]) / 2 - mb_box[1],
        ),
        "MB",
        font=mark_font,
        fill=CREAM,
    )
    d.text((margin + mark + 24, 70), "memory-bank-skill", font=brand_font, fill=INK)
    d.text((margin + mark + 24, 112), "v5.0.0 · MIT · open source", font=meta_font, fill=INK_MUTED)

    # Headline.
    d.text((margin, 178), "Persistent memory", font=headline_font, fill=INK)
    d.text((margin, 270), "for AI coding agents.", font=headline_font, fill=INK)
    # Lime underline accent under the second headline line.
    line2_box = d.textbbox((margin, 270), "for AI coding agents.", font=headline_font)
    d.rounded_rectangle(
        (margin + 4, line2_box[3] + 14, line2_box[2], line2_box[3] + 28), radius=7, fill=LIME
    )

    # Subline.
    sub_y = line2_box[3] + 56
    d.text(
        (margin, sub_y),
        "Plans, specs, code graph & cross-session recall —",
        font=sub_font,
        fill=INK_MUTED,
    )
    d.text(
        (margin, sub_y + 44),
        "a .memory-bank/ that lives next to your code.",
        font=sub_font,
        fill=INK_MUTED,
    )

    # Bottom-left: install command pill.
    cmd = "pipx install memory-bank-skill"
    cmd_box = d.textbbox((0, 0), cmd, font=mono_font)
    pill_w = (cmd_box[2] - cmd_box[0]) + 56
    pill_h = 58
    pill_y = H - 54 - pill_h
    d.rounded_rectangle((margin, pill_y, margin + pill_w, pill_y + pill_h), radius=16, fill=DARK)
    d.text(
        (margin + 28, pill_y + (pill_h - (cmd_box[3] - cmd_box[1])) / 2 - cmd_box[1]),
        cmd,
        font=mono_font,
        fill=LIME,
    )

    # Bottom-right: one muted line instead of chips (no room for both).
    tail = "works with 8 coding agents — zero lock-in"
    tail_box = d.textbbox((0, 0), tail, font=chip_font)
    d.text(
        (
            W - margin - (tail_box[2] - tail_box[0]),
            pill_y + (pill_h - (tail_box[3] - tail_box[1])) / 2 - tail_box[1],
        ),
        tail,
        font=chip_font,
        fill=INK_MUTED,
    )

    img.save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
