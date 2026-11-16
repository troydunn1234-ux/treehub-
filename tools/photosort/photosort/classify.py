"""Turn metadata + thumbnail features + (optional) CLIP probabilities into album decisions."""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .config import Category, Config
from .geo import haversine_km, valid_point
from .model import Features, PhotoRecord

CAMERA_APPS = {"", "com.apple.camera", "com.apple.mobileslideshow", "com.apple.Photos", "com.apple.photos"}


@dataclass
class Decision:
    uuid: str
    categories: list[str] = field(default_factory=list)   # category names over threshold
    albums: list[str] = field(default_factory=list)       # album names to add to
    scores: dict[str, float] = field(default_factory=dict)
    reasons: dict[str, str] = field(default_factory=dict)
    unsorted: bool = False
    dup_group: int | None = None
    dup_role: str = ""                                     # keeper | extra
    km_from_home: float | None = None


def noisy_or(values) -> float:
    p = 1.0
    for v in values:
        p *= 1.0 - max(0.0, min(1.0, v))
    return 1.0 - p


def _word_re(terms: list[str]) -> re.Pattern | None:
    if not terms:
        return None
    alts = "|".join(re.escape(t) for t in sorted(set(terms), key=len, reverse=True))
    return re.compile(rf"(?<![a-z0-9])(?:{alts})(?:s|es)?(?![a-z0-9])")


class _Matcher:
    def __init__(self, cat: Category):
        self.strong = _word_re(cat.labels)
        self.weak = _word_re(cat.weak_labels)
        self.exclude = _word_re(cat.exclude_labels)
        self.search = _word_re(cat.search)
        self.kw = _word_re(cat.keywords)


def _hits(rx: re.Pattern | None, items: list[str]) -> list[str]:
    if rx is None:
        return []
    return [s for s in items if rx.search(s)]


class Classifier:
    def __init__(self, config: Config, home: tuple[float, float] | None = None,
                 dup_info: dict[str, tuple[int, str]] | None = None):
        self.cfg = config
        self.home = home
        self.dup_info = dup_info or {}
        self.m = {c.name: _Matcher(c) for c in config.active}
        self.exempt = _word_re([str(x).lower() for x in config.review.get("exempt_labels", [])])

    # --- built-in rules -------------------------------------------------
    def _people(self, r: PhotoRecord, flags: set[str]) -> list[tuple[float, str]]:
        if r.persons:
            return [(0.95, f"named people x{len(r.persons)}")]
        if r.face_count >= 2:
            return [(0.80, f"{r.face_count} faces")]
        if r.face_count == 1:
            solo_selfie = "selfie" in flags or "front_camera" in flags
            return [(0.40 if solo_selfie else 0.60, "1 face" + (" (solo selfie)" if solo_selfie else ""))]
        return []

    def _saved(self, r: PhotoRecord, flags: set[str]) -> list[tuple[float, str]]:
        out = []
        if "gif" in flags:
            out.append((0.90, "gif"))
        if r.has_exif and not r.camera_make and not r.is_movie:
            out.append((0.55, "no camera info"))
        if r.imported_by and r.imported_by not in CAMERA_APPS and not r.camera_make:
            out.append((0.60, f"saved by {r.imported_by.split('.')[-1]}"))
        return out

    def _travel(self, r: PhotoRecord, d: Decision) -> list[tuple[float, str]]:
        if self.home is None or not valid_point(r.latitude, r.longitude):
            return []
        km = haversine_km(self.home[0], self.home[1], r.latitude, r.longitude)
        d.km_from_home = round(km, 1)
        if km >= float(self.cfg.travel.get("min_km", 150)):
            return [(0.95, f"{km:.0f} km from home" + (f" ({r.place})" if r.place else ""))]
        return []

    def _review(self, r: PhotoRecord, f: Features | None) -> list[tuple[float, str]]:
        if f is None or f.status != "ok" or f.sharp is None:
            return []
        rv = self.cfg.review
        out = []
        if f.std is not None and f.std < float(rv.get("flat_std", 5)):
            out.append((0.85, f"blank frame (contrast {f.std:.1f})"))
        elif f.mean is not None and f.mean < float(rv.get("dark_mean", 14)) and f.std < float(rv.get("dark_std", 12)):
            out.append((0.80, f"very dark (brightness {f.mean:.0f})"))
        else:
            scale = 0.5 if (self.exempt is not None and _hits(self.exempt, r.labels)) else 1.0
            if f.sharp < float(rv.get("blur_strict", 8.0)):
                out.append((0.75 * scale, f"blurry (sharpness {f.sharp:.1f})"))
            elif f.sharp < float(rv.get("blur_soft", 14.0)):
                out.append((0.40 * scale, f"soft (sharpness {f.sharp:.1f})"))
        if r.score_failure is not None and r.score_failure <= -0.6:
            out.append((0.30, "Photos flags it as a failed shot"))
        return out

    # --- main -------------------------------------------------------------
    def classify(self, r: PhotoRecord, f: Features | None = None,
                 clip: dict[str, float] | None = None) -> Decision:
        d = Decision(uuid=r.uuid)
        flags = r.flags()
        ls = self.cfg.label_strength
        text = " | ".join([r.title, r.caption, r.ai_caption, " ".join(r.keywords)]).lower()
        if r.uuid in self.dup_info:
            d.dup_group, d.dup_role = self.dup_info[r.uuid]
        for c in self.cfg.active:
            m = self.m[c.name]
            sig: list[tuple[float, str]] = []
            hard = sorted(flags & set(c.flags))
            if hard:
                sig.append((1.0, "flag:" + "+".join(hard)))
            elif flags & set(c.exclude_flags):
                d.scores[c.name] = 0.0
                continue
            if not _hits(m.exclude, r.labels):
                strong = _hits(m.strong, r.labels)
                sig += [(float(ls.get("strong", 0.85)), f"label:{s}") for s in strong[:3]]
                weak = [w for w in _hits(m.weak, r.labels) if w not in strong]
                sig += [(float(ls.get("weak", 0.35)), f"weak:{s}") for s in weak[:3]]
            sig += [(float(ls.get("search", 0.40)), f"search:{s}") for s in _hits(m.search, r.search_terms)[:2]]
            if m.kw is not None:
                k = m.kw.search(text)
                if k:
                    sig.append((float(ls.get("keyword", 0.80)), f"keyword:{k.group(0)}"))
            if clip and c.name in clip and clip[c.name] >= 0.05:
                sig.append((clip[c.name] * c.clip_weight, f"clip:{clip[c.name]:.2f}"))
            if c.rule == "people":
                sig += self._people(r, flags)
            elif c.rule == "saved":
                sig += self._saved(r, flags)
            elif c.rule == "travel":
                sig += self._travel(r, d)
            elif c.rule == "review":
                sig += self._review(r, f)
            elif c.rule == "duplicates" and d.dup_group is not None:
                sig.append((1.0, f"group {d.dup_group} ({d.dup_role})"))
            score = noisy_or(v for v, _ in sig)
            d.scores[c.name] = round(score, 3)
            if sig:
                d.reasons[c.name] = "; ".join(t for _, t in sorted(sig, key=lambda x: -x[0]))
            if score >= c.threshold:
                d.categories.append(c.name)
                if c.album not in d.albums:
                    d.albums.append(c.album)
        extra = self.cfg.duplicates.get("extras_album")
        if extra and d.dup_role == "extra" and extra not in d.albums:
            d.albums.append(extra)
        if not d.categories:
            d.unsorted = True
            if self.cfg.unsorted_album:
                d.albums.append(self.cfg.unsorted_album)
        return d
