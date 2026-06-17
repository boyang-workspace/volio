import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from server.main import connect, filename_title, looks_generic_ai_text, now_iso


def main() -> None:
    cleaned = 0
    with connect() as con:
        rows = con.execute(
            """
            SELECT id, title, description, long_description, original_filename
            FROM artworks
            """
        ).fetchall()
        for row in rows:
            bad_title = looks_generic_ai_text(row["title"])
            bad_description = looks_generic_ai_text(row["description"])
            bad_long = looks_generic_ai_text(row["long_description"])
            if not (bad_title or bad_description or bad_long):
                continue
            con.execute(
                """
                UPDATE artworks
                SET title = ?,
                    description = ?,
                    long_description = ?,
                    ai_status = 'pending',
                    ai_raw_json = NULL,
                    ai_error = 'Previous AI description was too generic. Run AI again.',
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    filename_title(row["original_filename"]) if bad_title else row["title"],
                    "" if bad_description else row["description"],
                    "" if bad_long else row["long_description"],
                    now_iso(),
                    row["id"],
                ),
            )
            con.execute("DELETE FROM artwork_tags WHERE artwork_id = ? AND source = 'ai'", (row["id"],))
            cleaned += 1
        con.execute(
            """
            DELETE FROM tags
            WHERE id NOT IN (SELECT DISTINCT tag_id FROM artwork_tags)
            """
        )
        con.commit()
    print(f"Cleaned {cleaned} generic AI records.")


if __name__ == "__main__":
    main()
