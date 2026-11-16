import csv
import json
import re
from pathlib import Path

import numpy as np
import pytest

from photosort import cli
from photosort.apply import ApplyError, apply_plan
from photosort.library import load_fake
from photosort.pipeline import analyse, run_scan
from photosort.report import write_report

PKG = Path(__file__).resolve().parent.parent / "photosort"


class FakeBackend:
    """Stands in for CLIP: deterministic unit vectors, counts how many images it embeds."""
    device = "fake"

    def __init__(self):
        self.images = 0

    def embed_images(self, images):
        self.images += len(images)
        out = np.array([[im.getpixel((0, 0))[0] + 1.0, im.getpixel((5, 5))[1] + 1.0, 1.0] for im in images], dtype=np.float32)
        return out / np.linalg.norm(out, axis=1, keepdims=True)

    def embed_texts(self, texts):
        out = np.array([[len(t) % 7 + 1.0, len(t) % 5 + 1.0, 1.0] for t in texts], dtype=np.float32)
        return out / np.linalg.norm(out, axis=1, keepdims=True)


class FakeWriter:
    def __init__(self, bad=()):
        self.folders, self.albums, self.calls, self.bad = [], {}, 0, set(bad)

    def ensure_folder(self, name):
        new = name not in self.folders
        if new:
            self.folders.append(name)
        return new

    def ensure_album(self, name):
        new = name not in self.albums
        self.albums.setdefault(name, set())
        return name, new

    def add(self, album, uuids):
        self.calls += 1
        if self.bad & set(uuids):
            raise RuntimeError("no such media item")
        self.albums[album] |= set(uuids)          # like Photos: adding twice is a no-op


@pytest.fixture()
def scanned(demo_lib, cfg, cache, tmp_path):
    records, info = load_fake(str(demo_lib))
    result = run_scan(records, records, cfg, cache, backend=None, quiet=True)
    rep = write_report(tmp_path / "run", result, cfg, info)
    return records, result, rep, tmp_path / "run"


def test_scan_sorts_demo_library(scanned, cfg):
    records, result, rep, run = scanned
    albums = rep["plan"]["albums"]
    for name in cfg.album_names():
        assert name in albums
    for name in ["Screenshots", "Selfies", "Videos", "Friends & Family", "Travel", "Gym & Fitness", "Food & Drinks",
                 "Receipts & Documents", "Cars & Rides", "Nature & Outdoors", "Trees", "Sunsets & Sky",
                 "Pets & Animals", "Memes & Saved Images", "Work", "Shopping", "Duplicates & Similar",
                 "Review to delete", "Unsorted"]:
        assert albums[name], name
    assert len(albums["Screenshots"]) == 10 and len(albums["Videos"]) == 6 and len(albums["Travel"]) == 10
    assert len(albums["Duplicates & Similar"]) == 8 and len(result.groups) == 4
    assert len(albums["Review to delete"]) == 9
    assert result.home_found
    by = {r.uuid: r for r in records}
    for g in result.groups:                      # keeper = the full-size copy
        assert by[g[0]].width == 4032
    assert any(len(d.categories) > 1 for d in result.decisions.values())
    # iCloud-only items without a preview are still sorted from metadata, never flagged blurry/duplicate
    for r in records:
        if not r.thumb_path:
            d = result.decisions[r.uuid]
            assert "Trees" in d.categories and "Review to delete" not in d.albums and d.dup_group is None


def test_report_files(scanned):
    records, result, rep, run = scanned
    page = (run / "report.html").read_text(encoding="utf-8")
    assert "Nothing has been changed in Photos" in page and "Sorted by Claude" in page
    srcs = re.findall(r'src="(thumbs/[^"]+)"', page)
    assert len(srcs) > 100 and all((run / s).exists() for s in set(srcs))
    assert "no local preview" in page
    assert (run / "sheets" / "food-drinks.jpg").exists()
    rows = list(csv.DictReader(open(run / "photos.csv", encoding="utf-8")))
    assert len(rows) == len(records) and "score:Trees" in rows[0] and "latitude" not in rows[0]
    plan = json.loads((run / "plan.json").read_text())
    assert plan["folder"] == "Sorted by Claude" and plan["photos_scanned"] == len(records)
    counts = dict(csv.reader(open(run / "albums.csv", encoding="utf-8")))
    assert int(counts["Videos"]) == 6


def test_report_escapes_html(demo_lib, cfg, cache, tmp_path):
    records, info = load_fake(str(demo_lib))
    records[0].filename = '<script>alert(1)</script>".jpg'
    result = run_scan(records, records[:20], cfg, cache, quiet=True)
    write_report(tmp_path / "r", result, cfg, info)
    page = (tmp_path / "r" / "report.html").read_text(encoding="utf-8")
    assert "<script>alert" not in page


