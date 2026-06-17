import json
import math
import random
import shutil
import sys
import uuid
from datetime import date, timedelta
from pathlib import Path

from PIL import Image, ImageDraw

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from server.main import (
    ORIGINALS_DIR,
    ROOT,
    THUMBNAILS_DIR,
    connect,
    create_batch,
    create_thumbnail,
    get_or_create_child,
    init_db,
    now_iso,
    relative_media_path,
    slug_text,
    upsert_tags,
)


TEST_DIR = ROOT / "test-data" / "sample-artworks"
BATCH_NAME = "Volio Demo Test Set"
CHILD_NAME = "Demo Kid"


def paper(size=(1200, 900)) -> Image.Image:
    image = Image.new("RGB", size, "#fbfaf4")
    draw = ImageDraw.Draw(image)
    rng = random.Random(42)
    for _ in range(180):
      x = rng.randrange(size[0])
      y = rng.randrange(size[1])
      shade = rng.randrange(225, 246)
      draw.point((x, y), fill=(shade, shade, shade))
    return image


def wobble(points, amount=5, seed=1):
    rng = random.Random(seed)
    return [(x + rng.randint(-amount, amount), y + rng.randint(-amount, amount)) for x, y in points]


def draw_tank(path: Path) -> None:
    image = paper()
    draw = ImageDraw.Draw(image)
    draw.line(wobble([(130, 650), (520, 600), (950, 660)], 12, 2), fill="#6aa06d", width=10)
    draw.rounded_rectangle((250, 410, 760, 560), radius=40, outline="#1b5e3a", width=18, fill="#88b66f")
    draw.rectangle((390, 320, 600, 430), outline="#1b5e3a", width=18, fill="#a8cc72")
    draw.line((590, 370, 890, 300), fill="#1b5e3a", width=20)
    for x in range(310, 720, 80):
        draw.ellipse((x, 535, x + 62, 597), outline="#23313d", width=14, fill="#d8e3cf")
    draw.line(wobble([(180, 210), (270, 160), (370, 200), (490, 145), (640, 205)], 15, 8), fill="#5da9e9", width=8)
    image.save(path, "JPEG", quality=92)


def draw_castle(path: Path) -> None:
    image = paper()
    draw = ImageDraw.Draw(image)
    for x in [190, 470, 750]:
        draw.rectangle((x, 310, x + 150, 650), outline="#734f96", width=14, fill="#d6b7ef")
        draw.polygon([(x - 15, 310), (x + 75, 190), (x + 165, 310)], outline="#e4577a", fill="#f98ea8")
    draw.rectangle((300, 410, 820, 650), outline="#734f96", width=14, fill="#f3d1ff")
    draw.arc((250, 555, 430, 780), 180, 360, fill="#6a4a80", width=14)
    for i, color in enumerate(["#ef476f", "#ffd166", "#06d6a0", "#118ab2"]):
        draw.arc((150 + i * 75, 95 + i * 7, 610 + i * 75, 440 + i * 7), 195, 335, fill=color, width=16)
    image.save(path, "JPEG", quality=92)


def draw_ocean(path: Path) -> None:
    image = paper()
    draw = ImageDraw.Draw(image)
    for y in range(250, 760, 70):
        draw.line(wobble([(80, y), (300, y + 30), (540, y - 10), (780, y + 25), (1080, y)], 11, y), fill="#48a7d4", width=10)
    fishes = [("#ff8a4c", 250, 390), ("#ffd166", 620, 500), ("#7bd88f", 850, 365)]
    for color, x, y in fishes:
        draw.ellipse((x, y, x + 160, y + 90), outline="#264653", width=9, fill=color)
        draw.polygon([(x + 150, y + 45), (x + 230, y), (x + 230, y + 90)], outline="#264653", fill=color)
        draw.ellipse((x + 35, y + 25, x + 52, y + 42), fill="#111827")
    for x, y in [(155, 560), (760, 230), (970, 610)]:
        draw.ellipse((x, y, x + 45, y + 45), outline="#7ec8e3", width=5)
    image.save(path, "JPEG", quality=92)


def draw_rocket(path: Path) -> None:
    image = paper()
    draw = ImageDraw.Draw(image)
    draw.polygon([(600, 160), (485, 420), (715, 420)], outline="#1d3557", fill="#e63946")
    draw.rounded_rectangle((500, 390, 700, 660), radius=50, outline="#1d3557", width=14, fill="#f1faee")
    draw.ellipse((560, 460, 640, 540), outline="#1d3557", width=10, fill="#a8dadc")
    draw.polygon([(500, 600), (380, 750), (520, 690)], fill="#457b9d", outline="#1d3557")
    draw.polygon([(700, 600), (820, 750), (680, 690)], fill="#457b9d", outline="#1d3557")
    for color, offset in [("#ffbe0b", 0), ("#fb5607", 35), ("#ff006e", -35)]:
        draw.polygon([(600 + offset, 665), (545 + offset, 820), (655 + offset, 820)], fill=color)
    for x, y in [(220, 180), (940, 220), (820, 110), (300, 590)]:
        draw.line((x - 18, y, x + 18, y), fill="#f4c430", width=8)
        draw.line((x, y - 18, x, y + 18), fill="#f4c430", width=8)
    image.save(path, "JPEG", quality=92)


