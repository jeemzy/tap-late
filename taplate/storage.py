import json
import sqlite3
from contextlib import contextmanager
from pathlib import Path


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
