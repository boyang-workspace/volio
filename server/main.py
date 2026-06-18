import base64
import io
import json
import os
import re
import secrets
import shutil
import socket
import sqlite3
import subprocess
import threading
import time
import uuid
import zipfile
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import qrcode

import cv2
import numpy as np
import requests
from fastapi import BackgroundTasks, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageDraw, ImageFont, ImageOps

try:
    from pillow_heif import register_heif_opener

    register_heif_opener()
except Exception:
    pass


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
DB_PATH = DATA_DIR / "volio.sqlite"
LIBRARY_DIR = ROOT / "library"
ORIGINALS_DIR = LIBRARY_DIR / "originals"
PROCESSED_DIR = LIBRARY_DIR / "processed"
THUMBNAILS_DIR = LIBRARY_DIR / "thumbnails"
EXPORTS_DIR = ROOT / "exports"
STATIC_DIR = ROOT / "static"
FRONTEND_DIST = ROOT / "frontend" / "dist"
PROCESSOR_JOBS_DIR = DATA_DIR / "processor_jobs"

OLLAMA_URL = os.getenv("VOLIO_OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
OLLAMA_MODEL = os.getenv("VOLIO_OLLAMA_MODEL", "minicpm-v4.5:8b")
VOLIO_DEFAULT_LOCALE = os.getenv("VOLIO_DEFAULT_LOCALE", "en").strip() or "en"
VOLIO_AI_LOCALE = os.getenv("VOLIO_AI_LOCALE", VOLIO_DEFAULT_LOCALE).strip() or VOLIO_DEFAULT_LOCALE
SUPPORTED_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".tif", ".tiff"}

AI_IDLE_TIMEOUT = int(os.getenv("VOLIO_AI_IDLE_TIMEOUT", "300"))
AI_CONCURRENCY = int(os.getenv("VOLIO_AI_CONCURRENCY", "1"))
AI_WINDOW = os.getenv("VOLIO_AI_WINDOW", "")

_last_request_at: float = time.time()
_ai_queue_paused = threading.Event()
_ai_worker_lock = threading.Lock()
_ai_worker_active = False
_processor_worker_lock = threading.Lock()
_processor_worker_active = False
_mobile_sessions: dict[str, dict[str, Any]] = {}
_ios_pairing_sessions: dict[str, dict[str, Any]] = {}
MOBILE_TOKEN_TTL = 3600
IOS_PAIRING_TOKEN_TTL = 30 * 24 * 3600
SUPPORTED_LOCALES = {"en", "zh"}
DEFAULT_SETTINGS = {
    "ui_language": VOLIO_DEFAULT_LOCALE if VOLIO_DEFAULT_LOCALE in SUPPORTED_LOCALES else "en",
    "ai_language": VOLIO_AI_LOCALE if VOLIO_AI_LOCALE in SUPPORTED_LOCALES else "zh",
    "mobile_session_ttl_minutes": "60",
}
UNASSIGNED_CHILD_ID = "__volio_unassigned__"
UNASSIGNED_CHILD_NAME = "__Volio Unassigned__"


def lan_ip() -> str | None:
    try:
        result = subprocess.run(
            ["ipconfig", "getifaddr", "en0"],
            capture_output=True, text=True, timeout=2,
        )
        ip = result.stdout.strip()
        if ip:
            return ip
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip:
            return ip
    except Exception:
        pass
    return None


def server_port() -> str:
    return os.getenv("VOLIO_PORT", "8001")


