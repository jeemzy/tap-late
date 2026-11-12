import json
import sqlite3
from contextlib import contextmanager
from pathlib import Path

from taplate.appearance import GlassSettings


class Store:
    def __init__(self, root: Path):
        self.root = root
        root.mkdir(parents=True, exist_ok=True)
        self.database = root / "sessions.sqlite3"
        with self.connection() as conn:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute(
                "CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, created REAL, "
                "expires REAL, status TEXT, digest TEXT, document TEXT)"
            )
            conn.execute("CREATE INDEX IF NOT EXISTS sessions_created ON sessions(created DESC)")
            conn.execute("CREATE TABLE IF NOT EXISTS application_settings (key TEXT PRIMARY KEY, value TEXT)")

    def glass_settings(self):
        with self.connection() as conn:
            row = conn.execute("SELECT value FROM application_settings WHERE key='liquid_glass'").fetchone()
        return GlassSettings.model_validate_json(row[0]) if row else GlassSettings()

    def update_glass_settings(self, changes):
        with self.connection() as conn:
            # Serialize read/merge/write so separate devices editing different knobs do not overwrite each other.
            conn.execute("BEGIN IMMEDIATE")
            row = conn.execute("SELECT value FROM application_settings WHERE key='liquid_glass'").fetchone()
            current = json.loads(row[0]) if row else GlassSettings().model_dump()
            settings = GlassSettings.model_validate({**current, **changes})
            conn.execute(
                "INSERT INTO application_settings (key,value) VALUES('liquid_glass',?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                (settings.model_dump_json(),),
            )
        return settings

    @contextmanager
    def connection(self):
        conn = sqlite3.connect(self.database, timeout=10)
        conn.row_factory = sqlite3.Row
        try:
            with conn:
                yield conn
        finally:
            conn.close()

    def get(self, session_id):
        with self.connection() as conn:
            row = conn.execute("SELECT document FROM sessions WHERE id=?", (session_id,)).fetchone()
        return json.loads(row[0]) if row else None

    def create(self, doc):
        with self.connection() as conn:
            conn.execute(
                "INSERT INTO sessions VALUES(?,?,?,?,?,?)",
                (
                    doc["id"],
                    doc["created_at"],
                    doc["expires_at"],
                    doc["status"],
                    doc["digest"],
                    json.dumps(doc, ensure_ascii=False),
                ),
            )

    def update(self, session_id, **changes):
        with self.connection() as conn:
            conn.execute("BEGIN IMMEDIATE")
            row = conn.execute("SELECT document FROM sessions WHERE id=?", (session_id,)).fetchone()
            if not row:
                return None
            doc = json.loads(row[0])
            doc.update(changes)
            conn.execute(
                "UPDATE sessions SET status=?, document=? WHERE id=?",
                (doc["status"], json.dumps(doc, ensure_ascii=False), session_id),
            )
        return doc

    def save_currency(self, session_id, region_id, amount_id, currency):
        with self.connection() as conn:
            conn.execute("BEGIN IMMEDIATE")
            row = conn.execute("SELECT document FROM sessions WHERE id=?", (session_id,)).fetchone()
            if not row:
                return None
            doc = json.loads(row[0])
            doc.setdefault("amount_currencies", {}).setdefault(region_id, {})[amount_id] = currency
            conn.execute("UPDATE sessions SET document=? WHERE id=?", (json.dumps(doc, ensure_ascii=False), session_id))
        return doc

    def rate_snapshot(self):
        with self.connection() as conn:
            row = conn.execute("SELECT value FROM application_settings WHERE key='ecb_rates'").fetchone()
        return json.loads(row[0]) if row else None

    def save_rate_snapshot(self, snapshot):
        with self.connection() as conn:
            conn.execute(
                "INSERT INTO application_settings (key,value) VALUES('ecb_rates',?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (json.dumps(snapshot),),
            )

    def list(self, now):
        with self.connection() as conn:
            rows = conn.execute(
                "SELECT document FROM sessions WHERE expires>? ORDER BY created DESC", (now,)
            ).fetchall()
        return [json.loads(row[0]) for row in rows]

    def expired(self, now):
        with self.connection() as conn:
            return [row[0] for row in conn.execute("SELECT id FROM sessions WHERE expires<=?", (now,))]

    def delete(self, session_id):
        with self.connection() as conn:
            conn.execute("DELETE FROM sessions WHERE id=?", (session_id,))
