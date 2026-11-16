"""The scan pipeline: analyse thumbnails (cached, resumable) -> group duplicates -> classify."""

from __future__ import annotations

import sys
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field

import numpy as np

from .cache import Cache
from .classify import Classifier, Decision
from .clipper import zero_shot
from .config import Config
from .dedupe import DupItem, find_groups, parse_ts, pick_keeper
from .features import compute_features, file_sig, load_image
from .geo import resolve_home
from .model import Features, PhotoRecord
from .progress import Progress


@dataclass
class ScanResult:
    records: list[PhotoRecord]
    decisions: dict[str, Decision]
    features: dict[str, Features]
    groups: list[list[str]] = field(default_factory=list)   # duplicate groups (uuids), keeper first
    home_found: bool = False
    clip_used: bool = False
    stats: dict = field(default_factory=dict)


def _load(rec: PhotoRecord):
    try:
        return load_image(rec.thumb_path)
    except Exception:
        return None


def analyse(records: list[PhotoRecord], cache: Cache, backend, model_id: str, quiet: bool = False,
            batch: int = 32, workers: int = 4) -> dict:
    """Compute missing thumbnail features and CLIP embeddings. Safe to interrupt and re-run."""
    feats = cache.get_features()
    emb_sigs = cache.embedding_sigs(model_id) if backend else {}
    todo = []
    nothumb = 0
    for r in records:
        if not r.thumb_path:
            nothumb += 1
            if r.uuid not in feats:
                cache.put_features(r.uuid, "", Features(status="nothumb"))
            continue
        sig = file_sig(r.thumb_path)
        need_f = feats.get(r.uuid, ("", None))[0] != sig
        need_e = backend is not None and emb_sigs.get(r.uuid) != sig
        if need_f or need_e:
            todo.append((r, sig, need_f, need_e))
    cache.commit()
    stats = {"analysed": len(todo), "cached": len(records) - len(todo) - nothumb, "nothumb": nothumb, "errors": 0}
    if not todo:
        return stats
    t0 = time.time()
    try:
        with Progress(len(todo), "analyse thumbnails", quiet=quiet) as bar, ThreadPoolExecutor(workers) as pool:
            for s in range(0, len(todo), batch):
                chunk = todo[s:s + batch]
                images = list(pool.map(_load, [c[0] for c in chunk]))
                ok = [(c, im) for c, im in zip(chunk, images) if im is not None]
                for (r, sig, need_f, _), im in zip(chunk, images):
                    if im is None:
                        stats["errors"] += 1
                        cache.put_features(r.uuid, sig, Features(status="error"))
                    elif need_f:
                        cache.put_features(r.uuid, sig, compute_features(im))
                want = [(c, im) for c, im in ok if c[3]]
                if want:
                    vecs = backend.embed_images([im for _, im in want])
                    for (c, _), v in zip(want, vecs):
                        cache.put_embedding(c[0].uuid, model_id, c[1], v)
                cache.commit()
                bar.update(len(chunk))
    except KeyboardInterrupt:
        cache.commit()
        print("\nInterrupted — progress is saved. Run the same command again to resume.", file=sys.stderr)
        raise
    stats["seconds"] = round(time.time() - t0, 1)
    return stats


def text_vectors(prompts: list[str], cache: Cache, backend, model_id: str) -> dict[str, np.ndarray]:
    out, missing = {}, []
    for p in prompts:
        v = cache.get_text_embedding(model_id, p)
        if v is None:
            missing.append(p)
        else:
            out[p] = v
    if missing:
        vecs = backend.embed_texts(missing)
        for p, v in zip(missing, vecs):
            cache.put_text_embedding(model_id, p, v)
            out[p] = np.asarray(v, dtype=np.float32)
        cache.commit()
    return out


def clip_probabilities(records: list[PhotoRecord], cfg: Config, cache: Cache, backend, model_id: str):
    cats = [c for c in cfg.active if c.prompts]
    bg = [str(p) for p in cfg.clip.get("background_prompts", [])]
    if not cats:
        return {}
    tv = text_vectors([p for c in cats for p in c.prompts] + bg, cache, backend, model_id)
    classes = [np.stack([tv[p] for p in c.prompts]) for c in cats] + [tv[p][None, :] for p in bg]
    embs = cache.get_embeddings(model_id, [r.uuid for r in records])
    uuids = list(embs)
    if not uuids:
        return {}
    probs = zero_shot(np.stack([embs[u] for u in uuids]), classes, float(cfg.clip.get("temperature", 100)))
    return {u: {c.name: float(probs[i, j]) for j, c in enumerate(cats)} for i, u in enumerate(uuids)}


def duplicate_groups(all_records: list[PhotoRecord], feats: dict[str, Features], cfg: Config):
    dc = cfg.duplicates
    items = []
    for r in all_records:
        f = feats.get(r.uuid)
        if f is None or f.status != "ok" or f.phash is None:
            continue
        if r.is_movie and not dc.get("include_videos", False):
            continue
        items.append(DupItem(r.uuid, f.phash, f.dhash, parse_ts(r.date), r.width * r.height, r.filesize,
                             r.is_favorite, r.has_adjustments, f.std if f.std is not None else 99.0))
    groups = find_groups(items, int(dc.get("max_distance", 6)), int(dc.get("similar_distance", 12)),
                         float(dc.get("similar_window_seconds", 120)), float(cfg.review.get("flat_std", 5)))
    out, info = [], {}
    for gid, g in enumerate(groups, 1):
        keep = pick_keeper(items, g)
        ordered = [keep] + [i for i in g if i != keep]
        out.append([items[i].uuid for i in ordered])
        for i in ordered:
            info[items[i].uuid] = (gid, "keeper" if i == keep else "extra")
    return out, info


def run_scan(all_records: list[PhotoRecord], selected: list[PhotoRecord], cfg: Config, cache: Cache,
             backend=None, quiet: bool = False) -> ScanResult:
    """all_records = whole library (context for home + duplicates); selected = photos to sort now."""
    model_id = cfg.clip_model_id()
    stats = analyse(selected, cache, backend, model_id, quiet=quiet)
    feats = {u: f for u, (_, f) in cache.get_features().items()}
    clip = clip_probabilities(selected, cfg, cache, backend, model_id) if backend is not None else {}
    home = None
    if cfg.by_rule("travel"):
        home = resolve_home(cfg.travel, [(r.latitude, r.longitude) for r in all_records])
    groups, dup_info = ([], {})
    if cfg.by_rule("duplicates"):
        groups, dup_info = duplicate_groups(all_records, feats, cfg)
    sel = {r.uuid for r in selected}
    groups = [g for g in groups if any(u in sel for u in g)]
    clf = Classifier(cfg, home=home, dup_info=dup_info)
    decisions = {r.uuid: clf.classify(r, feats.get(r.uuid), clip.get(r.uuid)) for r in selected}
    stats["clip_scored"] = len(clip)
    return ScanResult(records=selected, decisions=decisions, features=feats, groups=groups,
                      home_found=home is not None, clip_used=backend is not None, stats=stats)
