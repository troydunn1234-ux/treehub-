"""Resumable sqlite cache: image features, CLIP embeddings, applied album adds, run history."""

from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path

import numpy as np

from .model import Features, PhotoRecord

SCHEMA = """
CREATE TABLE IF NOT EXISTS photos(uuid TEXT PRIMARY KEY, meta TEXT NOT NULL, seen REAL NOT NULL);
CREATE TABLE IF NOT EXISTS features(uuid TEXT PRIMARY KEY, sig TEXT, phash TEXT, dhash TEXT,
    sharp REAL, mean REAL, std REAL, status TEXT, updated REAL);
CREATE TABLE IF NOT EXISTS embeddings(uuid TEXT, model TEXT, sig TEXT, vec BLOB, PRIMARY KEY(uuid, model));
CREATE TABLE IF NOT EXISTS text_embeddings(model TEXT, prompt TEXT, vec BLOB, PRIMARY KEY(model, prompt));
CREATE TABLE IF NOT EXISTS applied(uuid TEXT, album TEXT, ts REAL, PRIMARY KEY(uuid, album));
CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT);
"""


def _hex(v: int | None) -> str | None:
    return None if v is None else f"{v:016x}"


def _unhex(v: str | None) -> int | None:
    return None if v is None else int(v, 16)


class Cache:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(self.path))
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(SCHEMA)
        self.db.commit()

    def close(self):
        self.db.commit()
        self.db.close()

    def commit(self):
        self.db.commit()

    # --- metadata snapshot (lets --since runs compare against the whole library)
    def put_records(self, records: list[PhotoRecord]):
        now = time.time()
        self.db.executemany(
            "INSERT OR REPLACE INTO photos(uuid, meta, seen) VALUES(?,?,?)",
            [(r.uuid, json.dumps(r.to_dict(), separators=(",", ":")), now) for r in records],
        )
        self.db.commit()

    def get_records(self) -> list[PhotoRecord]:
        return [PhotoRecord.from_dict(json.loads(m)) for (m,) in self.db.execute("SELECT meta FROM photos")]

    # --- thumbnail features
    def get_features(self) -> dict[str, tuple[str, Features]]:
        out = {}
        for u, sig, ph, dh, sh, mn, sd, st in self.db.execute(
            "SELECT uuid, sig, phash, dhash, sharp, mean, std, status FROM features"
        ):
            out[u] = (sig, Features(_unhex(ph), _unhex(dh), sh, mn, sd, st or "ok"))
        return out

    def put_features(self, uuid: str, sig: str, f: Features):
        self.db.execute(
            "INSERT OR REPLACE INTO features VALUES(?,?,?,?,?,?,?,?,?)",
            (uuid, sig, _hex(f.phash), _hex(f.dhash), f.sharp, f.mean, f.std, f.status, time.time()),
        )

    # --- CLIP embeddings
    def embedding_sigs(self, model: str) -> dict[str, str]:
        return dict(self.db.execute("SELECT uuid, sig FROM embeddings WHERE model=?", (model,)))

    def put_embedding(self, uuid: str, model: str, sig: str, vec: np.ndarray):
        self.db.execute(
            "INSERT OR REPLACE INTO embeddings VALUES(?,?,?,?)",
            (uuid, model, sig, np.asarray(vec, dtype=np.float16).tobytes()),
        )

    def get_embeddings(self, model: str, uuids: list[str] | None = None) -> dict[str, np.ndarray]:
        out = {}
        want = set(uuids) if uuids is not None else None
        for u, blob in self.db.execute("SELECT uuid, vec FROM embeddings WHERE model=?", (model,)):
            if want is None or u in want:
                out[u] = np.frombuffer(blob, dtype=np.float16).astype(np.float32)
        return out

    def get_text_embedding(self, model: str, prompt: str) -> np.ndarray | None:
        row = self.db.execute(
            "SELECT vec FROM text_embeddings WHERE model=? AND prompt=?", (model, prompt)
        ).fetchone()
        return None if row is None else np.frombuffer(row[0], dtype=np.float32).copy()

    def put_text_embedding(self, model: str, prompt: str, vec: np.ndarray):
        self.db.execute(
            "INSERT OR REPLACE INTO text_embeddings VALUES(?,?,?)",
            (model, prompt, np.asarray(vec, dtype=np.float32).tobytes()),
        )

    # --- applied album adds (idempotency + respects photos you removed from an album later)
    def applied_for(self, album: str) -> set[str]:
        return {u for (u,) in self.db.execute("SELECT uuid FROM applied WHERE album=?", (album,))}

    def mark_applied(self, album: str, uuids: list[str]):
        now = time.time()
        self.db.executemany("INSERT OR IGNORE INTO applied VALUES(?,?,?)", [(u, album, now) for u in uuids])
        self.db.commit()

    # --- misc
    def get_kv(self, key: str, default=None):
        row = self.db.execute("SELECT value FROM kv WHERE key=?", (key,)).fetchone()
        return default if row is None else json.loads(row[0])

    def set_kv(self, key: str, value):
        self.db.execute("INSERT OR REPLACE INTO kv VALUES(?,?)", (key, json.dumps(value)))
        self.db.commit()
