import numpy as np
from PIL import Image, ImageFilter

from photosort.cli import parse_since, select_records
from photosort.clipper import zero_shot
from photosort.dedupe import DupItem, find_groups, pick_keeper
from photosort.demo import _picture
from photosort.features import compute_features, hamming, load_image
from photosort.geo import find_home, haversine_km, resolve_home
from photosort.library import pick_thumb
from photosort.model import Features, PhotoRecord

import random


def test_haversine_and_home():
    assert abs(haversine_km(0, 0, 0, 1) - 111.19) < 0.5
    pts = [(10 + i * 0.001, 20 + i * 0.001) for i in range(40)] + [(48.0, 2.0)] * 12 + [(None, None), (0.0, 0.0)]
    home = find_home(pts)
    assert abs(home[0] - 10.02) < 0.05 and abs(home[1] - 20.02) < 0.05
    assert find_home(pts[:5]) is None
    assert resolve_home({"home": [1.5, 2.5]}, []) == (1.5, 2.5)


def test_phash_robust_and_blur(tmp_path):
    rng = random.Random(3)
    im = _picture(rng)
    a = compute_features(im)
    b = compute_features(im.resize((320, 240)))
    c = compute_features(_picture(rng))
    assert hamming(a.phash, b.phash) <= 4 and hamming(a.dhash, b.dhash) <= 6
    assert hamming(a.phash, c.phash) > 12
    blurred = compute_features(im.filter(ImageFilter.GaussianBlur(12)))
    assert a.sharp > 30 and blurred.sharp < 8
    black = compute_features(Image.new("RGB", (200, 200), (3, 3, 3)))
    assert black.mean < 10 and black.std < 2
    p = tmp_path / "x.jpg"
    Image.new("RGB", (3000, 2000), (9, 99, 199)).save(p)
    assert max(load_image(str(p)).size) <= 512


def test_dedupe_groups_and_keeper():
    base = 0xF0F0AA5512345678
    items = [
        DupItem("a", base, base, ts=1000, pixels=100),
        DupItem("b", base ^ 0b111, base ^ 0b1, ts=9_000_000, pixels=400),           # duplicate, far in time
        DupItem("c", base ^ 0x3FF, base ^ 0x3F, ts=1030, pixels=100),              # 10 bits: similar only if near in time
        DupItem("d", ~base & 0xFFFFFFFFFFFFFFFF, 0x1, ts=1010, pixels=100),        # different
        DupItem("e", base ^ (0x3FF << 20), base, ts=5_000_000, pixels=100),        # 10 bits but far in time
        DupItem("flat", base, base, ts=1001, std=1.0),                             # blank frame: ignored
    ]
    groups = find_groups(items, max_distance=6, similar_distance=12, window_seconds=120)
    assert len(groups) == 1
    assert {items[i].uuid for i in groups[0]} == {"a", "b", "c"}
    assert items[pick_keeper(items, groups[0])].uuid == "b"
    items[0].favorite = True
    assert items[pick_keeper(items, groups[0])].uuid == "a"
    assert find_groups(items[:1]) == []


def test_dedupe_scales():
    rng = np.random.default_rng(0)
    hs = rng.integers(0, 2**63, size=20000, dtype=np.int64)
    items = [DupItem(str(i), int(h), int(h), ts=float(i) * 1000) for i, h in enumerate(hs)]
    items.append(DupItem("dup", int(hs[5]) ^ 0b101, int(hs[5]), ts=1e12))
    groups = find_groups(items)
    assert [sorted(items[i].uuid for i in g) for g in groups] == [["5", "dup"]]


def test_zero_shot():
    img = np.array([[1.0, 0.0], [0.0, 1.0]], dtype=np.float32)
    classes = [np.array([[1.0, 0.0], [0.7, 0.7]], dtype=np.float32), np.array([[0.0, 1.0]], dtype=np.float32)]
    p = zero_shot(img, classes, 100)
    assert p.shape == (2, 2) and p[0, 0] > 0.99 and p[1, 1] > 0.99
    assert np.allclose(p.sum(axis=1), 1, atol=1e-5)
    assert zero_shot(np.zeros((0, 2), dtype=np.float32), classes).shape == (0, 2)


def test_cache_roundtrip(cache):
    cache.put_features("u", "sig", Features(2**63 + 5, 7, 1.5, 2.5, 3.5))
    cache.put_features("n", "", Features(status="nothumb"))
    cache.commit()
    sig, f = cache.get_features()["u"]
    assert sig == "sig" and f.phash == 2**63 + 5 and f.dhash == 7 and f.sharp == 1.5
    assert cache.get_features()["n"][1].status == "nothumb"
    v = np.linspace(-1, 1, 512, dtype=np.float32)
    cache.put_embedding("u", "m", "sig", v)
    assert np.allclose(cache.get_embeddings("m")["u"], v, atol=1e-3)
    assert cache.embedding_sigs("m") == {"u": "sig"} and cache.get_embeddings("other") == {}
    cache.put_text_embedding("m", "a photo", v)
    assert np.array_equal(cache.get_text_embedding("m", "a photo"), v)
    cache.mark_applied("A", ["u", "u", "w"])
    assert cache.applied_for("A") == {"u", "w"} and cache.applied_for("B") == set()
    cache.put_records([PhotoRecord(uuid="u", labels=["x"])])
    assert cache.get_records()[0].labels == ["x"]
    cache.set_kv("k", 1.5)
    assert cache.get_kv("k") == 1.5 and cache.get_kv("zz") is None


def test_since_and_limit(cache):
    recs = [PhotoRecord(uuid="old", date_added="2020-01-01T10:00:00+00:00", date="2020-01-01T10:00:00+00:00"),
            PhotoRecord(uuid="new", date_added="2026-06-01T10:00:00+00:00", date="2019-01-01T10:00:00+00:00"),
            PhotoRecord(uuid="nodate")]
    since = parse_since("2025-01-01", cache)
    assert [r.uuid for r in select_records(recs, since, None)] == ["new"]      # by date ADDED, not taken
    assert parse_since("last", cache) is None
    cache.set_kv("last_scan_started", 1_700_000_000)
    assert parse_since("last", cache).year == 2023
    assert parse_since("7d", cache) is not None and parse_since(None, cache) is None
    assert [r.uuid for r in select_records(recs, None, 1)] == ["old"]


def test_pick_thumb(tmp_path):
    small, mid, big, mov = (tmp_path / n for n in ("s.jpeg", "m.jpeg", "b.jpeg", "v.mov"))
    small.write_bytes(b"x" * 10_000); mid.write_bytes(b"x" * 80_000); big.write_bytes(b"x" * 900_000)
    mov.write_bytes(b"x" * 100)
    assert pick_thumb([str(mov), str(big), str(mid), str(small)], None, False) == str(mid)
    assert pick_thumb([str(small), str(mov)], None, False) == str(small)
    assert pick_thumb([], None, False) is None                                  # iCloud-only, no preview
    assert pick_thumb([str(tmp_path / "gone.jpeg")], str(big), False) == str(big)
    assert pick_thumb([], str(big), True) is None