app = FastAPI(title="Volio", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def ensure_dirs() -> None:
    for path in [
        DATA_DIR,
        ORIGINALS_DIR,
        PROCESSED_DIR,
        THUMBNAILS_DIR,
        PROCESSOR_JOBS_DIR,
        EXPORTS_DIR / "pdf",
        EXPORTS_DIR / "json",
        EXPORTS_DIR / "zip",
    ]:
        path.mkdir(parents=True, exist_ok=True)


def connect() -> sqlite3.Connection:
    ensure_dirs()
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA busy_timeout=5000")
    return con


def ensure_column(con: sqlite3.Connection, table: str, column: str, definition: str) -> None:
    existing = {row["name"] for row in con.execute(f"PRAGMA table_info({table})").fetchall()}
    if column not in existing:
        con.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


def ensure_unassigned_child(con: sqlite3.Connection) -> None:
    ts = now_iso()
    con.execute(
        """
        INSERT OR IGNORE INTO children (id, name, notes, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        (UNASSIGNED_CHILD_ID, UNASSIGNED_CHILD_NAME, "Internal Volio placeholder", ts, ts),
    )


def init_db() -> None:
    with connect() as con:
        con.executescript(
            """
            CREATE TABLE IF NOT EXISTS children (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL UNIQUE,
              birth_date TEXT,
              notes TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS batches (
              id TEXT PRIMARY KEY,
              child_id TEXT NOT NULL,
              name TEXT NOT NULL,
              work_type TEXT DEFAULT 'paper',
              artwork_date TEXT,
              date_precision TEXT,
              date_note TEXT,
              child_age_months INTEGER,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY (child_id) REFERENCES children(id)
            );

            CREATE TABLE IF NOT EXISTS projects (
              id TEXT PRIMARY KEY,
              person_id TEXT NOT NULL,
              title TEXT NOT NULL,
              description TEXT,
              project_type TEXT DEFAULT 'art_project',
              started_at TEXT,
              completed_at TEXT,
              date_note TEXT,
              status TEXT DEFAULT 'active',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY (person_id) REFERENCES children(id)
            );

            CREATE TABLE IF NOT EXISTS ios_pairing_tokens (
              token TEXT PRIMARY KEY,
              host TEXT NOT NULL,
              host_name TEXT NOT NULL,
              port INTEGER NOT NULL,
              base_url TEXT NOT NULL,
              created_at REAL NOT NULL,
              last_seen_at TEXT,
              ttl INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS artworks (
              id TEXT PRIMARY KEY,
              child_id TEXT NOT NULL,
              batch_id TEXT,
              project_id TEXT,
              work_type TEXT DEFAULT 'paper',
              stage TEXT,
              medium TEXT,
              story TEXT,
              visibility TEXT DEFAULT 'private',
              ownership_status TEXT DEFAULT 'parent_managed',
              title TEXT,
              description TEXT,
              long_description TEXT,
              child_quote TEXT,
              parent_note TEXT,
              artwork_date TEXT,
              date_precision TEXT,
              date_note TEXT,
              child_age_months INTEGER,
              original_path TEXT NOT NULL,
              processed_path TEXT,
              thumbnail_path TEXT,
              original_filename TEXT,
              width INTEGER,
              height INTEGER,
              physical_status TEXT DEFAULT 'undecided',
              is_favorite INTEGER DEFAULT 0,
              is_representative INTEGER DEFAULT 0,
              client_work_id TEXT,
              ai_status TEXT DEFAULT 'pending',
              ai_model TEXT,
              ai_locale TEXT,
              ai_error TEXT,
              ai_raw_json TEXT,
              deleted_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY (child_id) REFERENCES children(id),
              FOREIGN KEY (batch_id) REFERENCES batches(id),
              FOREIGN KEY (project_id) REFERENCES projects(id)
            );

            CREATE TABLE IF NOT EXISTS work_files (
              id TEXT PRIMARY KEY,
              artwork_id TEXT NOT NULL,
              file_role TEXT NOT NULL,
              file_path TEXT NOT NULL,
              filename TEXT,
              mime_type TEXT,
              width INTEGER,
              height INTEGER,
              sort_order INTEGER DEFAULT 0,
              created_at TEXT NOT NULL,
              FOREIGN KEY (artwork_id) REFERENCES artworks(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS collections (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              query_json TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS collection_items (
              collection_id TEXT NOT NULL,
              artwork_id TEXT NOT NULL,
              source TEXT,
              sort_order INTEGER DEFAULT 0,
              created_at TEXT NOT NULL,
              PRIMARY KEY (collection_id, artwork_id),
              FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE,
              FOREIGN KEY (artwork_id) REFERENCES artworks(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS tags (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              UNIQUE(name, type)
            );

            CREATE TABLE IF NOT EXISTS artwork_tags (
              artwork_id TEXT NOT NULL,
              tag_id TEXT NOT NULL,
              confidence REAL,
              source TEXT,
              PRIMARY KEY (artwork_id, tag_id),
              FOREIGN KEY (artwork_id) REFERENCES artworks(id) ON DELETE CASCADE,
              FOREIGN KEY (tag_id) REFERENCES tags(id)
            );

            CREATE TABLE IF NOT EXISTS preferences (
              key TEXT PRIMARY KEY,
              value TEXT
            );

            CREATE TABLE IF NOT EXISTS processor_jobs (
              id TEXT PRIMARY KEY,
              token_hint TEXT,
              source TEXT DEFAULT 'ios',
              work_id TEXT NOT NULL,
              work_type TEXT DEFAULT 'paper',
              title TEXT,
              created_around_kind TEXT,
              created_around_label TEXT,
              created_around_year INTEGER,
              created_around_month INTEGER,
              created_around_season TEXT,
              created_around_age_months INTEGER,
              file_path TEXT NOT NULL,
              status TEXT NOT NULL,
              result_json TEXT,
              error_message TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              completed_at TEXT
            );
            """
        )
        ensure_column(con, "artworks", "project_id", "TEXT")
        ensure_column(con, "artworks", "work_type", "TEXT DEFAULT 'artwork'")
        ensure_column(con, "artworks", "stage", "TEXT")
        ensure_column(con, "artworks", "medium", "TEXT")
        ensure_column(con, "artworks", "story", "TEXT")
        ensure_column(con, "artworks", "visibility", "TEXT DEFAULT 'private'")
        ensure_column(con, "artworks", "ownership_status", "TEXT DEFAULT 'parent_managed'")
        ensure_column(con, "artworks", "ai_locale", "TEXT")
        ensure_column(con, "artworks", "processed_path", "TEXT")
        ensure_column(con, "artworks", "processed_status", "TEXT")
        ensure_column(con, "artworks", "processed_error", "TEXT")
        ensure_column(con, "artworks", "deleted_at", "TEXT")
        ensure_column(con, "artworks", "date_precision", "TEXT")
        ensure_column(con, "artworks", "child_age_months", "INTEGER")
        ensure_column(con, "artworks", "client_work_id", "TEXT")
        con.execute(
            """
            UPDATE artworks
            SET client_work_id = replace(replace(original_filename, '.jpg', ''), '.jpeg', '')
            WHERE (client_work_id IS NULL OR trim(client_work_id) = '')
              AND lower(original_filename) GLOB '[0-9a-f]*.jp*g'
              AND length(replace(replace(original_filename, '.jpg', ''), '.jpeg', '')) >= 32
            """
        )
        ensure_column(con, "batches", "work_type", "TEXT DEFAULT 'paper'")
        ensure_column(con, "batches", "date_precision", "TEXT")
        ensure_column(con, "batches", "child_age_months", "INTEGER")
        ensure_unassigned_child(con)
        con.execute(
            "UPDATE artworks SET child_id = ? WHERE child_id IS NULL OR trim(child_id) = ''",
            (UNASSIGNED_CHILD_ID,),
        )
        con.execute(
            "UPDATE batches SET child_id = ? WHERE child_id IS NULL OR trim(child_id) = ''",
            (UNASSIGNED_CHILD_ID,),
        )
        con.execute("UPDATE artworks SET work_type = 'artwork' WHERE work_type IS NULL")
        con.execute("UPDATE artworks SET visibility = 'private' WHERE visibility IS NULL")
        con.execute("UPDATE artworks SET ownership_status = 'parent_managed' WHERE ownership_status IS NULL")
        con.execute(
            """
            UPDATE artworks
            SET processed_path = NULL,
                processed_status = 'original',
                processed_error = NULL
            WHERE processed_path IS NOT NULL
            """
        )
        con.execute("DELETE FROM work_files WHERE file_role = 'processed'")
        if pref(con, "ui_language") == "zh" and pref(con, "ui_language_default_en_migrated") != "true":
            set_pref(con, "ui_language", "en")
            set_pref(con, "ui_language_default_en_migrated", "true")
        con.execute(
            """
            UPDATE artworks
            SET ai_status = 'failed',
                ai_error = 'Analysis was interrupted. Run AI again.',
                updated_at = ?
            WHERE ai_status = 'processing'
            """,
            (now_iso(),),
        )
        con.execute(
            """
            UPDATE processor_jobs
            SET status = 'failed',
                error_message = 'Processing was interrupted. Retry from Volio.',
                updated_at = ?
            WHERE status = 'processing'
            """,
            (now_iso(),),
        )


def row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    return dict(row) if row else None


def rows_to_dicts(rows: list[sqlite3.Row]) -> list[dict[str, Any]]:
    return [dict(row) for row in rows]


def pref(con: sqlite3.Connection, key: str, fallback: str | None = None) -> str | None:
    row = con.execute("SELECT value FROM preferences WHERE key = ?", (key,)).fetchone()
    if row and row["value"] is not None:
        return row["value"]
    return fallback


def set_pref(con: sqlite3.Connection, key: str, value: str) -> None:
    con.execute("INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?)", (key, value))


def current_settings(con: sqlite3.Connection) -> dict[str, Any]:
    ui_language = pref(con, "ui_language", DEFAULT_SETTINGS["ui_language"]) or "en"
    ai_language = pref(con, "ai_language", DEFAULT_SETTINGS["ai_language"]) or "zh"
    ttl_raw = pref(con, "mobile_session_ttl_minutes", DEFAULT_SETTINGS["mobile_session_ttl_minutes"]) or "60"
    try:
        ttl_minutes = max(5, min(480, int(ttl_raw)))
    except ValueError:
        ttl_minutes = 60
    if ui_language not in SUPPORTED_LOCALES:
        ui_language = "en"
    if ai_language not in SUPPORTED_LOCALES:
        ai_language = "zh"
    return {
        "ui_language": ui_language,
        "ai_language": ai_language,
        "mobile_session_ttl_minutes": ttl_minutes,
    }


def slug_text(value: str, fallback: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip()).strip("-._")
    return safe[:80] or fallback


def relative_media_path(path: Path) -> str:
    return str(path.relative_to(ROOT))


def resolve_library_path(rel_path: str) -> Path:
    path = (ROOT / rel_path).resolve()
    library_root = LIBRARY_DIR.resolve()
    if not str(path).startswith(str(library_root)):
        raise HTTPException(status_code=403, detail="Invalid media path")
    if not path.exists():
        raise HTTPException(status_code=404, detail="Media not found")
    return path


def exif_date(path: Path) -> str | None:
    try:
        image = Image.open(path)
        exif = image.getexif()
        raw = exif.get(36867)
        if raw and re.match(r"^\d{4}:\d{2}:\d{2}", raw):
            return raw[:10].replace(":", "-")
    except Exception:
        pass
    return None


def image_year(date_value: str | None) -> str:
    if date_value and re.match(r"^\d{4}", date_value):
        return date_value[:4]
    return str(datetime.now().year)


def get_or_create_child(con: sqlite3.Connection, name: str, birth_date: str | None = None) -> dict[str, Any]:
    clean_name = name.strip() or "Child"
    if clean_name.lower() == UNASSIGNED_CHILD_NAME.lower():
        ensure_unassigned_child(con)
        row = con.execute("SELECT * FROM children WHERE id = ?", (UNASSIGNED_CHILD_ID,)).fetchone()
        return dict(row)
    row = con.execute("SELECT * FROM children WHERE lower(name) = lower(?)", (clean_name,)).fetchone()
    if row:
        if birth_date and not row["birth_date"]:
            con.execute(
                "UPDATE children SET birth_date = ?, updated_at = ? WHERE id = ?",
                (birth_date.strip(), now_iso(), row["id"]),
            )
            row = con.execute("SELECT * FROM children WHERE id = ?", (row["id"],)).fetchone()
        return dict(row)
    child_id = str(uuid.uuid4())
    ts = now_iso()
    con.execute(
        "INSERT INTO children (id, name, birth_date, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        (child_id, clean_name, birth_date.strip() if birth_date else None, ts, ts),
    )
    return {
        "id": child_id,
        "name": clean_name,
        "birth_date": birth_date.strip() if birth_date else None,
        "notes": None,
        "created_at": ts,
        "updated_at": ts,
    }


def visible_child_id(child_id: str | None) -> str | None:
    if not child_id or child_id == UNASSIGNED_CHILD_ID:
        return None
    return child_id


def store_child_id(child_id: Any) -> str:
    if child_id is None:
        return UNASSIGNED_CHILD_ID
    value = str(child_id).strip()
    return value or UNASSIGNED_CHILD_ID


def parse_int(value: Any) -> int | None:
    if value is None:
        return None
    try:
        text = str(value).strip()
        if not text:
            return None
        return int(float(text))
    except (TypeError, ValueError):
        return None


def normalized_precision(value: str | None, artwork_date: str | None = None, child_age_months: int | None = None) -> str:
    clean = (value or "").strip().lower()
    if clean in {"date", "month", "season", "year", "age", "unknown"}:
        return clean
    if child_age_months is not None:
        return "age"
    text = (artwork_date or "").strip()
    if re.match(r"^\d{4}-\d{2}-\d{2}$", text):
        return "date"
    if re.match(r"^\d{4}-\d{2}$", text):
        return "month"
    if re.match(r"^\d{4}$", text):
        return "year"
    return "unknown"


def approximate_datetime(value: str | None, precision: str | None = None) -> datetime | None:
    text = (value or "").strip()
    if not text:
        return None
    precision = normalized_precision(precision, text)
    try:
        if re.match(r"^\d{4}-\d{2}-\d{2}$", text):
            return datetime.strptime(text, "%Y-%m-%d")
        if re.match(r"^\d{4}-\d{2}$", text):
            return datetime.strptime(f"{text}-15", "%Y-%m-%d")
        if re.match(r"^\d{4}$", text):
            return datetime(int(text), 7 if precision == "year" else 1, 1)
    except ValueError:
        return None
    return None


def add_months(value: datetime, months: int) -> datetime:
    month_index = value.month - 1 + months
    year = value.year + month_index // 12
    month = month_index % 12 + 1
    day = min(value.day, 28)
    return datetime(year, month, day)


def age_months_from_dates(birth_date: str | None, artwork_date: str | None, precision: str | None = None) -> int | None:
    birth = approximate_datetime(birth_date, "month" if birth_date and len(birth_date.strip()) == 7 else None)
    created = approximate_datetime(artwork_date, precision)
    if not birth or not created or created < birth:
        return None
    months = (created.year - birth.year) * 12 + created.month - birth.month
    if created.day < birth.day:
        months -= 1
    return max(0, months)


def date_from_child_age(birth_date: str | None, child_age_months: int | None) -> str | None:
    if child_age_months is None:
        return None
    birth = approximate_datetime(birth_date, "month" if birth_date and len(birth_date.strip()) == 7 else None)
    if not birth:
        return None
    return add_months(birth, child_age_months).strftime("%Y-%m")


def age_label(child_age_months: int | None) -> str | None:
    if child_age_months is None:
        return None
    years = max(0, child_age_months) // 12
    months = max(0, child_age_months) % 12
    if months == 0:
        return f"{years} years old"
    return f"{years}y {months}m"


def timeline_group_label(child_age_months: int | None, artwork_date: str | None, date_note: str | None) -> str:
    if child_age_months is not None:
        return f"Age {max(0, child_age_months) // 12}"
    if artwork_date:
        return str(artwork_date)[:4]
    if date_note:
        return str(date_note)
    return "Date unknown"


def created_around_label(artwork_date: str | None, precision: str | None, date_note: str | None, child_age_months: int | None) -> str:
    if date_note:
        return date_note
    if child_age_months is not None and normalized_precision(precision, artwork_date, child_age_months) == "age":
        return age_label(child_age_months) or "Age unknown"
    text = (artwork_date or "").strip()
    if not text:
        return "Date unknown"
    precision = normalized_precision(precision, text, child_age_months)
    if precision == "year":
        return text[:4]
    if precision == "month" and re.match(r"^\d{4}-\d{2}", text):
        try:
            return datetime.strptime(text[:7], "%Y-%m").strftime("%B %Y")
        except ValueError:
            return text
    return text


def create_batch(
    con: sqlite3.Connection,
    child_id: str,
    name: str,
    artwork_date: str | None,
    date_note: str | None,
    date_precision: str | None = None,
    child_age_months: int | None = None,
    work_type: str = "paper",
) -> dict[str, Any]:
    batch_id = str(uuid.uuid4())
    ts = now_iso()
    batch_name = name.strip() or f"Import {datetime.now().strftime('%Y-%m-%d %H:%M')}"
    clean_precision = normalized_precision(date_precision, artwork_date, child_age_months)
    clean_work_type = work_type if work_type in {"paper", "object", "artwork"} else "paper"
    con.execute(
        """
        INSERT INTO batches (id, child_id, name, work_type, artwork_date, date_precision, date_note, child_age_months, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (batch_id, child_id, batch_name, clean_work_type, artwork_date or None, clean_precision, date_note or None, child_age_months, ts, ts),
    )
    return {
        "id": batch_id,
        "child_id": child_id,
        "name": batch_name,
        "work_type": clean_work_type,
        "artwork_date": artwork_date,
        "date_precision": clean_precision,
        "date_note": date_note,
        "child_age_months": child_age_months,
        "created_at": ts,
        "updated_at": ts,
    }


def open_uploaded_image(src: Path) -> Image.Image:
    try:
        image = Image.open(src)
        return ImageOps.exif_transpose(image).convert("RGB")
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Unsupported image: {src.name}") from exc


def create_thumbnail(original: Path, thumb: Path) -> tuple[int, int]:
    image = open_uploaded_image(original)
    width, height = image.size
    image.thumbnail((720, 720))
    thumb.parent.mkdir(parents=True, exist_ok=True)
    image.save(thumb, "WEBP", quality=82)
    return width, height


def read_cv_image(path: Path) -> np.ndarray:
    image = open_uploaded_image(path)
    return cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)


def save_cv_image(image: np.ndarray, path: Path, quality: int = 92) -> None:
    rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    pil = Image.fromarray(rgb)
    path.parent.mkdir(parents=True, exist_ok=True)
    pil.save(path, "WEBP", quality=quality)


def order_quad(points: np.ndarray) -> np.ndarray:
    pts = points.reshape(4, 2).astype("float32")
    s = pts.sum(axis=1)
    diff = np.diff(pts, axis=1)
    ordered = np.zeros((4, 2), dtype="float32")
    ordered[0] = pts[np.argmin(s)]
    ordered[2] = pts[np.argmax(s)]
    ordered[1] = pts[np.argmin(diff)]
    ordered[3] = pts[np.argmax(diff)]
    return ordered


def four_point_transform(image: np.ndarray, points: np.ndarray) -> np.ndarray:
    rect = order_quad(points)
    tl, tr, br, bl = rect
    width_a = np.linalg.norm(br - bl)
    width_b = np.linalg.norm(tr - tl)
    height_a = np.linalg.norm(tr - br)
    height_b = np.linalg.norm(tl - bl)
    max_width = max(1, int(max(width_a, width_b)))
    max_height = max(1, int(max(height_a, height_b)))
    dst = np.array(
        [[0, 0], [max_width - 1, 0], [max_width - 1, max_height - 1], [0, max_height - 1]],
        dtype="float32",
    )
    matrix = cv2.getPerspectiveTransform(rect, dst)
    return cv2.warpPerspective(image, matrix, (max_width, max_height), flags=cv2.INTER_CUBIC)


def find_document_quad(image: np.ndarray) -> np.ndarray | None:
    height, width = image.shape[:2]
    max_side = max(height, width)
    scale = 1.0
    resized = image
    if max_side > 1200:
        scale = 1200 / max_side
        resized = cv2.resize(image, (int(width * scale), int(height * scale)), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(gray, 50, 150)
    edges = cv2.dilate(edges, np.ones((3, 3), dtype=np.uint8), iterations=1)
    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None
    resized_area = resized.shape[0] * resized.shape[1]
    for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:8]:
        area = cv2.contourArea(contour)
        if area < resized_area * 0.18:
            continue
        peri = cv2.arcLength(contour, True)
        approx = cv2.approxPolyDP(contour, 0.025 * peri, True)
        if len(approx) == 4 and cv2.isContourConvex(approx):
            return approx.reshape(4, 2).astype("float32") / scale
    return None


def normalize_lighting(image: np.ndarray, strength: float = 0.28) -> np.ndarray:
    height, width = image.shape[:2]
    sigma = max(18, int(max(height, width) / 28))
    blurred = cv2.GaussianBlur(image, (0, 0), sigmaX=sigma, sigmaY=sigma)
    corrected = cv2.divide(image, blurred, scale=245)
    corrected = cv2.normalize(corrected, None, 0, 255, cv2.NORM_MINMAX)
    lab = cv2.cvtColor(corrected, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=1.15, tileGridSize=(8, 8))
    l_channel = clahe.apply(l_channel)
    corrected = cv2.cvtColor(cv2.merge((l_channel, a_channel, b_channel)), cv2.COLOR_LAB2BGR)
    strength = max(0.0, min(1.0, strength))
    return cv2.addWeighted(image, 1.0 - strength, corrected, strength, 0)


def rotate_cv_image(image: np.ndarray, degrees: int) -> np.ndarray:
    normalized = degrees % 360
    if normalized == 90:
        return cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
    if normalized == 180:
        return cv2.rotate(image, cv2.ROTATE_180)
    if normalized == 270:
        return cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return image


def apply_normalized_crop(image: np.ndarray, crop: dict[str, Any] | None) -> np.ndarray:
    if not crop:
        return image
    height, width = image.shape[:2]
    x = max(0.0, min(1.0, float(crop.get("x", 0))))
    y = max(0.0, min(1.0, float(crop.get("y", 0))))
    w = max(0.02, min(1.0 - x, float(crop.get("w", 1))))
    h = max(0.02, min(1.0 - y, float(crop.get("h", 1))))
    left = int(x * width)
    top = int(y * height)
    right = max(left + 1, int((x + w) * width))
    bottom = max(top + 1, int((y + h) * height))
    return image[top:bottom, left:right]


def apply_normalized_perspective(image: np.ndarray, points: list[Any] | None) -> np.ndarray:
    if not points or len(points) != 4:
        return image
    height, width = image.shape[:2]
    quad: list[list[float]] = []
    try:
        for point in points:
            quad.append([
                max(0.0, min(1.0, float(point.get("x", 0)))) * width,
                max(0.0, min(1.0, float(point.get("y", 0)))) * height,
            ])
    except Exception:
        return image
    warped = four_point_transform(image, np.array(quad, dtype="float32"))
    if warped.shape[0] < 40 or warped.shape[1] < 40:
        return image
    return warped


def processed_path_for(original_rel: str) -> Path:
    original = ROOT / original_rel
    year = original.parent.name if original.parent.name else str(datetime.now().year)
    return PROCESSED_DIR / year / f"{original.stem}-processed.webp"


def artwork_source_path(row: sqlite3.Row, source: str = "display") -> Path:
    return ROOT / row["original_path"]


def process_artwork_image(
    artwork_id: str,
    mode: str = "auto",
    crop: dict[str, Any] | None = None,
    perspective: list[Any] | None = None,
    rotate: int = 0,
    source: str = "original",
    enhance: bool = False,
) -> dict[str, Any]:
    init_db()
    with connect() as con:
        row = con.execute("SELECT * FROM artworks WHERE id = ?", (artwork_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artwork not found")
        if mode == "reset":
            con.execute(
                "UPDATE artworks SET processed_path = NULL, processed_status = ?, processed_error = NULL, updated_at = ? WHERE id = ?",
                ("original", now_iso(), artwork_id),
            )
            con.commit()
            return {"processed": False, "mode": "reset"}
        src_path = artwork_source_path(row, source)
        dest_path = processed_path_for(row["original_path"])

    try:
        image = read_cv_image(src_path)
        image = rotate_cv_image(image, rotate)
        image = apply_normalized_perspective(image, perspective)
        image = apply_normalized_crop(image, crop)
        transformed = False
        if mode == "auto":
            quad = find_document_quad(image)
            if quad is not None:
                warped = four_point_transform(image, quad)
                if warped.shape[0] > 100 and warped.shape[1] > 100:
                    image = warped
                    transformed = True
        if enhance:
            image = normalize_lighting(image)
        save_cv_image(image, dest_path)
        height, width = image.shape[:2]
        rel = relative_media_path(dest_path)
        with connect() as con:
            con.execute(
                """
                UPDATE artworks
                SET processed_path = ?,
                    processed_status = ?,
                    processed_error = NULL,
                    width = ?,
                    height = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (rel, "auto" if mode == "auto" else "manual", width, height, now_iso(), artwork_id),
            )
            con.execute(
                """
                INSERT OR REPLACE INTO work_files (
                  id, artwork_id, file_role, file_path, filename, width, height, sort_order, created_at
                )
                VALUES (
                  COALESCE((SELECT id FROM work_files WHERE artwork_id = ? AND file_role = 'processed'), ?),
                  ?, 'processed', ?, ?, ?, ?, 1, ?
                )
                """,
                (
                    artwork_id,
                    str(uuid.uuid4()),
                    artwork_id,
                    rel,
                    dest_path.name,
                    width,
                    height,
                    now_iso(),
                ),
            )
            con.commit()
        return {
            "processed": True,
            "mode": mode,
            "transformed": transformed,
            "enhanced": enhance,
            "source": source,
            "width": width,
            "height": height,
            "path": rel,
        }
    except Exception as exc:
        with connect() as con:
            con.execute(
                "UPDATE artworks SET processed_status = ?, processed_error = ?, updated_at = ? WHERE id = ?",
                ("failed", str(exc)[:500], now_iso(), artwork_id),
            )
            con.commit()
        if isinstance(exc, HTTPException):
            raise
        raise HTTPException(status_code=500, detail=f"Image processing failed: {exc}") from exc


def make_thumbnail(artwork_id: str) -> None:
    with connect() as con:
        row = con.execute("SELECT original_path, processed_path FROM artworks WHERE id = ?", (artwork_id,)).fetchone()
        if not row:
            return
        source_rel = row["original_path"]
        source = ROOT / source_rel
        source_path = Path(source_rel)
        year = source_path.parent.name
        stem = source_path.stem.replace("-processed", "")
        rel_thumb = str(Path("library") / "thumbnails" / year / f"{stem}.webp")
        thumb = ROOT / rel_thumb
        thumb.parent.mkdir(parents=True, exist_ok=True)
        image = open_uploaded_image(source)
        image.thumbnail((720, 720))
        image.save(thumb, "WEBP", quality=82)
        rel = relative_media_path(thumb)
        con.execute(
            "UPDATE artworks SET thumbnail_path = ?, updated_at = ? WHERE id = ?",
            (rel, now_iso(), artwork_id),
        )
        con.commit()


def prepare_artwork_display(artwork_id: str) -> None:
    make_thumbnail(artwork_id)


def clean_model_json(text: str) -> dict[str, Any]:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, flags=re.S)
        if not match:
            raise
        return json.loads(match.group(0))


def normalize_tag(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower())


GENERIC_AI_PHRASES = {
    "child artwork portfolio",
    "artwork portfolio",
    "creative portfolio",
    "portfolio showcasing",
    "portfolio of a child's artwork",
    "collection showcasing",
    "curated collection",
    "artistic creations",
    "creative output of young minds",
    "json schema",
    "visible content, colors, possible materials",
    "suggested tags",
    "materials guess",
    "techniques guess",
    "uncertainty",
    "a child's artwork portfolio",
}

GENERIC_AI_TAGS = {
    "art",
    "artwork",
    "child",
    "child art",
    "childhood",
    "child-centered",
    "creativity",
    "easy-to-understand",
    "gentle",
    "objective",
    "parent-friendly",
    "portfolio",
    "potential",
    "primary",
    "secondary",
    "suggested tags",
    "uncertainty",
    "warm",
}


def looks_generic_ai_text(value: str | None) -> bool:
    if not value:
        return False
    clean = re.sub(r"\s+", " ", value.strip().lower())
    if not clean:
        return False
    return any(phrase in clean for phrase in GENERIC_AI_PHRASES)


def filename_title(filename: str | None) -> str:
    stem = Path(filename or "Untitled artwork").stem
    clean = re.sub(r"[-_]+", " ", stem).strip()
    clean = re.sub(r"\s+", " ", clean)
    return clean[:120] or "Untitled artwork"


def clean_ai_text(value: Any, fallback: str = "") -> str:
    if isinstance(value, list):
        text = " ".join(str(item).strip() for item in value if str(item).strip())
    elif isinstance(value, dict):
        parts = []
        for key, item in value.items():
            label = str(key).replace("_", " ").strip()
            body = clean_ai_text(item)
            if label and body:
                parts.append(f"{label}: {body}")
        text = "\n".join(parts)
    else:
        text = str(value or "").strip()
    if looks_generic_ai_text(text):
        return fallback
    return text


def title_from_description(value: str | None) -> str:
    text = re.sub(r"[.。!！?？].*$", "", value or "").strip()
    text = re.sub(r"\s+", " ", text)
    if not text or looks_generic_ai_text(text):
        return ""
    words = text.split(" ")
    if len(words) > 8:
        text = " ".join(words[:8])
    return text[:80].strip().title()


def title_case_for_locale(value: str) -> str:
    if VOLIO_AI_LOCALE.lower().startswith("zh"):
        return value[:80].strip()
    return value[:80].strip().title()


def clean_ai_list(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []
    cleaned: list[str] = []
    seen: set[str] = set()
    for raw in values or []:
        if not isinstance(raw, str):
            continue
        value = normalize_tag(raw).lstrip("#＃").strip()
        if not value or looks_generic_ai_text(value):
            continue
        if value in GENERIC_AI_TAGS:
            continue
        if value not in seen:
            cleaned.append(value)
            seen.add(value)
    return cleaned[:12]


def split_tag_text(value: str) -> list[str]:
    text = re.sub(r"^[\s\-*•#＃]+", "", value.strip())
    text = re.sub(r"^(标签|tags?|tag 标签)\s*[：:]\s*", "", text, flags=re.I)
    parts = re.split(r"[,，;；、\n]+", text)
    return [part.strip().lstrip("#＃").strip() for part in parts if part.strip()]


def extract_labeled_sections(text: str) -> dict[str, str]:
    labels = {
        "标题": "title",
        "title": "title",
        "短描述": "short_description",
        "简短描述": "short_description",
        "short description": "short_description",
        "详细描述": "long_description",
        "长描述": "long_description",
        "detailed description": "long_description",
        "long description": "long_description",
        "标签": "tags",
        "tag": "tags",
        "tags": "tags",
        "tag 标签": "tags",
    }
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        line = re.sub(r"^[#*\-\s]+", "", line).strip()
        if not line:
            if current == "long_description":
                sections.setdefault(current, []).append("")
            continue
        match = re.match(r"^([^：:]{1,32})\s*[：:]\s*(.*)$", line)
        key = labels.get(match.group(1).strip().lower()) if match else None
        if key:
            current = key
            rest = match.group(2).strip()
            sections.setdefault(current, [])
            if rest:
                sections[current].append(rest)
        elif current:
            sections.setdefault(current, []).append(line)
    return {key: "\n".join(value).strip() for key, value in sections.items()}


def first_sentence(value: str) -> str:
    text = re.sub(r"\s+", " ", value or "").strip()
    if not text:
        return ""
    match = re.match(r"^(.{12,140}?[。.!！?？])", text)
    if match:
        return match.group(1).strip()
    return text[:140].strip()


def parse_ai_chat_text(text: str, filename: str | None) -> dict[str, Any]:
    sections = extract_labeled_sections(text)
    long_description = clean_ai_text(sections.get("long_description")) or clean_ai_text(text)
    short_description = clean_ai_text(sections.get("short_description")) or first_sentence(long_description)
    title = clean_ai_text(sections.get("title"))
    if not title:
        title = title_case_for_locale(first_sentence(short_description) or filename_title(filename))
    tag_source = sections.get("tags") or ""
    tags = split_tag_text(tag_source)
    if not tags and "标签" in text:
        tail = text.split("标签", 1)[1]
        tags = split_tag_text(tail)
    return {
        "title": title,
        "short_description": short_description,
        "long_description": long_description,
        "themes": [],
        "objects": [],
        "colors": [],
        "materials_guess": [],
        "techniques_guess": [],
        "suggested_tags": tags,
        "raw_text": text,
    }


def upsert_tags(
    con: sqlite3.Connection,
    artwork_id: str,
    tag_type: str,
    values: list[Any],
    source: str,
) -> None:
    for raw in values or []:
        if not isinstance(raw, str):
            continue
        name = normalize_tag(raw)
        if not name:
            continue
        row = con.execute("SELECT id FROM tags WHERE name = ? AND type = ?", (name, tag_type)).fetchone()
        tag_id = row["id"] if row else str(uuid.uuid4())
        if not row:
            con.execute("INSERT INTO tags (id, name, type) VALUES (?, ?, ?)", (tag_id, name, tag_type))
        con.execute(
            """
            INSERT OR REPLACE INTO artwork_tags (artwork_id, tag_id, confidence, source)
            VALUES (?, ?, ?, ?)
            """,
            (artwork_id, tag_id, 0.7, source),
        )


def tags_for_artwork(con: sqlite3.Connection, artwork_id: str) -> list[dict[str, Any]]:
    rows = con.execute(
        """
        SELECT tags.id, tags.name, tags.type, artwork_tags.source
        FROM artwork_tags
        JOIN tags ON tags.id = artwork_tags.tag_id
        WHERE artwork_tags.artwork_id = ?
        ORDER BY tags.type, tags.name
        """,
        (artwork_id,),
    ).fetchall()
    return rows_to_dicts(rows)


def hydrate_artwork(con: sqlite3.Connection, row: sqlite3.Row, base_url: str | None = None) -> dict[str, Any]:
    item = dict(row)
    if item.get("child_id") == UNASSIGNED_CHILD_ID:
        item["child_id"] = None
        item["child_name"] = None
    child_birth_date = item.get("child_birth_date")
    if item.get("child_id") and not child_birth_date:
        child_row = con.execute("SELECT birth_date FROM children WHERE id = ?", (item["child_id"],)).fetchone()
        child_birth_date = child_row["birth_date"] if child_row else None
    if child_birth_date:
        item["child_birth_date"] = child_birth_date
    stored_age = parse_int(item.get("child_age_months"))
    computed_age = stored_age if stored_age is not None else age_months_from_dates(
        child_birth_date,
        item.get("artwork_date"),
        item.get("date_precision"),
    )
    item["child_age_months"] = computed_age
    item["child_age_label"] = age_label(computed_age)
    item["created_around_label"] = created_around_label(
        item.get("artwork_date"),
        item.get("date_precision"),
        item.get("date_note"),
        computed_age,
    )
    item["timeline_group"] = timeline_group_label(computed_age, item.get("artwork_date"), item.get("date_note"))
    item["tags"] = tags_for_artwork(con, item["id"])
    item["thumbnail_url"] = f"/media/{item['thumbnail_path']}" if item.get("thumbnail_path") else None
    item["original_url"] = f"/media/{item['original_path']}"
    item["processed_url"] = f"/media/{item['processed_path']}" if item.get("processed_path") else None
    item["display_url"] = item["original_url"]
    if base_url:
        base = base_url.rstrip("/")
        item["thumbnail_absolute_url"] = f"{base}{item['thumbnail_url']}" if item.get("thumbnail_url") else None
        item["original_absolute_url"] = f"{base}{item['original_url']}"
        item["processed_absolute_url"] = f"{base}{item['processed_url']}" if item.get("processed_url") else None
        item["display_absolute_url"] = item["original_absolute_url"]
    return item


def ai_prompt(locale: str | None = None) -> str:
    language = (locale or VOLIO_AI_LOCALE).lower()
    if language.startswith("zh"):
        return """
理解和解释一下这张图片，并打上一些 tag。

请观察真实画面，不要照抄模板，不要说这是作品集。
如果图片里有印刷文字、手写标记、学习材料、涂鸦、插图、角色表情或拍摄背景，都要一起解释。
如果能看出文本主题，只总结主题和关键词，不要长篇抄题。
不要评价孩子水平，不要诊断心理；对意图不确定时用“可能”“看起来”。

请按这个格式回答：
标题：一句具体标题
短描述：一句话总结，适合显示在作品卡片上
详细描述：分段解释文字/学习内容、手绘插图、整体氛围或用途；写得具体一点，方便以后语义搜索
标签：用逗号分隔 8 到 14 个关键词，不要带 #，包含内容、场景、情绪、学科、画风、材料、用途
""".strip()
    return """
Understand and explain this image, then add useful tags.

Describe what is actually visible. Do not copy this prompt. Do not call it a portfolio.
If the image contains printed text, handwriting, study materials, notes, doodles, illustrations,
character expressions, or the photo context, explain those parts together.
If visible text has a topic, summarize the topic and keywords instead of transcribing long passages.
Do not score the work. Do not diagnose psychology. Use "may" or "appears" when intent is uncertain.

Use this format:
Title: one specific title
Short description: one sentence for the artwork card
Detailed description: a few concrete paragraphs explaining text/study context, drawing subject, mood, and possible use
Tags: 8 to 14 comma-separated keywords, no hashtags, covering content, context, mood, subject, visual style, material, and use
""".strip()


def analysis_image_bytes(path: Path) -> bytes:
    image = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    image.thumbnail((1400, 1400))
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=90, optimize=True)
    return buffer.getvalue()


def analyze_artwork(artwork_id: str) -> None:
    init_db()
    with connect() as con:
        row = con.execute("SELECT * FROM artworks WHERE id = ?", (artwork_id,)).fetchone()
        if not row:
            return
        settings = current_settings(con)
        ai_language = settings["ai_language"]
        con.execute(
            "UPDATE artworks SET ai_status = ?, ai_error = NULL, updated_at = ? WHERE id = ?",
            ("processing", now_iso(), artwork_id),
        )
        con.commit()
        analysis_path = ROOT / row["original_path"]

    try:
        image_bytes = analysis_image_bytes(analysis_path)
        payload = {
            "model": OLLAMA_MODEL,
            "messages": [
                {
                    "role": "user",
                    "content": ai_prompt(ai_language),
                    "images": [base64.b64encode(image_bytes).decode("ascii")],
                }
            ],
            "stream": False,
            "options": {"temperature": 0.1},
        }
        response = requests.post(f"{OLLAMA_URL}/api/chat", json=payload, timeout=180)
        response.raise_for_status()
        body = response.json()
        raw_text = body.get("message", {}).get("content", "").strip()
        if not raw_text:
            raw_text = body.get("response", "").strip()
        parsed = parse_ai_chat_text(raw_text, row["original_filename"])

        short_description = clean_ai_text(parsed.get("short_description"))
        long_description = clean_ai_text(parsed.get("long_description"))
        if not long_description and short_description:
            long_description = short_description
        fallback_title = title_from_description(short_description) or filename_title(row["original_filename"])
        title = clean_ai_text(parsed.get("title")) or fallback_title

        with connect() as con:
            con.execute(
                """
                UPDATE artworks
                SET title = COALESCE(NULLIF(?, ''), title),
                    description = ?,
                    long_description = ?,
                    ai_status = ?,
                    ai_model = ?,
                    ai_locale = ?,
                    ai_error = NULL,
                    ai_raw_json = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    title,
                    short_description,
                    long_description,
                    "completed",
                    OLLAMA_MODEL,
                    ai_language,
                    json.dumps({"raw_text": raw_text, "parsed": parsed}, ensure_ascii=False),
                    now_iso(),
                    artwork_id,
                ),
            )
            con.execute("DELETE FROM artwork_tags WHERE artwork_id = ? AND source = 'ai'", (artwork_id,))
            upsert_tags(con, artwork_id, "theme", clean_ai_list(parsed.get("themes", [])), "ai")
            upsert_tags(con, artwork_id, "object", clean_ai_list(parsed.get("objects", [])), "ai")
            upsert_tags(con, artwork_id, "color", clean_ai_list(parsed.get("colors", [])), "ai")
            upsert_tags(con, artwork_id, "material", clean_ai_list(parsed.get("materials_guess", [])), "ai")
            upsert_tags(con, artwork_id, "technique", clean_ai_list(parsed.get("techniques_guess", [])), "ai")
            upsert_tags(con, artwork_id, "semantic", clean_ai_list(parsed.get("suggested_tags", [])), "ai")
            con.commit()
    except Exception as exc:
        with connect() as con:
            con.execute(
                "UPDATE artworks SET ai_status = ?, ai_error = ?, updated_at = ? WHERE id = ?",
                ("failed", str(exc)[:500], now_iso(), artwork_id),
            )
            con.commit()


def processor_result_from_image(path: Path, filename: str | None, work_type: str | None = None) -> dict[str, Any]:
    settings_language = VOLIO_AI_LOCALE if VOLIO_AI_LOCALE in SUPPORTED_LOCALES else "en"
    image_bytes = analysis_image_bytes(path)
    payload = {
        "model": OLLAMA_MODEL,
        "messages": [
            {
                "role": "user",
                "content": ai_prompt(settings_language),
                "images": [base64.b64encode(image_bytes).decode("ascii")],
            }
        ],
        "stream": False,
        "options": {"temperature": 0.1},
    }
    response = requests.post(f"{OLLAMA_URL}/api/chat", json=payload, timeout=180)
    response.raise_for_status()
    body = response.json()
    raw_text = body.get("message", {}).get("content", "").strip() or body.get("response", "").strip()
    parsed = parse_ai_chat_text(raw_text, filename)
    short_description = clean_ai_text(parsed.get("short_description"))
    long_description = clean_ai_text(parsed.get("long_description")) or short_description
    fallback_title = title_from_description(short_description) or filename_title(filename)
    return {
        "title": clean_ai_text(parsed.get("title")) or fallback_title,
        "description": short_description,
        "long_description": long_description,
        "work_type": work_type or "paper",
        "materials": clean_ai_list(parsed.get("materials_guess", [])),
        "themes": clean_ai_list(parsed.get("themes", [])),
        "objects": clean_ai_list(parsed.get("objects", [])),
        "colors": clean_ai_list(parsed.get("colors", [])),
        "techniques": clean_ai_list(parsed.get("techniques_guess", [])),
        "tags": clean_ai_list(parsed.get("suggested_tags", [])),
        "raw": {"raw_text": raw_text, "parsed": parsed},
    }


def processor_job_payload(row: sqlite3.Row | dict[str, Any]) -> dict[str, Any]:
    data = dict(row)
    result = None
    if data.get("result_json"):
        try:
            result = json.loads(data["result_json"])
        except Exception:
            result = None
    return {
        "id": data["id"],
        "work_id": data.get("work_id"),
        "status": data.get("status"),
        "error_message": data.get("error_message"),
        "result": result,
        "created_at": data.get("created_at"),
        "updated_at": data.get("updated_at"),
        "completed_at": data.get("completed_at"),
    }


def next_processor_job_id() -> str | None:
    with connect() as con:
        row = con.execute(
            """
            SELECT id
            FROM processor_jobs
            WHERE status IN ('queued', 'failed_retry')
            ORDER BY created_at ASC
            LIMIT 1
            """
        ).fetchone()
        return row["id"] if row else None


def process_processor_job(job_id: str) -> None:
    with connect() as con:
        row = con.execute("SELECT * FROM processor_jobs WHERE id = ?", (job_id,)).fetchone()
        if not row:
            return
        con.execute(
            "UPDATE processor_jobs SET status = 'processing', error_message = NULL, updated_at = ? WHERE id = ?",
            (now_iso(), job_id),
        )
        con.commit()
        file_path = ROOT / row["file_path"]
        filename = file_path.name
        work_type = row["work_type"] or "paper"
    try:
        result = processor_result_from_image(file_path, filename, work_type)
        with connect() as con:
            con.execute(
                """
                UPDATE processor_jobs
                SET status = 'succeeded',
                    result_json = ?,
                    error_message = NULL,
                    updated_at = ?,
                    completed_at = ?
                WHERE id = ?
                """,
                (json.dumps(result, ensure_ascii=False), now_iso(), now_iso(), job_id),
            )
            con.commit()
    except Exception as exc:
        with connect() as con:
            con.execute(
                """
                UPDATE processor_jobs
                SET status = 'failed',
                    error_message = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (str(exc)[:500], now_iso(), job_id),
            )
            con.commit()


def processor_queue_worker() -> None:
    global _processor_worker_active
    try:
        while True:
            job_id = next_processor_job_id()
            if not job_id:
                break
            process_processor_job(job_id)
    finally:
        with _processor_worker_lock:
            _processor_worker_active = False


def start_processor_worker() -> bool:
    global _processor_worker_active
    with _processor_worker_lock:
        if _processor_worker_active:
            return True
        _processor_worker_active = True
        thread = threading.Thread(target=processor_queue_worker, name="volio-processor-queue", daemon=True)
        thread.start()
        return True


def next_unprocessed_artwork_id() -> str | None:
    with connect() as con:
        row = con.execute(
            f"""
            SELECT id
            FROM artworks
            WHERE {ACTIVE_ARTWORK_SQL}
              AND {UNPROCESSED_ARTWORK_SQL}
              AND ai_status != 'processing'
            ORDER BY updated_at ASC
            LIMIT 1
            """
        ).fetchone()
        return row["id"] if row else None


def ai_queue_worker() -> None:
    global _ai_worker_active
    try:
        while not _ai_queue_paused.is_set() and _can_process():
            artwork_id = next_unprocessed_artwork_id()
            if not artwork_id:
                break
            analyze_artwork(artwork_id)
    finally:
        with _ai_worker_lock:
            _ai_worker_active = False


def start_ai_queue_worker() -> bool:
    global _ai_worker_active
    if _ai_queue_paused.is_set() or not _can_process():
        return False
    with _ai_worker_lock:
        if _ai_worker_active:
            return True
        _ai_worker_active = True
        thread = threading.Thread(target=ai_queue_worker, name="volio-ai-queue", daemon=True)
        thread.start()
        return True


def save_upload(
    con: sqlite3.Connection,
    file: UploadFile,
    child_id: str,
    batch_id: str,
    artwork_date: str | None,
    date_note: str | None,
    date_precision: str | None = None,
    child_age_months: int | None = None,
    work_type: str = "paper",
    client_work_id: str | None = None,
) -> dict[str, Any]:
    original_name = file.filename or "artwork.jpg"
    ext = Path(original_name).suffix.lower()
    if ext == ".jpeg":
        ext = ".jpg"
    if ext not in SUPPORTED_EXTS:
        raise HTTPException(status_code=400, detail=f"Unsupported file type: {original_name}")

    child_row = con.execute("SELECT birth_date FROM children WHERE id = ?", (child_id,)).fetchone()
    child_birth_date = child_row["birth_date"] if child_row else None
    if not artwork_date and child_age_months is not None:
        artwork_date = date_from_child_age(child_birth_date, child_age_months)
    if child_age_months is None:
        child_age_months = age_months_from_dates(child_birth_date, artwork_date, date_precision)
    clean_precision = normalized_precision(date_precision, artwork_date, child_age_months)
    clean_work_type = work_type if work_type in {"paper", "object", "artwork"} else "paper"
    clean_client_work_id = (client_work_id or "").strip()[:120] or None

    if clean_client_work_id:
        existing = con.execute("SELECT * FROM artworks WHERE client_work_id = ?", (clean_client_work_id,)).fetchone()
        if existing:
            ts = now_iso()
            con.execute(
                """
                UPDATE artworks
                SET child_id = ?,
                    batch_id = COALESCE(batch_id, ?),
                    work_type = ?,
                    artwork_date = COALESCE(?, artwork_date),
                    date_precision = ?,
                    date_note = COALESCE(?, date_note),
                    child_age_months = COALESCE(?, child_age_months),
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    child_id,
                    batch_id,
                    clean_work_type,
                    artwork_date or None,
                    clean_precision,
                    date_note or None,
                    child_age_months,
                    ts,
                    existing["id"],
                ),
            )
            return {"id": existing["id"], "original_filename": existing["original_filename"], "client_work_id": clean_client_work_id, "reused": True}

    artwork_id = str(uuid.uuid4())
    year = image_year(artwork_date)
    safe_name = slug_text(Path(original_name).stem, "artwork")
    dest_name = f"{datetime.now().strftime('%Y%m%d-%H%M%S')}-{artwork_id[:8]}-{safe_name}{ext}"
    original_path = ORIGINALS_DIR / year / dest_name
    thumb_path = THUMBNAILS_DIR / year / f"{Path(dest_name).stem}.webp"
    original_path.parent.mkdir(parents=True, exist_ok=True)

    with original_path.open("wb") as handle:
        shutil.copyfileobj(file.file, handle)

    if not artwork_date:
        artwork_date = exif_date(original_path)

    image = open_uploaded_image(original_path)
    width, height = image.size

    ts = now_iso()
    con.execute(
        """
        INSERT INTO artworks (
          id, child_id, batch_id, work_type, ownership_status, visibility, title, artwork_date, date_precision, date_note, child_age_months, original_path,
          thumbnail_path, original_filename, width, height, client_work_id, ai_status, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            artwork_id,
            child_id,
            batch_id,
            clean_work_type,
            "parent_managed",
            "private",
            Path(original_name).stem.replace("_", " ").strip()[:120] or None,
            artwork_date or None,
            clean_precision,
            date_note or None,
            child_age_months,
            relative_media_path(original_path),
            None,
            original_name,
            width,
            height,
            clean_client_work_id,
            "pending",
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
            original_name,
            width,
            height,
            0,
            ts,
        ),
    )
    return {"id": artwork_id, "original_filename": original_name, "client_work_id": clean_client_work_id, "reused": False}


def artwork_query(
    con: sqlite3.Connection,
    child_id: str | None = None,
    batch_id: str | None = None,
    status: str | None = None,
    q: str | None = None,
    smart: str | None = None,
    tag: str | None = None,
    tag_type: str | None = None,
    year: str | None = None,
    base_url: str | None = None,
    include_deleted: bool = False,
) -> list[dict[str, Any]]:
    where = []
    params: list[Any] = []
    if smart == "trash":
        where.append("artworks.deleted_at IS NOT NULL AND artworks.deleted_at != ''")
    elif not include_deleted:
        where.append(ACTIVE_ARTWORK_SQL)
    if child_id:
        where.append("artworks.child_id = ?")
        params.append(child_id)
    if batch_id:
        where.append("artworks.batch_id = ?")
        params.append(batch_id)
    if status:
        where.append("artworks.ai_status = ?")
        params.append(status)
    if smart == "unreviewed":
        where.append("(artworks.ai_status != 'completed' OR artworks.title IS NULL OR artworks.title = '')")
    elif smart in {"unassigned", "uncategorized"}:
        where.append("artworks.child_id = ?")
        params.append(UNASSIGNED_CHILD_ID)
    elif smart == "untagged":
        where.append("NOT EXISTS (SELECT 1 FROM artwork_tags at_untagged WHERE at_untagged.artwork_id = artworks.id)")
    elif smart == "favorites":
        where.append("artworks.is_favorite = 1")
    elif smart == "representative":
        where.append("artworks.is_representative = 1")
    elif smart == "needs_quote":
        where.append("(artworks.child_quote IS NULL OR trim(artworks.child_quote) = '')")
    if year:
        where.append("COALESCE(artworks.artwork_date, artworks.created_at) LIKE ?")
        params.append(f"{year}%")
    if tag:
        where.append(
            """
            EXISTS (
              SELECT 1
              FROM artwork_tags at_tag
              JOIN tags t_tag ON t_tag.id = at_tag.tag_id
              WHERE at_tag.artwork_id = artworks.id
                AND t_tag.name = ?
                AND (? IS NULL OR t_tag.type = ?)
            )
            """
        )
        params.extend([normalize_tag(tag), tag_type, tag_type])
    if q:
        where.append(
            """
            (
              artworks.title LIKE ?
              OR artworks.description LIKE ?
              OR artworks.long_description LIKE ?
              OR artworks.parent_note LIKE ?
              OR artworks.child_quote LIKE ?
              OR EXISTS (
                SELECT 1
                FROM artwork_tags at2
                JOIN tags t2 ON t2.id = at2.tag_id
                WHERE at2.artwork_id = artworks.id AND t2.name LIKE ?
              )
            )
            """
        )
        needle = f"%{q}%"
        params.extend([needle, needle, needle, needle, needle, needle])
    clause = "WHERE " + " AND ".join(where) if where else ""
    rows = con.execute(
        f"""
        SELECT artworks.*, children.name AS child_name, batches.name AS batch_name
        FROM artworks
        LEFT JOIN children ON children.id = artworks.child_id
        LEFT JOIN batches ON batches.id = artworks.batch_id
        {clause}
        ORDER BY artworks.created_at DESC
        LIMIT 500
        """,
        params,
    ).fetchall()
    return [hydrate_artwork(con, row, base_url=base_url) for row in rows]


def count_where(con: sqlite3.Connection, where_sql: str = "", params: tuple[Any, ...] = ()) -> int:
    clause = f"WHERE {where_sql}" if where_sql else ""
    return con.execute(f"SELECT COUNT(*) AS n FROM artworks {clause}", params).fetchone()["n"]


ACTIVE_ARTWORK_SQL = "(artworks.deleted_at IS NULL OR artworks.deleted_at = '')"
UNPROCESSED_ARTWORK_SQL = """
(
  artworks.ai_status IN ('pending', 'failed')
  OR artworks.description IS NULL
  OR trim(artworks.description) = ''
  OR artworks.long_description IS NULL
  OR trim(artworks.long_description) = ''
)
"""


@app.middleware("http")
async def track_activity(request, call_next):
    global _last_request_at
    _last_request_at = time.time()
    return await call_next(request)


def _parse_window(window: str) -> tuple[float, float] | None:
    if not window:
        return None
    try:
        parts = window.split("-")
        start = float(parts[0].replace(":", "."))
        end = float(parts[1].replace(":", "."))
        return (start, end)
    except Exception:
        return None


def _in_window(window_spec: str) -> bool:
    parsed = _parse_window(window_spec)
    if parsed is None:
        return True
    start, end = parsed
    now = datetime.now()
    current = now.hour + now.minute / 60.0
    if start <= end:
        return start <= current <= end
    return current >= start or current <= end


def _can_process() -> bool:
    if _ai_queue_paused.is_set():
        return False
    if not _in_window(AI_WINDOW):
        return False
    idle_seconds = time.time() - _last_request_at
    if idle_seconds < AI_IDLE_TIMEOUT and not _in_window(AI_WINDOW):
        return False
    return True


def _queue_worker() -> None:
    while True:
        try:
            if not _can_process():
                time.sleep(30)
                continue

            with connect() as con:
                rows = con.execute(
                    f"""
                    SELECT id
                    FROM artworks
                    WHERE {ACTIVE_ARTWORK_SQL}
                      AND {UNPROCESSED_ARTWORK_SQL}
                      AND ai_status != 'processing'
                    ORDER BY updated_at ASC
                    LIMIT ?
                    """,
                    (AI_CONCURRENCY,),
                ).fetchall()

            if not rows:
                time.sleep(10)
                continue

            for row in rows:
                if not _can_process():
                    break
                analyze_artwork(row["id"])
        except Exception:
            time.sleep(10)


@app.on_event("startup")
def startup() -> None:
    init_db()
    worker = threading.Thread(target=_queue_worker, daemon=True)
    worker.start()


@app.get("/")
def index() -> FileResponse:
    return FileResponse(FRONTEND_DIST / "index.html")


@app.get("/assets/{path:path}")
def frontend_assets(path: str) -> FileResponse:
    return FileResponse(FRONTEND_DIST / "assets" / path)


@app.get("/media/{rel_path:path}")
def media(rel_path: str) -> FileResponse:
    return FileResponse(resolve_library_path(rel_path))


@app.get("/api/config")
def config() -> dict[str, Any]:
    try:
        response = requests.get(f"{OLLAMA_URL}/api/tags", timeout=2)
        ollama_ok = response.ok
    except Exception:
        ollama_ok = False
    with connect() as con:
        last_child = con.execute("SELECT value FROM preferences WHERE key = 'last_child_name'").fetchone()
        settings = current_settings(con)
    return {
        "ollama_url": OLLAMA_URL,
        "ollama_model": OLLAMA_MODEL,
        "ollama_ok": ollama_ok,
        "default_locale": settings["ui_language"],
        "ai_locale": settings["ai_language"],
        "last_child_name": last_child["value"] if last_child else None,
        "settings": settings,
        "ai_config": {
            "idle_timeout": AI_IDLE_TIMEOUT,
            "concurrency": AI_CONCURRENCY,
            "window": AI_WINDOW or None,
        },
    }


@app.get("/api/settings")
def get_settings() -> dict[str, Any]:
    with connect() as con:
        return current_settings(con)


@app.patch("/api/settings")
async def update_settings(payload: dict[str, Any]) -> dict[str, Any]:
    ui_language = (payload.get("ui_language") or "").strip()
    ai_language = (payload.get("ai_language") or "").strip()
    ttl_raw = payload.get("mobile_session_ttl_minutes")

    with connect() as con:
        if ui_language:
            if ui_language not in SUPPORTED_LOCALES:
                raise HTTPException(status_code=400, detail="Unsupported UI language")
            set_pref(con, "ui_language", ui_language)
        if ai_language:
            if ai_language not in SUPPORTED_LOCALES:
                raise HTTPException(status_code=400, detail="Unsupported AI language")
            set_pref(con, "ai_language", ai_language)
        if ttl_raw is not None:
            try:
                ttl_minutes = max(5, min(480, int(ttl_raw)))
            except (TypeError, ValueError) as exc:
                raise HTTPException(status_code=400, detail="Invalid phone import duration") from exc
            set_pref(con, "mobile_session_ttl_minutes", str(ttl_minutes))
        con.commit()
        return current_settings(con)


@app.get("/api/state")
def state() -> dict[str, Any]:
    with connect() as con:
        counts = {
            "children": con.execute("SELECT COUNT(*) AS n FROM children WHERE id != ?", (UNASSIGNED_CHILD_ID,)).fetchone()["n"],
            "artworks": con.execute(f"SELECT COUNT(*) AS n FROM artworks WHERE {ACTIVE_ARTWORK_SQL}").fetchone()["n"],
            "unassigned": con.execute(
                f"SELECT COUNT(*) AS n FROM artworks WHERE {ACTIVE_ARTWORK_SQL} AND child_id = ?",
                (UNASSIGNED_CHILD_ID,),
            ).fetchone()["n"],
            "untagged": con.execute(
                f"""
                SELECT COUNT(*) AS n
                FROM artworks
                WHERE {ACTIVE_ARTWORK_SQL}
                  AND NOT EXISTS (
                    SELECT 1 FROM artwork_tags at_untagged
                    WHERE at_untagged.artwork_id = artworks.id
                  )
                """
            ).fetchone()["n"],
            "pending": con.execute(f"SELECT COUNT(*) AS n FROM artworks WHERE {ACTIVE_ARTWORK_SQL} AND ai_status = 'pending'").fetchone()["n"],
            "processing": con.execute(f"SELECT COUNT(*) AS n FROM artworks WHERE {ACTIVE_ARTWORK_SQL} AND ai_status = 'processing'").fetchone()["n"],
            "failed": con.execute(f"SELECT COUNT(*) AS n FROM artworks WHERE {ACTIVE_ARTWORK_SQL} AND ai_status = 'failed'").fetchone()["n"],
            "completed": con.execute(f"SELECT COUNT(*) AS n FROM artworks WHERE {ACTIVE_ARTWORK_SQL} AND ai_status = 'completed'").fetchone()["n"],
            "unprocessed": con.execute(f"SELECT COUNT(*) AS n FROM artworks WHERE {ACTIVE_ARTWORK_SQL} AND {UNPROCESSED_ARTWORK_SQL}").fetchone()["n"],
            "trash": con.execute("SELECT COUNT(*) AS n FROM artworks WHERE deleted_at IS NOT NULL AND deleted_at != ''").fetchone()["n"],
        }
        latest = artwork_query(con)[:8]
        revision_row = con.execute("SELECT MAX(updated_at) AS revision FROM artworks").fetchone()
        processor_rows = con.execute(
            "SELECT status, COUNT(*) AS n FROM processor_jobs GROUP BY status"
        ).fetchall()
    processor = {row["status"]: row["n"] for row in processor_rows}
    processor["worker_active"] = _processor_worker_active
    return {
        "counts": counts,
        "latest": latest,
        "revision": revision_row["revision"] if revision_row else None,
        "processor": processor,
    }


@app.get("/api/children")
def list_children() -> list[dict[str, Any]]:
    with connect() as con:
        rows = con.execute(
            """
            SELECT children.*, COUNT(artworks.id) AS count
            FROM children
            LEFT JOIN artworks ON artworks.child_id = children.id AND (artworks.deleted_at IS NULL OR artworks.deleted_at = '')
            WHERE children.id != ?
            GROUP BY children.id
            ORDER BY children.name
            """,
            (UNASSIGNED_CHILD_ID,),
        ).fetchall()
        return rows_to_dicts(rows)


@app.post("/api/children")
def add_child(name: str = Form(...), birth_date: str = Form("")) -> dict[str, Any]:
    with connect() as con:
        child = get_or_create_child(con, name, birth_date.strip() or None)
        con.commit()
        return child


@app.patch("/api/children/{child_id}")
async def update_child(child_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    name = (payload.get("name") or "").strip()
    birth_date = (payload.get("birth_date") or "").strip()
    if not name and "name" in payload:
        raise HTTPException(status_code=400, detail="Child name cannot be empty")
    with connect() as con:
        row = con.execute("SELECT * FROM children WHERE id = ?", (child_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Child not found")
        updates: dict[str, Any] = {}
        if name:
            duplicate = con.execute(
                "SELECT id FROM children WHERE lower(name) = lower(?) AND id != ?",
                (name, child_id),
            ).fetchone()
            if duplicate:
                raise HTTPException(status_code=409, detail="A child with this name already exists")
            updates["name"] = name
        if "birth_date" in payload:
            updates["birth_date"] = birth_date or None
        if updates:
            fields = ", ".join([f"{key} = ?" for key in updates])
            con.execute(
                f"UPDATE children SET {fields}, updated_at = ? WHERE id = ?",
                (*updates.values(), now_iso(), child_id),
            )
        con.commit()
        updated = con.execute("SELECT * FROM children WHERE id = ?", (child_id,)).fetchone()
        return dict(updated)


@app.delete("/api/children/{child_id}")
def delete_child(child_id: str) -> dict[str, Any]:
    if child_id == UNASSIGNED_CHILD_ID:
        raise HTTPException(status_code=400, detail="Unassigned cannot be deleted")
    with connect() as con:
        ensure_unassigned_child(con)
        row = con.execute("SELECT id FROM children WHERE id = ?", (child_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Child not found")
        ts = now_iso()
        count = con.execute(
            f"SELECT COUNT(*) FROM artworks WHERE child_id = ? AND {ACTIVE_ARTWORK_SQL}",
            (child_id,),
        ).fetchone()[0]
        con.execute(
            "UPDATE artworks SET child_id = ?, updated_at = ? WHERE child_id = ?",
            (UNASSIGNED_CHILD_ID, ts, child_id),
        )
        con.execute(
            "UPDATE batches SET child_id = ?, updated_at = ? WHERE child_id = ?",
            (UNASSIGNED_CHILD_ID, ts, child_id),
        )
        con.execute(
            "UPDATE projects SET person_id = ?, updated_at = ? WHERE person_id = ?",
            (UNASSIGNED_CHILD_ID, ts, child_id),
        )
        con.execute("DELETE FROM children WHERE id = ?", (child_id,))
        con.commit()
    return {"deleted": True, "child_id": child_id, "unassigned": count}


@app.get("/api/batches")
def list_batches(child_id: str | None = None) -> list[dict[str, Any]]:
    with connect() as con:
        if child_id:
            rows = con.execute(
                """
                SELECT batches.*, COUNT(artworks.id) AS artwork_count
                FROM batches
                LEFT JOIN artworks ON artworks.batch_id = batches.id AND (artworks.deleted_at IS NULL OR artworks.deleted_at = '')
                WHERE batches.child_id = ?
                GROUP BY batches.id
                ORDER BY batches.created_at DESC
                """,
                (child_id,),
            ).fetchall()
        else:
            rows = con.execute(
                """
                SELECT batches.*, children.name AS child_name, COUNT(artworks.id) AS artwork_count
                FROM batches
                LEFT JOIN children ON children.id = batches.child_id
                LEFT JOIN artworks ON artworks.batch_id = batches.id AND (artworks.deleted_at IS NULL OR artworks.deleted_at = '')
                GROUP BY batches.id
                ORDER BY batches.created_at DESC
                """
            ).fetchall()
        return rows_to_dicts(rows)


@app.get("/api/facets")
def facets() -> dict[str, Any]:
    with connect() as con:
        smart = [
            {"id": "all", "name": "All", "count": count_where(con, ACTIVE_ARTWORK_SQL)},
            {
                "id": "unassigned",
                "name": "Unassigned",
                "count": count_where(con, f"{ACTIVE_ARTWORK_SQL} AND child_id = ?", (UNASSIGNED_CHILD_ID,)),
            },
            {
                "id": "untagged",
                "name": "Untagged",
                "count": count_where(
                    con,
                    f"""{ACTIVE_ARTWORK_SQL}
                    AND NOT EXISTS (
                      SELECT 1 FROM artwork_tags at_untagged
                      WHERE at_untagged.artwork_id = artworks.id
                    )""",
                ),
            },
            {"id": "trash", "name": "Trash", "count": count_where(con, "deleted_at IS NOT NULL AND deleted_at != ''")},
            {
                "id": "unreviewed",
                "name": "Review Needed",
                "count": count_where(con, f"{ACTIVE_ARTWORK_SQL} AND (ai_status != 'completed' OR title IS NULL OR title = '')"),
            },
            {"id": "favorites", "name": "Favorites", "count": count_where(con, f"{ACTIVE_ARTWORK_SQL} AND is_favorite = 1")},
            {"id": "representative", "name": "Representative", "count": count_where(con, f"{ACTIVE_ARTWORK_SQL} AND is_representative = 1")},
            {
                "id": "needs_quote",
                "name": "Needs Child Quote",
                "count": count_where(con, f"{ACTIVE_ARTWORK_SQL} AND (child_quote IS NULL OR trim(child_quote) = '')"),
            },
        ]
        children = rows_to_dicts(
            con.execute(
                """
                SELECT children.id, children.name, COUNT(artworks.id) AS count
                FROM children
                LEFT JOIN artworks ON artworks.child_id = children.id AND (artworks.deleted_at IS NULL OR artworks.deleted_at = '')
                WHERE children.id != ?
                GROUP BY children.id
                ORDER BY children.name
                """,
                (UNASSIGNED_CHILD_ID,),
            ).fetchall()
        )
        years = rows_to_dicts(
            con.execute(
                """
                SELECT substr(COALESCE(artworks.artwork_date, artworks.created_at), 1, 4) AS year,
                       COUNT(*) AS count
                FROM artworks
                WHERE artworks.deleted_at IS NULL OR artworks.deleted_at = ''
                GROUP BY year
                ORDER BY year DESC
                """
            ).fetchall()
        )
        batches = rows_to_dicts(
            con.execute(
                """
                SELECT batches.id, batches.name, children.name AS child_name, COUNT(artworks.id) AS count
                FROM batches
                LEFT JOIN children ON children.id = batches.child_id
                LEFT JOIN artworks ON artworks.batch_id = batches.id AND (artworks.deleted_at IS NULL OR artworks.deleted_at = '')
                GROUP BY batches.id
                ORDER BY batches.created_at DESC
                LIMIT 40
                """
            ).fetchall()
        )
        tag_rows = rows_to_dicts(
            con.execute(
                """
                SELECT tags.name, tags.type, COUNT(artwork_tags.artwork_id) AS count
                FROM tags
                JOIN artwork_tags ON artwork_tags.tag_id = tags.id
                JOIN artworks ON artworks.id = artwork_tags.artwork_id
                WHERE (tags.type != 'custom' OR artwork_tags.source = 'manual')
                  AND (artworks.deleted_at IS NULL OR artworks.deleted_at = '')
                GROUP BY tags.id
                HAVING count > 0
                ORDER BY tags.type, count DESC, tags.name
                """
            ).fetchall()
        )
    tags_by_type: dict[str, list[dict[str, Any]]] = {}
    for row in tag_rows:
        tags_by_type.setdefault(row["type"], []).append(row)
    return {
        "smart": smart,
        "children": children,
        "years": years,
        "batches": batches,
        "tags": {key: value[:30] for key, value in tags_by_type.items()},
    }


@app.get("/api/tags")
def list_tags(type: str | None = None, source: str | None = None) -> list[dict[str, Any]]:
    where = []
    params: list[Any] = []
    if type:
        where.append("tags.type = ?")
        params.append(type)
    if source:
        where.append("artwork_tags.source = ?")
        params.append(source)
    clause = "WHERE " + " AND ".join(where) if where else ""
    with connect() as con:
        rows = con.execute(
            f"""
            SELECT tags.id, tags.name, tags.type, artwork_tags.source,
                   COUNT(DISTINCT artwork_tags.artwork_id) AS count
            FROM tags
            LEFT JOIN artwork_tags ON artwork_tags.tag_id = tags.id
            {clause}
            GROUP BY tags.id, artwork_tags.source
            ORDER BY tags.type, artwork_tags.source, count DESC, tags.name
            """,
            params,
        ).fetchall()
        return rows_to_dicts(rows)


@app.patch("/api/tags/{tag_id}")
async def update_tag(tag_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    new_name = normalize_tag(str(payload.get("name") or ""))
    if not new_name:
        raise HTTPException(status_code=400, detail="Tag name cannot be empty")
    with connect() as con:
        row = con.execute("SELECT * FROM tags WHERE id = ?", (tag_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Tag not found")
        existing = con.execute(
            "SELECT * FROM tags WHERE name = ? AND type = ? AND id != ?",
            (new_name, row["type"], tag_id),
        ).fetchone()
        if existing:
            links = con.execute(
                "SELECT artwork_id, confidence, source FROM artwork_tags WHERE tag_id = ?",
                (tag_id,),
            ).fetchall()
            for link in links:
                con.execute(
                    """
                    INSERT OR IGNORE INTO artwork_tags (artwork_id, tag_id, confidence, source)
                    VALUES (?, ?, ?, ?)
                    """,
                    (link["artwork_id"], existing["id"], link["confidence"], link["source"]),
                )
            con.execute("DELETE FROM artwork_tags WHERE tag_id = ?", (tag_id,))
            con.execute("DELETE FROM tags WHERE id = ?", (tag_id,))
            if links:
                placeholders = ",".join(["?"] * len(links))
                con.execute(
                    f"UPDATE artworks SET updated_at = ? WHERE id IN ({placeholders})",
                    (now_iso(), *[link["artwork_id"] for link in links]),
                )
            con.commit()
            return dict(existing)
        linked = [item["artwork_id"] for item in con.execute(
            "SELECT artwork_id FROM artwork_tags WHERE tag_id = ?",
            (tag_id,),
        ).fetchall()]
        con.execute("UPDATE tags SET name = ? WHERE id = ?", (new_name, tag_id))
        if linked:
            placeholders = ",".join(["?"] * len(linked))
            con.execute(
                f"UPDATE artworks SET updated_at = ? WHERE id IN ({placeholders})",
                (now_iso(), *linked),
            )
        con.commit()
        updated = con.execute("SELECT * FROM tags WHERE id = ?", (tag_id,)).fetchone()
        return dict(updated)


@app.post("/api/tags/{tag_id}/promote")
def promote_tag(tag_id: str) -> dict[str, Any]:
    with connect() as con:
        row = con.execute("SELECT * FROM tags WHERE id = ?", (tag_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Tag not found")
        con.execute("UPDATE artwork_tags SET source = 'manual' WHERE tag_id = ?", (tag_id,))
        con.commit()
        return dict(row)


@app.delete("/api/tags/{tag_id}")
def delete_tag(tag_id: str) -> dict[str, Any]:
    with connect() as con:
        row = con.execute("SELECT id FROM tags WHERE id = ?", (tag_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Tag not found")
        linked = [item["artwork_id"] for item in con.execute(
            "SELECT artwork_id FROM artwork_tags WHERE tag_id = ?",
            (tag_id,),
        ).fetchall()]
        con.execute("DELETE FROM artwork_tags WHERE tag_id = ?", (tag_id,))
        con.execute("DELETE FROM tags WHERE id = ?", (tag_id,))
        if linked:
            placeholders = ",".join(["?"] * len(linked))
            con.execute(
                f"UPDATE artworks SET updated_at = ? WHERE id IN ({placeholders})",
                (now_iso(), *linked),
            )
        con.commit()
    return {"deleted": True, "tag_id": tag_id}


@app.delete("/api/artworks/{artwork_id}/tags")
def remove_artwork_tag(artwork_id: str, payload: dict[str, Any] = {}) -> dict[str, Any]:
    name = normalize_tag((payload.get("name") or "").strip())
    if not name:
        raise HTTPException(status_code=400, detail="Tag name required")
    tag_type = (payload.get("type") or "custom").strip()
    with connect() as con:
        row = con.execute("SELECT id FROM artworks WHERE id = ?", (artwork_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artwork not found")
        tag = con.execute("SELECT id FROM tags WHERE name = ? AND type = ?", (name, tag_type)).fetchone()
        if tag:
            con.execute("DELETE FROM artwork_tags WHERE artwork_id = ? AND tag_id = ?", (artwork_id, tag["id"]))
            con.execute("UPDATE artworks SET updated_at = ? WHERE id = ?", (now_iso(), artwork_id))
            con.commit()
    return {"deleted": True}


@app.post("/api/artworks/{artwork_id}/tags")
def add_artwork_tag(artwork_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    name = normalize_tag((payload.get("name") or "").strip())
    if not name:
        raise HTTPException(status_code=400, detail="Tag name required")
    tag_type = (payload.get("type") or "custom").strip()
    source = (payload.get("source") or "manual").strip()
    with connect() as con:
        row = con.execute("SELECT id FROM artworks WHERE id = ?", (artwork_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artwork not found")
        upsert_tags(con, artwork_id, tag_type, [name], source)
        con.execute("UPDATE artworks SET updated_at = ? WHERE id = ?", (now_iso(), artwork_id))
        con.commit()
    return {"added": True, "name": name, "type": tag_type, "source": source}


@app.post("/api/import")
def import_images(
    background_tasks: BackgroundTasks,
    child_name: str = Form(...),
    batch_name: str = Form(""),
    artwork_date: str = Form(""),
    date_precision: str = Form(""),
    date_note: str = Form(""),
    child_age_months: str = Form(""),
    work_type: str = Form("paper"),
    auto_analyze: str = Form("true"),
    files: list[UploadFile] = File(...),
) -> dict[str, Any]:
    if not files:
        raise HTTPException(status_code=400, detail="No files uploaded")
    imported: list[dict[str, Any]] = []
    age_months = parse_int(child_age_months)
    with connect() as con:
        child = get_or_create_child(con, child_name)
        effective_artwork_date = artwork_date or date_from_child_age(child.get("birth_date"), age_months) or ""
        batch = create_batch(
            con,
            child["id"],
            batch_name,
            effective_artwork_date or None,
            date_note or None,
            date_precision or None,
            age_months,
            work_type,
        )
        con.execute(
            "INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?)",
            ("last_child_name", child_name.strip()),
        )
        con.execute(
            "INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?)",
            ("last_child_id", child["id"]),
        )
        for file in files:
            imported.append(save_upload(
                con,
                file,
                child["id"],
                batch["id"],
                effective_artwork_date or None,
                date_note or None,
                date_precision or None,
                age_months,
                work_type,
            ))
        con.commit()
    for item in imported:
        background_tasks.add_task(prepare_artwork_display, item["id"])
    if auto_analyze.lower() == "true":
        start_ai_queue_worker()
    return {"child": child, "batch": batch, "imported": imported, "auto_analyze": auto_analyze.lower() == "true"}


@app.get("/api/artworks")
def list_artworks(
    request: Request,
    child_id: str | None = None,
    batch_id: str | None = None,
    status: str | None = None,
    q: str | None = None,
    smart: str | None = None,
    tag: str | None = None,
    tag_type: str | None = None,
    year: str | None = None,
    absolute_urls: bool = False,
    include_deleted: bool = False,
) -> list[dict[str, Any]]:
    with connect() as con:
        return artwork_query(
            con,
            child_id=child_id,
            batch_id=batch_id,
            status=status,
            q=q,
            smart=smart,
            tag=tag,
            tag_type=tag_type,
            year=year,
            base_url=str(request.base_url) if absolute_urls else None,
            include_deleted=include_deleted,
        )


@app.get("/api/artworks/{artwork_id}")
def get_artwork(artwork_id: str, request: Request, absolute_urls: bool = False) -> dict[str, Any]:
    with connect() as con:
        row = con.execute(
            """
            SELECT artworks.*, children.name AS child_name, batches.name AS batch_name
            FROM artworks
            LEFT JOIN children ON children.id = artworks.child_id
            LEFT JOIN batches ON batches.id = artworks.batch_id
            WHERE artworks.id = ?
            """,
            (artwork_id,),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artwork not found")
        return hydrate_artwork(con, row, base_url=str(request.base_url) if absolute_urls else None)


@app.patch("/api/artworks/{artwork_id}")
async def update_artwork(artwork_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    allowed = {
        "title",
        "description",
        "long_description",
        "child_id",
        "child_quote",
        "parent_note",
        "artwork_date",
        "date_precision",
        "date_note",
        "child_age_months",
        "work_type",
        "medium",
        "physical_status",
        "is_favorite",
        "is_representative",
    }
    updates = {key: payload[key] for key in allowed if key in payload}
    manual_tags = payload.get("manual_tags")
    with connect() as con:
        row = con.execute("SELECT id FROM artworks WHERE id = ?", (artwork_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artwork not found")
        if "child_id" in updates:
            updates["child_id"] = store_child_id(updates["child_id"])
            ensure_unassigned_child(con)
            child = con.execute("SELECT id FROM children WHERE id = ?", (updates["child_id"],)).fetchone()
            if not child:
                raise HTTPException(status_code=400, detail="Child not found")
        if updates:
            fields = ", ".join([f"{key} = ?" for key in updates])
            values = list(updates.values()) + [now_iso(), artwork_id]
            con.execute(f"UPDATE artworks SET {fields}, updated_at = ? WHERE id = ?", values)
        if isinstance(manual_tags, list):
            con.execute(
                """
                DELETE FROM artwork_tags
                WHERE artwork_id = ?
                  AND source = 'manual'
                  AND tag_id IN (SELECT id FROM tags WHERE type = 'custom')
                """,
                (artwork_id,),
            )
            upsert_tags(con, artwork_id, "custom", manual_tags, "manual")
        con.commit()
        updated = con.execute(
            """
            SELECT artworks.*, children.name AS child_name, batches.name AS batch_name
            FROM artworks
            LEFT JOIN children ON children.id = artworks.child_id
            LEFT JOIN batches ON batches.id = artworks.batch_id
            WHERE artworks.id = ?
            """,
            (artwork_id,),
        ).fetchone()
        return hydrate_artwork(con, updated)


@app.delete("/api/artworks/{artwork_id}")
def delete_artwork(artwork_id: str) -> dict[str, Any]:
    with connect() as con:
        row = con.execute("SELECT id FROM artworks WHERE id = ?", (artwork_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artwork not found")
        con.execute(
            "UPDATE artworks SET deleted_at = ?, updated_at = ? WHERE id = ?",
            (now_iso(), now_iso(), artwork_id),
        )
        con.commit()
    return {"deleted": True, "trashed": True, "id": artwork_id}


@app.post("/api/artworks/{artwork_id}/restore")
def restore_artwork(artwork_id: str) -> dict[str, Any]:
    with connect() as con:
        row = con.execute("SELECT id FROM artworks WHERE id = ?", (artwork_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artwork not found")
        con.execute(
            "UPDATE artworks SET deleted_at = NULL, updated_at = ? WHERE id = ?",
            (now_iso(), artwork_id),
        )
        con.commit()
    return {"restored": True, "id": artwork_id}


@app.post("/api/artworks/{artwork_id}/analyze")
def analyze_one(artwork_id: str, background_tasks: BackgroundTasks) -> dict[str, Any]:
    with connect() as con:
        exists = con.execute("SELECT id FROM artworks WHERE id = ?", (artwork_id,)).fetchone()
        if not exists:
            raise HTTPException(status_code=404, detail="Artwork not found")
    background_tasks.add_task(analyze_artwork, artwork_id)
    return {"queued": True, "artwork_id": artwork_id}


@app.post("/api/artworks/{artwork_id}/process")
async def process_one(artwork_id: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    payload = payload or {}
    mode = (payload.get("mode") or "auto").strip()
    crop = payload.get("crop") if isinstance(payload.get("crop"), dict) else None
    perspective = payload.get("perspective") if isinstance(payload.get("perspective"), list) else None
    rotate = int(payload.get("rotate") or 0)
    source = (payload.get("source") or "original").strip()
    enhance = bool(payload.get("enhance") or False)
    process_result = process_artwork_image(
        artwork_id,
        mode=mode,
        crop=crop,
        perspective=perspective,
        rotate=rotate,
        source=source,
        enhance=enhance,
    )
    make_thumbnail(artwork_id)
    with connect() as con:
        row = con.execute(
            """
            SELECT artworks.*, children.name AS child_name, batches.name AS batch_name
            FROM artworks
            LEFT JOIN children ON children.id = artworks.child_id
            LEFT JOIN batches ON batches.id = artworks.batch_id
            WHERE artworks.id = ?
            """,
            (artwork_id,),
        ).fetchone()
        return {"result": process_result, "work": hydrate_artwork(con, row)}


@app.post("/api/batches/{batch_id}/analyze")
def analyze_batch(batch_id: str, background_tasks: BackgroundTasks) -> dict[str, Any]:
    with connect() as con:
        rows = con.execute("SELECT id FROM artworks WHERE batch_id = ?", (batch_id,)).fetchall()
    for row in rows:
        background_tasks.add_task(analyze_artwork, row["id"])
    return {"queued": len(rows), "batch_id": batch_id}


@app.get("/api/ai/queue")
def ai_queue_status() -> dict[str, Any]:
    return _queue_status_payload()


@app.post("/api/ai/queue/pause")
def pause_queue() -> dict[str, bool]:
    _ai_queue_paused.set()
    return {"paused": True}


@app.post("/api/ai/queue/resume")
def resume_queue() -> dict[str, bool]:
    _ai_queue_paused.clear()
    return {"paused": False}


@app.post("/api/ai/queue/process-now")
def process_now(background_tasks: BackgroundTasks) -> dict[str, Any]:
    with connect() as con:
        queued = con.execute(
            f"SELECT COUNT(*) FROM artworks WHERE {ACTIVE_ARTWORK_SQL} AND {UNPROCESSED_ARTWORK_SQL} AND ai_status != 'processing'"
        ).fetchone()[0]
    started = start_ai_queue_worker()
    return {"queued": queued, "started": started}


def _purge_expired_ios_tokens() -> None:
    now = time.time()
    expired = [
        token for token, session in _ios_pairing_sessions.items()
        if now - session["created_at"] > int(session.get("ttl", IOS_PAIRING_TOKEN_TTL))
    ]
    for token in expired:
        _ios_pairing_sessions.pop(token, None)
    with connect() as con:
        con.execute(
            "DELETE FROM ios_pairing_tokens WHERE ? - created_at > ttl",
            (now,),
        )
        con.commit()


def _persist_ios_pairing_token(token: str, session: dict[str, Any]) -> None:
    with connect() as con:
        con.execute(
            """
            INSERT OR REPLACE INTO ios_pairing_tokens
              (token, host, host_name, port, base_url, created_at, last_seen_at, ttl)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                token,
                session["host"],
                session["host_name"],
                int(session["port"]),
                session["base_url"],
                float(session["created_at"]),
                session.get("last_seen_at"),
                int(session.get("ttl", IOS_PAIRING_TOKEN_TTL)),
            ),
        )
        con.commit()


def _load_ios_pairing_token(token: str) -> dict[str, Any] | None:
    with connect() as con:
        row = con.execute("SELECT * FROM ios_pairing_tokens WHERE token = ?", (token,)).fetchone()
    if not row:
        return None
    session = dict(row)
    session["created_at"] = float(session["created_at"])
    session["ttl"] = int(session.get("ttl") or IOS_PAIRING_TOKEN_TTL)
    session["port"] = int(session.get("port") or server_port())
    return session


def _require_ios_pairing(request: Request, form_token: str | None = None, mark_seen: bool = True) -> dict[str, Any]:
    _purge_expired_ios_tokens()
    auth = request.headers.get("authorization", "")
    bearer = auth[7:].strip() if auth.lower().startswith("bearer ") else None
    token = form_token or request.headers.get("x-volio-token") or bearer or request.query_params.get("token")
    if token and token not in _ios_pairing_sessions:
        persisted = _load_ios_pairing_token(token)
        if persisted:
            _ios_pairing_sessions[token] = persisted
    if not token or token not in _ios_pairing_sessions:
        raise HTTPException(status_code=401, detail="Pair Volio with Volio Desktop again.")
    session = _ios_pairing_sessions[token]
    if time.time() - session["created_at"] > int(session.get("ttl", IOS_PAIRING_TOKEN_TTL)):
        _ios_pairing_sessions.pop(token, None)
        with connect() as con:
            con.execute("DELETE FROM ios_pairing_tokens WHERE token = ?", (token,))
            con.commit()
        raise HTTPException(status_code=401, detail="Pairing expired. Scan the QR code again.")
    if mark_seen:
        session["last_seen_at"] = now_iso()
        _persist_ios_pairing_token(token, session)
    return session


def _queue_status_payload() -> dict[str, Any]:
    with connect() as con:
        pending = con.execute(
            f"SELECT COUNT(*) FROM artworks WHERE {ACTIVE_ARTWORK_SQL} AND {UNPROCESSED_ARTWORK_SQL} AND ai_status != 'processing'"
        ).fetchone()[0]
        processing = con.execute(f"SELECT COUNT(*) FROM artworks WHERE {ACTIVE_ARTWORK_SQL} AND ai_status = 'processing'").fetchone()[0]
        failed = con.execute(f"SELECT COUNT(*) FROM artworks WHERE {ACTIVE_ARTWORK_SQL} AND ai_status = 'failed'").fetchone()[0]
    now = datetime.now()
    return {
        "pending": pending,
        "processing": processing,
        "failed": failed,
        "unprocessed": pending,
        "paused": _ai_queue_paused.is_set(),
        "can_process": _can_process(),
        "worker_active": _ai_worker_active,
        "idle_seconds": int(time.time() - _last_request_at),
        "idle_timeout": AI_IDLE_TIMEOUT,
        "window": AI_WINDOW or None,
        "in_window": _in_window(AI_WINDOW),
        "now": now.isoformat(timespec="minutes"),
    }


def _ollama_status() -> dict[str, Any]:
    try:
        response = requests.get(f"{OLLAMA_URL}/api/tags", timeout=2)
        ok = response.ok
    except Exception:
        ok = False
    return {
        "url": OLLAMA_URL,
        "model": OLLAMA_MODEL,
        "ok": ok,
    }


@app.post("/api/ios/pairing/session")
def create_ios_pairing_session(request: Request) -> dict[str, Any]:
    ip = lan_ip()
    if not ip:
        raise HTTPException(status_code=503, detail="Cannot detect LAN IP. Connect to Wi-Fi first.")
    token = secrets.token_urlsafe(24)
    ttl = IOS_PAIRING_TOKEN_TTL
    host_name = socket.gethostname()
    port = server_port()
    base_url = f"http://{ip}:{port}"
    _purge_expired_ios_tokens()
    session = {
        "host": ip,
        "host_name": host_name,
        "port": port,
        "base_url": base_url,
        "created_at": time.time(),
        "last_seen_at": None,
        "ttl": ttl,
    }
    _ios_pairing_sessions[token] = session
    _persist_ios_pairing_token(token, session)
    pairing_payload = {
        "type": "volio-ios-pairing",
        "version": 1,
        "app": "Volio Desktop",
        "base_url": base_url,
        "host": ip,
        "host_name": host_name,
        "port": port,
        "token": token,
    }
    pairing_url = "volio://pair?" + urlencode({
        "base_url": base_url,
        "token": token,
        "host_name": host_name,
    })
    qr_bytes = io.BytesIO()
    qr_img = qrcode.make(pairing_url, box_size=8, border=2)
    qr_img.save(qr_bytes, format="PNG")
    qr_b64 = base64.b64encode(qr_bytes.getvalue()).decode("ascii")
    return {
        **pairing_payload,
        "pairing_url": pairing_url,
        "local_url": str(request.base_url).rstrip("/"),
        "qr_data_url": f"data:image/png;base64,{qr_b64}",
        "expires_in": ttl,
    }


@app.get("/api/ios/pairing/session/{token}")
def get_ios_pairing_session(token: str, request: Request) -> dict[str, Any]:
    session = _require_ios_pairing(request, form_token=token, mark_seen=False)
    remaining = int(session.get("ttl", IOS_PAIRING_TOKEN_TTL)) - int(time.time() - session["created_at"])
    return {
        "valid": True,
        "host": session["host"],
        "host_name": session["host_name"],
        "port": session["port"],
        "base_url": session["base_url"],
        "expires_in": max(0, remaining),
        "last_seen_at": session.get("last_seen_at"),
    }


@app.get("/api/ios/bootstrap")
def ios_bootstrap(request: Request) -> dict[str, Any]:
    session = _require_ios_pairing(request)
    base_url = str(request.base_url)
    with connect() as con:
        children = rows_to_dicts(
            con.execute("SELECT * FROM children WHERE id != ? ORDER BY name", (UNASSIGNED_CHILD_ID,)).fetchall()
        )
        settings = current_settings(con)
        latest = artwork_query(con, base_url=base_url)
    return {
        "desktop": {
            "name": "Volio Desktop",
            "host": session["host"],
            "host_name": session["host_name"],
            "base_url": session["base_url"],
        },
        "settings": settings,
        "ollama": _ollama_status(),
        "queue": _queue_status_payload(),
        "children": children,
        "artworks": latest,
    }


@app.post("/api/ios/children")
def ios_add_child(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    _require_ios_pairing(request)
    name = (payload.get("name") or "").strip()
    birth_date = (payload.get("birth_date") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Child name cannot be empty")
    with connect() as con:
        child = get_or_create_child(con, name, birth_date or None)
        con.commit()
        return child


@app.get("/api/ios/artworks")
def ios_list_artworks(
    request: Request,
    child_id: str | None = None,
    q: str | None = None,
    year: str | None = None,
) -> list[dict[str, Any]]:
    _require_ios_pairing(request)
    with connect() as con:
        return artwork_query(
            con,
            child_id=child_id,
            q=q,
            year=year,
            base_url=str(request.base_url),
        )


@app.get("/api/ios/artworks/{artwork_id}")
def ios_get_artwork(artwork_id: str, request: Request) -> dict[str, Any]:
    _require_ios_pairing(request)
    with connect() as con:
        row = con.execute(
            """
            SELECT artworks.*, children.name AS child_name, batches.name AS batch_name
            FROM artworks
            LEFT JOIN children ON children.id = artworks.child_id
            LEFT JOIN batches ON batches.id = artworks.batch_id
            WHERE artworks.id = ?
            """,
            (artwork_id,),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Artwork not found")
        return hydrate_artwork(con, row, base_url=str(request.base_url))


@app.patch("/api/ios/artworks/{artwork_id}")
async def ios_update_artwork(artwork_id: str, request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    _require_ios_pairing(request)
    return await update_artwork(artwork_id, payload)


@app.delete("/api/ios/artworks/{artwork_id}")
def ios_delete_artwork(artwork_id: str, request: Request) -> dict[str, Any]:
    _require_ios_pairing(request)
    return delete_artwork(artwork_id)


@app.post("/api/ios/artworks/{artwork_id}/analyze")
def ios_analyze_one(artwork_id: str, request: Request, background_tasks: BackgroundTasks) -> dict[str, Any]:
    _require_ios_pairing(request)
    return analyze_one(artwork_id, background_tasks)


@app.get("/api/ios/ai/queue")
def ios_ai_queue_status(request: Request) -> dict[str, Any]:
    _require_ios_pairing(request)
    return _queue_status_payload()


@app.get("/api/ios/process/jobs")
def ios_process_jobs(request: Request) -> dict[str, Any]:
    _require_ios_pairing(request)
    with connect() as con:
        rows = con.execute(
            """
            SELECT *
            FROM processor_jobs
            ORDER BY created_at DESC
            LIMIT 100
            """
        ).fetchall()
        counts = con.execute(
            """
            SELECT status, COUNT(*) AS count
            FROM processor_jobs
            GROUP BY status
            """
        ).fetchall()
    return {
        "jobs": [processor_job_payload(row) for row in rows],
        "counts": {row["status"]: row["count"] for row in counts},
        "worker_active": _processor_worker_active,
    }


@app.post("/api/ios/process/jobs")
def ios_create_process_job(
    request: Request,
    token: str = Form(""),
    work_id: str = Form(""),
    work_type: str = Form("paper"),
    title: str = Form(""),
    created_around_kind: str = Form(""),
    created_around_label: str = Form(""),
    created_around_year: str = Form(""),
    created_around_month: str = Form(""),
    created_around_season: str = Form(""),
    created_around_age_months: str = Form(""),
    file: UploadFile = File(...),
) -> dict[str, Any]:
    _require_ios_pairing(request, form_token=token or None)
    if not work_id.strip():
        raise HTTPException(status_code=400, detail="work_id is required")
    original_name = file.filename or f"{work_id}.jpg"
    ext = Path(original_name).suffix.lower() or ".jpg"
    if ext == ".jpeg":
        ext = ".jpg"
    if ext not in SUPPORTED_EXTS:
        raise HTTPException(status_code=400, detail=f"Unsupported file type: {original_name}")
    job_id = str(uuid.uuid4())
    safe_name = slug_text(work_id, "work")
    job_dir = PROCESSOR_JOBS_DIR / job_id
    job_dir.mkdir(parents=True, exist_ok=True)
    dest = job_dir / f"{safe_name}.jpg"
    with dest.open("wb") as out:
        shutil.copyfileobj(file.file, out)
    # Validate and normalize the image so the worker gets predictable RGB JPEG/WEBP input.
    image = open_uploaded_image(dest)
    image.thumbnail((1800, 1800))
    image.save(dest, "JPEG", quality=90)
    ts = now_iso()
    rel_path = str(dest.relative_to(ROOT))
    with connect() as con:
        con.execute(
            """
            INSERT INTO processor_jobs (
              id, token_hint, source, work_id, work_type, title,
              created_around_kind, created_around_label, created_around_year,
              created_around_month, created_around_season, created_around_age_months,
              file_path, status, created_at, updated_at
            )
            VALUES (?, ?, 'ios', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?, ?)
            """,
            (
                job_id,
                (token or request.headers.get("x-volio-token") or "")[:8],
                work_id,
                work_type or "paper",
                title or None,
                created_around_kind or None,
                created_around_label or None,
                parse_int(created_around_year),
                parse_int(created_around_month),
                created_around_season or None,
                parse_int(created_around_age_months),
                rel_path,
                ts,
                ts,
            ),
        )
        con.commit()
        row = con.execute("SELECT * FROM processor_jobs WHERE id = ?", (job_id,)).fetchone()
    start_processor_worker()
    return processor_job_payload(row)


@app.get("/api/ios/process/jobs/{job_id}")
def ios_get_process_job(job_id: str, request: Request) -> dict[str, Any]:
    _require_ios_pairing(request)
    with connect() as con:
        row = con.execute("SELECT * FROM processor_jobs WHERE id = ?", (job_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Processing job not found")
    return processor_job_payload(row)


@app.post("/api/ios/process/jobs/{job_id}/retry")
def ios_retry_process_job(job_id: str, request: Request) -> dict[str, Any]:
    _require_ios_pairing(request)
    with connect() as con:
        row = con.execute("SELECT * FROM processor_jobs WHERE id = ?", (job_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Processing job not found")
        con.execute(
            """
            UPDATE processor_jobs
            SET status = 'queued',
                error_message = NULL,
                updated_at = ?
            WHERE id = ?
            """,
            (now_iso(), job_id),
        )
        con.commit()
        row = con.execute("SELECT * FROM processor_jobs WHERE id = ?", (job_id,)).fetchone()
    start_processor_worker()
    return processor_job_payload(row)


@app.post("/api/ios/import")
def ios_import_images(
    request: Request,
    background_tasks: BackgroundTasks,
    token: str = Form(""),
    child_id: str = Form(""),
    child_name: str = Form(""),
    batch_name: str = Form(""),
    artwork_date: str = Form(""),
    date_precision: str = Form(""),
    date_note: str = Form(""),
    child_age_months: str = Form(""),
    client_work_id: str = Form(""),
    work_type: str = Form("paper"),
    auto_analyze: str = Form("true"),
    files: list[UploadFile] = File(...),
) -> dict[str, Any]:
    _require_ios_pairing(request, form_token=token or None)
    if not files:
        raise HTTPException(status_code=400, detail="No files uploaded")
    imported: list[dict[str, Any]] = []
    age_months = parse_int(child_age_months)
    with connect() as con:
        child = None
        if child_id:
            row = con.execute("SELECT * FROM children WHERE id = ?", (child_id,)).fetchone()
            child = row_to_dict(row)
        if not child:
            clean_name = child_name.strip() or "iPhone Import"
            child = get_or_create_child(con, clean_name)
        batch_label = batch_name.strip() or "iPhone Import"
        effective_artwork_date = artwork_date or date_from_child_age(child.get("birth_date"), age_months) or ""
        batch = create_batch(
            con,
            child["id"],
            batch_label,
            effective_artwork_date or None,
            date_note or None,
            date_precision or None,
            age_months,
            work_type,
        )
        set_pref(con, "last_child_name", child["name"])
        set_pref(con, "last_child_id", child["id"])
        for file in files:
            imported.append(save_upload(
                con,
                file,
                child["id"],
                batch["id"],
                effective_artwork_date or None,
                date_note or None,
                date_precision or None,
                age_months,
                work_type,
                client_work_id if len(files) == 1 else None,
            ))
        con.commit()
    for item in imported:
        background_tasks.add_task(prepare_artwork_display, item["id"])
    if auto_analyze.lower() == "true":
        start_ai_queue_worker()
    return {
        "child": child,
        "batch": batch,
        "imported": imported,
        "auto_analyze": auto_analyze.lower() == "true",
    }


def _purge_expired_tokens() -> None:
    now = time.time()
    expired = [
        k for k, v in _mobile_sessions.items()
        if now - v["created_at"] > int(v.get("ttl", MOBILE_TOKEN_TTL))
    ]
    for k in expired:
        _mobile_sessions.pop(k, None)


@app.post("/api/mobile/session")
def create_mobile_session(payload: dict[str, Any]) -> dict[str, Any]:
    ip = lan_ip()
    if not ip:
        raise HTTPException(status_code=503, detail="Cannot detect LAN IP. Connect to Wi-Fi first.")
    child_name = (payload.get("child_name") or "").strip() or "Mobile Import"
    with connect() as con:
        ttl = current_settings(con)["mobile_session_ttl_minutes"] * 60
    token = secrets.token_urlsafe(16)
    _purge_expired_tokens()
    _mobile_sessions[token] = {
        "child_name": child_name,
        "created_at": time.time(),
        "ttl": ttl,
        "uploaded_count": 0,
        "last_upload_at": None,
    }
    url = f"http://{ip}:{server_port()}/m/upload?t={token}"
    local_url = f"http://127.0.0.1:{server_port()}/m/upload?t={token}"
    qr_bytes = io.BytesIO()
    qr_img = qrcode.make(url, box_size=8, border=2)
    qr_img.save(qr_bytes, format="PNG")
    qr_b64 = base64.b64encode(qr_bytes.getvalue()).decode("ascii")
    return {
        "token": token,
        "url": url,
        "local_url": local_url,
        "host": ip,
        "port": server_port(),
        "qr_data_url": f"data:image/png;base64,{qr_b64}",
        "expires_in": ttl,
        "child_name": child_name,
        "uploaded_count": 0,
        "last_upload_at": None,
    }


@app.get("/api/mobile/session/{token}")
def get_mobile_session(token: str) -> dict[str, Any]:
    session = _mobile_sessions.get(token)
    if not session:
        raise HTTPException(status_code=404, detail="Session expired or invalid")
    ttl = int(session.get("ttl", MOBILE_TOKEN_TTL))
    remaining = ttl - int(time.time() - session["created_at"])
    if remaining <= 0:
        _mobile_sessions.pop(token, None)
        raise HTTPException(status_code=404, detail="Session expired")
    return {
        "valid": True,
        "child_name": session["child_name"],
        "expires_in": remaining,
        "uploaded_count": int(session.get("uploaded_count") or 0),
        "last_upload_at": session.get("last_upload_at"),
    }


@app.post("/api/mobile/upload")
def mobile_upload(
    background_tasks: BackgroundTasks,
    token: str = Form(...),
    files: list[UploadFile] = File(...),
) -> dict[str, Any]:
    session = _mobile_sessions.get(token)
    if not session:
        raise HTTPException(status_code=401, detail="Invalid or expired session. Scan the QR code again.")
    if time.time() - session["created_at"] > int(session.get("ttl", MOBILE_TOKEN_TTL)):
        _mobile_sessions.pop(token, None)
        raise HTTPException(status_code=401, detail="Session expired. Scan the QR code again.")
    if not files:
        raise HTTPException(status_code=400, detail="No files uploaded")
    child_name = session["child_name"]
    imported: list[dict[str, Any]] = []
    with connect() as con:
        child = get_or_create_child(con, child_name)
        batch = create_batch(con, child["id"], "Mobile Import", datetime.now().strftime("%Y-%m-%d"), "from phone")
        for file in files:
            imported.append(save_upload(con, file, child["id"], batch["id"], datetime.now().strftime("%Y-%m-%d"), "from phone"))
        con.commit()
    for item in imported:
        background_tasks.add_task(prepare_artwork_display, item["id"])
    start_ai_queue_worker()
    session["uploaded_count"] = int(session.get("uploaded_count") or 0) + len(imported)
    session["last_upload_at"] = now_iso()
    return {"imported": len(imported), "child_name": child_name}


@app.get("/m/upload")
def mobile_upload_page(token: str = "") -> FileResponse:
    return FileResponse(STATIC_DIR / "mobile.html")


def export_artworks(child_id: str | None = None) -> list[dict[str, Any]]:
    with connect() as con:
        return artwork_query(con, child_id=child_id)


@app.get("/api/export/json")
def export_json(child_id: str | None = None) -> JSONResponse:
    payload = {"exported_at": now_iso(), "artworks": export_artworks(child_id)}
    headers = {"Content-Disposition": 'attachment; filename="volio-export.json"'}
    return JSONResponse(payload, headers=headers)


@app.get("/api/export/zip")
def export_zip(child_id: str | None = None) -> StreamingResponse:
    artworks = export_artworks(child_id)
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("metadata.json", json.dumps({"exported_at": now_iso(), "artworks": artworks}, ensure_ascii=False, indent=2))
        for item in artworks:
            original = ROOT / item["original_path"]
            if original.exists():
                archive.write(original, f"originals/{original.name}")
    buffer.seek(0)
    headers = {"Content-Disposition": 'attachment; filename="volio-archive.zip"'}
    return StreamingResponse(buffer, media_type="application/zip", headers=headers)


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def wrap_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, width: int) -> list[str]:
    words = re.split(r"\s+", text.strip())
    lines: list[str] = []
    current = ""
    for word in words:
        trial = f"{current} {word}".strip()
        if draw.textlength(trial, font=font) <= width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines[:10]


@app.get("/api/export/pdf")
def export_pdf(child_id: str | None = None) -> StreamingResponse:
    artworks = export_artworks(child_id)
    if not artworks:
        raise HTTPException(status_code=400, detail="No artworks to export")

    pages: list[Image.Image] = []
    page_w, page_h = 1654, 2339
    margin = 110
    title_font = load_font(46)
    meta_font = load_font(26)
    body_font = load_font(30)
    small_font = load_font(22)

    cover = Image.new("RGB", (page_w, page_h), "#f7f5ef")
    draw = ImageDraw.Draw(cover)
    draw.text((margin, 280), "Volio Portfolio", fill="#1f2933", font=load_font(74))
    child_names = sorted({item.get("child_name") or "Child" for item in artworks})
    draw.text((margin, 390), ", ".join(child_names), fill="#475467", font=load_font(36))
    draw.text((margin, 460), f"{len(artworks)} artworks", fill="#667085", font=meta_font)
    draw.text((margin, page_h - 180), f"Exported {datetime.now().strftime('%Y-%m-%d')}", fill="#667085", font=small_font)
    pages.append(cover)

    for item in artworks:
        page = Image.new("RGB", (page_w, page_h), "#fbfaf7")
        draw = ImageDraw.Draw(page)
        image_path = ROOT / item["original_path"]
        try:
            art = ImageOps.exif_transpose(Image.open(image_path)).convert("RGB")
            art.thumbnail((page_w - margin * 2, 1320))
            x = (page_w - art.width) // 2
            y = 120
            page.paste(art, (x, y))
            text_y = y + art.height + 70
        except Exception:
            text_y = 220

        title = item.get("title") or "Untitled artwork"
        draw.text((margin, text_y), title, fill="#101828", font=title_font)
        text_y += 64

        meta = " · ".join(
            part
            for part in [
                item.get("child_name"),
                item.get("artwork_date") or item.get("date_note"),
                "favorite" if item.get("is_favorite") else "",
                "representative" if item.get("is_representative") else "",
            ]
            if part
        )
        if meta:
            draw.text((margin, text_y), meta, fill="#667085", font=meta_font)
            text_y += 54

        description = item.get("description") or item.get("long_description") or ""
        for line in wrap_text(draw, description, body_font, page_w - margin * 2):
            draw.text((margin, text_y), line, fill="#344054", font=body_font)
            text_y += 42

        if item.get("child_quote"):
            text_y += 18
            quote = f"Child quote: {item['child_quote']}"
            for line in wrap_text(draw, quote, body_font, page_w - margin * 2):
                draw.text((margin, text_y), line, fill="#1d4ed8", font=body_font)
                text_y += 42

        pages.append(page)

    buffer = io.BytesIO()
    pages[0].save(buffer, "PDF", save_all=True, append_images=pages[1:], resolution=150)
    buffer.seek(0)
    headers = {"Content-Disposition": 'attachment; filename="volio-portfolio.pdf"'}
    return StreamingResponse(buffer, media_type="application/pdf", headers=headers)


@app.exception_handler(HTTPException)
def http_error(_: Any, exc: HTTPException) -> JSONResponse:
    return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)