def draw_robot(path: Path) -> None:
    image = paper()
    draw = ImageDraw.Draw(image)
    draw.rectangle((385, 230, 815, 610), outline="#36454f", width=16, fill="#b9c6d3")
    draw.rectangle((450, 130, 750, 260), outline="#36454f", width=16, fill="#d9e3ea")
    draw.ellipse((505, 170, 555, 220), fill="#2d6cdf")
    draw.ellipse((645, 170, 695, 220), fill="#2d6cdf")
    draw.line((550, 255, 650, 255), fill="#36454f", width=10)
    draw.line((385, 360, 260, 470), fill="#36454f", width=16)
    draw.line((815, 360, 940, 470), fill="#36454f", width=16)
    for x in [465, 565, 665]:
        draw.rounded_rectangle((x, 430, x + 65, 500), radius=12, outline="#36454f", width=8, fill="#ffd166")
    draw.line((600, 130, 600, 70), fill="#36454f", width=8)
    draw.ellipse((582, 45, 618, 80), fill="#ef476f")
    image.save(path, "JPEG", quality=92)


def draw_flowers(path: Path) -> None:
    image = paper()
    draw = ImageDraw.Draw(image)
    for x, y, color in [(280, 410, "#ff6b6b"), (520, 350, "#ffd166"), (760, 430, "#7bd88f"), (930, 360, "#b388eb")]:
        draw.line((x, y + 70, x - 20, 735), fill="#2f9e44", width=10)
        for angle in range(0, 360, 60):
            px = x + math.cos(math.radians(angle)) * 55
            py = y + math.sin(math.radians(angle)) * 45
            draw.ellipse((px - 35, py - 28, px + 35, py + 28), fill=color, outline="#4a4e69", width=5)
        draw.ellipse((x - 28, y - 28, x + 28, y + 28), fill="#f4a261", outline="#4a4e69", width=5)
    draw.line(wobble([(80, 745), (300, 710), (600, 735), (1040, 705)], 12, 5), fill="#6ab04c", width=12)
    image.save(path, "JPEG", quality=92)


DRAWERS = [
    ("green-tank-on-hill", draw_tank),
    ("rainbow-castle", draw_castle),
    ("orange-fish-ocean", draw_ocean),
    ("red-rocket-stars", draw_rocket),
    ("silver-robot-buttons", draw_robot),
    ("garden-flowers", draw_flowers),
]


RECORDS = [
    {
        "slug": "green-tank-on-hill",
        "title": "Green Tank on a Hill",
        "description": "A green tank rolls across a wavy hill, with large wheels and a long cannon pointing toward the sky.",
        "long_description": "The drawing uses thick green outlines and rounded shapes for the tank body. Blue cloud-like strokes float above it, and the uneven ground line makes the scene feel active.",
        "date": "2026-02-03",
        "quote": "This tank is going up the mountain.",
        "themes": ["vehicles", "imaginary battle", "outdoor scene"],
        "objects": ["tank", "wheels", "hill", "clouds"],
        "colors": ["green", "blue", "gray"],
        "materials": ["marker", "crayon"],
        "techniques": ["bold outline", "filled shapes"],
        "manual_tags": ["tank phase"],
    },
    {
        "slug": "rainbow-castle",
        "title": "Rainbow Castle",
        "description": "A purple castle sits under several bright rainbow arcs with pink tower roofs.",
        "long_description": "The castle is made from simple rectangles and triangle roofs. The rainbow bands repeat above the towers, giving the page a cheerful, storybook feeling.",
        "date": "2026-02-06",
        "quote": "",
        "themes": ["castle", "fantasy", "rainbow"],
        "objects": ["castle", "rainbow", "towers", "door"],
        "colors": ["purple", "pink", "yellow", "green", "blue"],
        "materials": ["marker"],
        "techniques": ["geometric shapes", "repeated arcs"],
        "manual_tags": [],
    },
    {
        "slug": "orange-fish-ocean",
        "title": "Fish in Blue Waves",
        "description": "Three colorful fish swim through loose blue wave lines with bubbles around them.",
        "long_description": "The fish are drawn with oval bodies and triangle tails. The repeated wave strokes organize the whole page into an underwater scene.",
        "date": "2026-02-12",
        "quote": "The yellow fish is the fastest one.",
        "themes": ["ocean", "animals", "movement"],
        "objects": ["fish", "waves", "bubbles"],
        "colors": ["blue", "orange", "yellow", "green"],
        "materials": ["marker"],
        "techniques": ["line repetition", "simple animal shapes"],
        "manual_tags": ["animals"],
    },
    {
        "slug": "red-rocket-stars",
        "title": "Rocket With Stars",
        "description": "A red and white rocket launches upward with colorful flames and small stars around it.",
        "long_description": "The rocket is centered on the page and built from a pointed triangle and rounded body. Bright flame shapes below it make the launch easy to recognize.",
        "date": "2026-03-01",
        "quote": "",
        "themes": ["space", "launch", "adventure"],
        "objects": ["rocket", "stars", "flames"],
        "colors": ["red", "white", "blue", "yellow"],
        "materials": ["marker"],
        "techniques": ["symmetry", "bold outline"],
        "manual_tags": ["space"],
    },
    {
        "slug": "silver-robot-buttons",
        "title": "Robot With Buttons",
        "description": "A silver robot has blue eyes, yellow chest buttons, and a small red antenna light.",
        "long_description": "The figure is made from boxy shapes and strong dark outlines. The repeated button shapes and simple arms make it look like a friendly machine.",
        "date": "2026-03-05",
        "quote": "It can clean my room but only on weekends.",
        "themes": ["robot", "machine", "character"],
        "objects": ["robot", "buttons", "antenna", "arms"],
        "colors": ["silver", "blue", "yellow", "red"],
        "materials": ["marker"],
        "techniques": ["geometric drawing", "character design"],
        "manual_tags": [],
    },
    {
        "slug": "garden-flowers",
        "title": "Garden of Big Flowers",
        "description": "Large flowers in red, yellow, green, and purple grow from a wavy grass line.",
        "long_description": "Each flower has repeated oval petals around a warm orange center. The stems lean in different directions, which gives the garden a loose handmade rhythm.",
        "date": "2026-04-10",
        "quote": "",
        "themes": ["garden", "plants", "spring"],
        "objects": ["flowers", "stems", "grass"],
        "colors": ["red", "yellow", "green", "purple", "orange"],
        "materials": ["marker"],
        "techniques": ["repeated shapes", "curved lines"],
        "manual_tags": ["spring"],
    },
]


