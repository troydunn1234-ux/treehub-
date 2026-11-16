"""Build a small synthetic library (generated images + made-up metadata) to try the pipeline
without touching Photos. Used by `./sortphotos demo` and by the tests."""

from __future__ import annotations

import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HOME = (10.0, 20.0)      # made-up coordinates
AWAY = (48.0, 2.0)

SCENES = [
    # (count, labels, extra fields)
    (14, ["food", "plate", "meal"], {}),
    (12, ["gym", "weightlifting"], {"search_terms": ["fitness center"]}),
    (12, ["tree", "forest", "outdoor"], {}),
    (10, ["sunset", "sky"], {}),
    (10, ["dog", "animal"], {}),
    (10, ["car", "vehicle"], {}),
    (8, ["document", "receipt"], {}),
    (8, ["mountain", "landscape", "outdoor"], {}),
    (6, ["store", "shelf"], {}),
    (6, ["office", "whiteboard"], {}),
    (10, [], {"is_screenshot": True, "camera_make": ""}),
    (8, [], {"is_selfie": True, "face_count": 1}),
    (8, ["people"], {"face_count": 3, "persons": ["Person A", "Person B"]}),
    (6, [], {"is_movie": True}),
    (8, [], {"camera_make": "", "imported_by": "com.example.chat"}),
    (10, ["beach", "ocean"], {"latitude": AWAY[0], "longitude": AWAY[1], "place": "Far Away Beach"}),
    (20, [], {}),
]


def _picture(rng: random.Random, size=(640, 480)) -> Image.Image:
    im = Image.new("RGB", size, tuple(rng.randrange(30, 225) for _ in range(3)))
    d = ImageDraw.Draw(im)
    for _ in range(rng.randrange(8, 16)):
        x0, y0 = rng.randrange(size[0]), rng.randrange(size[1])
        x1, y1 = x0 + rng.randrange(30, 260), y0 + rng.randrange(30, 220)
        col = tuple(rng.randrange(256) for _ in range(3))
        (d.ellipse if rng.random() < 0.4 else d.rectangle)([x0, y0, x1, y1], fill=col)
    for _ in range(12):
        d.line([rng.randrange(size[0]), rng.randrange(size[1]), rng.randrange(size[0]), rng.randrange(size[1])],
               fill=(rng.randrange(256),) * 3, width=rng.randrange(1, 4))
    return im


def make_demo_library(directory: str | Path, seed: int = 1) -> Path:
    d = Path(directory)
    (d / "img").mkdir(parents=True, exist_ok=True)
    rng = random.Random(seed)
    t = datetime(2024, 1, 1, 9, 0, tzinfo=timezone.utc)
    photos = []

    def add(im, labels=(), **kw):
        nonlocal t
        i = len(photos)
        t += timedelta(hours=rng.randrange(5, 30))
        rel = None
        if im is not None:
            rel = f"img/{i:04d}.jpg"
            im.save(d / rel, "JPEG", quality=88)
        rec = {
            "uuid": f"DEMO-{i:04d}", "filename": f"IMG_{i:04d}.JPG", "date": t.isoformat(),
            "date_added": t.isoformat(), "width": 4032, "height": 3024, "filesize": 2_000_000 + i,
            "labels": list(labels), "has_exif": True, "camera_make": "DemoCam", "thumb_path": rel,
            "latitude": HOME[0] + rng.uniform(-0.05, 0.05), "longitude": HOME[1] + rng.uniform(-0.05, 0.05),
        }
        rec.update(kw)
        photos.append(rec)
        return rec

    for count, labels, extra in SCENES:
        for _ in range(count):
            add(_picture(rng), labels, **extra)
    # exact-ish duplicates (same picture saved twice, far apart in time)
    for _ in range(4):
        im = _picture(rng)
        add(im, ["food"])
        add(im.resize((600, 450)), ["food"], width=600, height=450)
    # blurry, dark and blank shots
    for _ in range(5):
        add(_picture(rng).filter(ImageFilter.GaussianBlur(14)))
    for _ in range(3):
        add(Image.new("RGB", (640, 480), (4, 4, 5)))
    add(Image.new("RGB", (640, 480), (200, 200, 200)))
    # iCloud-only items with no local preview
    for _ in range(4):
        add(None, ["tree"], is_missing=True)
    (d / "library.json").write_text(json.dumps({"photos": photos}, indent=1), encoding="utf-8")
    return d