def test_cache_resume_and_clip(demo_lib, cfg, cache):
    records, _ = load_fake(str(demo_lib))
    be = FakeBackend()
    s1 = analyse(records[:40], cache, be, "m", quiet=True)          # "interrupted" after 40
    assert s1["analysed"] == 40 and be.images == 40
    s2 = analyse(records, cache, be, "m", quiet=True)               # resumes: only the rest
    with_thumb = sum(1 for r in records if r.thumb_path)
    assert s2["cached"] == 40 and be.images == with_thumb
    s3 = analyse(records, cache, be, "m", quiet=True)
    assert s3["analysed"] == 0 and be.images == with_thumb
    result = run_scan(records, records, cfg, cache, backend=be, quiet=True)
    assert result.clip_used and result.stats["clip_scored"] == with_thumb
    assert any("clip:" in " ".join(d.reasons.values()) for d in result.decisions.values())
    s4 = analyse(records, cache, None, "m", quiet=True)             # --no-clip run reuses features
    assert s4["analysed"] == 0


def test_since_run_still_sees_old_duplicates(demo_lib, cfg, cache):
    records, _ = load_fake(str(demo_lib))
    run_scan(records, records, cfg, cache, quiet=True)
    new = [r for r in records if r.width == 600][:1]                # one resized copy = "newly added"
    result = run_scan(records, new, cfg, cache, quiet=True)
    assert len(result.decisions) == 1 and len(result.groups) == 1
    assert result.decisions[new[0].uuid].dup_role == "extra"


def test_apply_is_add_only_and_idempotent(scanned, cache):
    _, _, rep, _ = scanned
    plan = rep["plan"]
    w = FakeWriter()
    s = apply_plan(plan, w, cache, quiet=True, chunk=7)
    assert w.folders == ["Sorted by Claude"] and s["folder_created"]
    for a, uuids in plan["albums"].items():
        assert w.albums[a] == set(uuids) and s["albums"][a]["added"] == len(uuids)
    calls = w.calls
    s2 = apply_plan(plan, w, cache, quiet=True)                       # second run: nothing to do
    assert w.calls == calls and all(v["added"] == 0 for v in s2["albums"].values())
    w.albums["Trees"].clear()                                         # user emptied an album by hand
    apply_plan(plan, w, cache, quiet=True)
    assert w.albums["Trees"] == set()                                 # ... and it is not refilled
    apply_plan(plan, w, cache, quiet=True, only=["Trees"], readd=True)
    assert w.albums["Trees"] == set(plan["albums"]["Trees"])


def test_apply_only_skip_and_bad_ids(scanned, cache):
    _, _, rep, _ = scanned
    plan = rep["plan"]
    bad = plan["albums"]["Videos"][0]
    w = FakeWriter(bad=[bad])
    s = apply_plan(plan, w, cache, quiet=True, only=["Videos", "Trees"], skip=["Trees"])
    assert list(w.albums) == ["Videos"]
    assert w.albums["Videos"] == set(plan["albums"]["Videos"]) - {bad}
    assert [f["uuid"] for f in s["failed"]] == [bad]
    assert bad not in cache.applied_for("Videos")
    with pytest.raises(ApplyError):
        apply_plan(plan, w, cache, quiet=True, only=["No Such Album"])


def test_cli_demo_and_apply_dry_run(tmp_path, capsys):
    out = tmp_path / "out"
    assert cli.main(["demo", "--out", str(out), "--no-open", "--quiet"]) == 0
    assert (out / ".gitignore").read_text() == "*\n"                 # outputs can never be committed
    assert not (out / "latest.txt").exists()                         # demo never becomes the plan to apply
    run = Path((out / "demo" / "latest.txt").read_text())
    assert (run / "report.html").exists() and (run / "plan.json").exists()
    assert "DRY RUN" in capsys.readouterr().out
    assert cli.main(["apply", "--out", str(out), "--yes"]) == 2      # no real scan yet
    assert cli.main(["apply", "--out", str(out / "demo"), "--yes"]) == 2   # demo plans are refused
    lib = f"fake:{out / 'demo' / 'demo-library'}"
    assert cli.main(["scan", "--out", str(out), "--library", lib, "--since", "2030-01-01",
                     "--no-open", "--no-clip", "--quiet"]) == 0     # nothing new -> nothing to sort
    assert not (out / "latest.txt").exists()
    assert cli.main(["scan", "--out", str(out), "--library", lib, "--limit", "30", "--no-open", "--no-clip",
                     "--quiet"]) == 0
    plan = json.loads((Path((out / "latest.txt").read_text()) / "plan.json").read_text())
    assert plan["photos_scanned"] == 30


def test_package_never_calls_destructive_photos_apis():
    """Guard rail: the code must not contain any call that deletes, removes, moves, edits or imports."""
    banned = [r"\.delete", r"delete_album", r"delete_folder", r"\.remove\(", r"remove_by_id", r"\.move\(",
              r"import_photos", r"\.trash", r"albumRemove", r"photosLibraryDelete", r"batch_edit",
              r"\.(title|name|description|keywords|favorite|location|date)\s*=[^=]", r"os\.remove", r"unlink",
              r"rmtree", r"\.export\(", r"use_photokit", r"osascript"]
    for py in PKG.glob("*.py"):
        src = py.read_text(encoding="utf-8")
        for pat in banned:
            assert not re.search(pat, src), f"{py.name} matches forbidden pattern {pat}"
    apply_src = (PKG / "apply.py").read_text(encoding="utf-8")
    assert re.findall(r'_run\("(\w+)"', apply_src) == ["albumAdd"]