def create_source_images() -> None:
    TEST_DIR.mkdir(parents=True, exist_ok=True)
    drawers = dict(DRAWERS)
    for record in RECORDS:
        path = TEST_DIR / f"{record['date']}-{record['slug']}.jpg"
        if not path.exists():
            drawers[record["slug"]](path)


def seed_database() -> None:
    init_db()
    with connect() as con:
        existing = con.execute("SELECT id FROM batches WHERE name = ?", (BATCH_NAME,)).fetchone()
        if existing:
            print(f"Demo batch already exists: {BATCH_NAME}")
            return

        child = get_or_create_child(con, CHILD_NAME)
        batch = create_batch(con, child["id"], BATCH_NAME, "2026-04", "demo data")
        for index, record in enumerate(RECORDS):
            artwork_id = str(uuid.uuid4())
            year = record["date"][:4]
            filename = f"{record['date']}-{record['slug']}.jpg"
            source = TEST_DIR / filename
            safe = slug_text(Path(filename).stem, "demo-artwork")
            dest_name = f"demo-{artwork_id[:8]}-{safe}.jpg"
            original_path = ORIGINALS_DIR / year / dest_name
            thumb_path = THUMBNAILS_DIR / year / f"{Path(dest_name).stem}.webp"
            original_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, original_path)
            width, height = create_thumbnail(original_path, thumb_path)
            ts = now_iso()
            con.execute(
                """
                INSERT INTO artworks (
                  id, child_id, batch_id, work_type, ownership_status, visibility, title, description,
                  long_description, child_quote, artwork_date, date_note, original_path, thumbnail_path,
                  original_filename, width, height, physical_status, is_favorite, is_representative,
                  ai_status, ai_model, ai_locale, ai_raw_json, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    artwork_id,
                    child["id"],
                    batch["id"],
                    "artwork",
                    "parent_managed",
                    "private",
                    record["title"],
                    record["description"],
                    record["long_description"],
                    record["quote"] or None,
                    record["date"],
                    "demo test set",
                    relative_media_path(original_path),
                    relative_media_path(thumb_path),
                    filename,
                    width,
                    height,
                    "undecided",
                    1 if index in {0, 2} else 0,
                    1 if index in {1, 4} else 0,
                    "completed",
                    "demo-seed",
                    "en",
                    json.dumps(record, ensure_ascii=False),
                    ts,
                    ts,
                ),
            )
            con.execute(
                """
                INSERT INTO work_files (
                  id, artwork_id, file_role, file_path, filename, width, height, sort_order, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(uuid.uuid4()),
                    artwork_id,
                    "original",
                    relative_media_path(original_path),
                    filename,
                    width,
                    height,
                    0,
                    ts,
                ),
            )
            upsert_tags(con, artwork_id, "theme", record["themes"], "ai")
            upsert_tags(con, artwork_id, "object", record["objects"], "ai")
            upsert_tags(con, artwork_id, "color", record["colors"], "ai")
            upsert_tags(con, artwork_id, "material", record["materials"], "ai")
            upsert_tags(con, artwork_id, "technique", record["techniques"], "ai")
            upsert_tags(con, artwork_id, "custom", record["manual_tags"], "manual")
        con.commit()
    print(f"Created {len(RECORDS)} demo artworks in {TEST_DIR}")


def main() -> None:
    create_source_images()
    seed_database()


if __name__ == "__main__":
    main()
