from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "Volio.iconset"
ICNS = ROOT / "Volio.app" / "Contents" / "Resources" / "Volio.icns"


def font(size: int) -> ImageFont.ImageFont:
    for path in [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf",
        "/System/Library/Fonts/SFNS.ttf",
    ]:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def draw_icon(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    radius = int(size * 0.22)
    draw.rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=radius,
        fill=(246, 247, 249, 255),
        outline=(177, 196, 217, 255),
        width=max(1, int(size * 0.012)),
    )

    pad = int(size * 0.17)
    sheet = (pad, int(size * 0.18), size - pad, int(size * 0.72))
    draw.rounded_rectangle(
        sheet,
        radius=int(size * 0.045),
        fill=(255, 255, 255, 255),
        outline=(31, 61, 104, 255),
        width=max(1, int(size * 0.015)),
    )
    draw.ellipse(
        (int(size * 0.31), int(size * 0.33), int(size * 0.63), int(size * 0.57)),
        fill=(74, 134, 219, 255),
        outline=(20, 67, 132, 255),
        width=max(1, int(size * 0.01)),
    )
    draw.polygon(
        [
            (int(size * 0.60), int(size * 0.45)),
            (int(size * 0.78), int(size * 0.32)),
            (int(size * 0.78), int(size * 0.59)),
        ],
        fill=(49, 111, 198, 255),
    )
    for x, y in [(0.25, 0.36), (0.72, 0.31), (0.24, 0.58), (0.75, 0.64)]:
        r = max(2, int(size * 0.018))
        cx = int(size * x)
        cy = int(size * y)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(62, 171, 207, 255), width=max(1, int(size * 0.006)))

    label_font = font(int(size * 0.17))
    text = "V"
    box = draw.textbbox((0, 0), text, font=label_font)
    tw = box[2] - box[0]
    th = box[3] - box[1]
    draw.text(((size - tw) / 2, int(size * 0.76) - th / 2), text, fill=(17, 24, 39, 255), font=label_font)
    return image


def main() -> None:
    ICONSET.mkdir(exist_ok=True)
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for size, name in sizes:
        draw_icon(size).save(ICONSET / name)
    ICNS.parent.mkdir(parents=True, exist_ok=True)


if __name__ == "__main__":
    main()
