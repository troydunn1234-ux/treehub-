"""Load and validate categories.yaml (+ optional categories.local.yaml overlay)."""

from __future__ import annotations

import copy
import hashlib
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from .model import KNOWN_FLAGS

RULES = {"people", "saved", "travel", "duplicates", "review"}
DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "categories.yaml"


class ConfigError(ValueError):
    pass


@dataclass
class Category:
    name: str
    album: str
    threshold: float
    rule: str | None = None
    flags: list[str] = field(default_factory=list)
    exclude_flags: list[str] = field(default_factory=list)
    labels: list[str] = field(default_factory=list)
    weak_labels: list[str] = field(default_factory=list)
    exclude_labels: list[str] = field(default_factory=list)
    search: list[str] = field(default_factory=list)
    keywords: list[str] = field(default_factory=list)
    prompts: list[str] = field(default_factory=list)
    clip_weight: float = 1.0
    enabled: bool = True


@dataclass
class Config:
    folder: str
    unsorted_album: str | None
    threshold: float
    label_strength: dict
    clip: dict
    travel: dict
    duplicates: dict
    review: dict
    categories: list[Category]
    path: str = ""

    def category(self, name: str) -> Category | None:
        return next((c for c in self.categories if c.name == name), None)

    def by_rule(self, rule: str) -> Category | None:
        return next((c for c in self.categories if c.rule == rule and c.enabled), None)

    @property
    def active(self) -> list[Category]:
        return [c for c in self.categories if c.enabled]

    def clip_model_id(self) -> str:
        return f"{self.clip.get('model')}|{self.clip.get('pretrained')}"

    def album_names(self) -> list[str]:
        names = []
        for c in self.active:
            if c.album not in names:
                names.append(c.album)
        extra = self.duplicates.get("extras_album")
        if extra and extra not in names:
            names.append(extra)
        if self.unsorted_album and self.unsorted_album not in names:
            names.append(self.unsorted_album)
        return names


_DEFAULTS = {
    "folder": "Sorted by Claude",
    "unsorted_album": "Unsorted",
    "threshold": 0.5,
    "label_strength": {"strong": 0.85, "weak": 0.35, "search": 0.40, "keyword": 0.80},
    "clip": {
        "backend": "auto",
        "model": "ViT-B-32",
        "pretrained": "laion2b_s34b_b79k",
        "temperature": 100,
        "background_prompts": ["a photo"],
    },
    "travel": {"home": "auto", "min_km": 150, "min_gps_photos": 25},
    "duplicates": {
        "max_distance": 6,
        "similar_distance": 12,
        "similar_window_seconds": 120,
        "include_videos": False,
        "extras_album": None,
    },
    "review": {
        "blur_soft": 14.0,
        "blur_strict": 8.0,
        "dark_mean": 14,
        "dark_std": 12,
        "flat_std": 5,
        "exempt_labels": [],
    },
}


def _merge(base: dict, over: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in (over or {}).items():
        if k == "categories":
            cats = {c["name"]: c for c in out.get("categories", [])}
            order = [c["name"] for c in out.get("categories", [])]
            for c in v or []:
                if "name" not in c:
                    raise ConfigError("every category needs a name")
                if c["name"] in cats:
                    cats[c["name"]] = {**cats[c["name"]], **c}
                else:
                    cats[c["name"]] = c
                    order.append(c["name"])
            out["categories"] = [cats[n] for n in order]
        elif isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = {**out[k], **v}
        else:
            out[k] = v
    return out


def _strlist(v, where: str) -> list[str]:
    if v is None:
        return []
    if not isinstance(v, list):
        raise ConfigError(f"{where} must be a list")
    return [str(x).strip().lower() for x in v if str(x).strip()]


def parse_config(raw: dict, path: str = "") -> Config:
    if not isinstance(raw, dict):
        raise ConfigError("config must be a mapping")
    names = [str(c.get("name", "")).strip() for c in raw.get("categories") or [] if isinstance(c, dict)]
    dupes = sorted({n for n in names if n and names.count(n) > 1})
    if dupes:
        raise ConfigError(f"duplicate category name: {dupes}")
    data = _merge(_DEFAULTS, raw)
    thr = float(data["threshold"])
    cats: list[Category] = []
    seen = set()
    for c in data.get("categories") or []:
        name = str(c.get("name", "")).strip()
        if not name:
            raise ConfigError("every category needs a name")
        if name in seen:
            raise ConfigError(f"duplicate category name: {name}")
        seen.add(name)
        where = f"category '{name}'"
        unknown = set(c) - {
            "name", "album", "threshold", "rule", "flags", "exclude_flags", "labels", "weak_labels",
            "exclude_labels", "search", "keywords", "prompts", "clip_weight", "enabled",
        }
        if unknown:
            raise ConfigError(f"{where}: unknown keys {sorted(unknown)}")
        rule = c.get("rule")
        if rule is not None and rule not in RULES:
            raise ConfigError(f"{where}: unknown rule '{rule}' (use one of {sorted(RULES)})")
        t = float(c.get("threshold", thr))
        if not 0 < t <= 1:
            raise ConfigError(f"{where}: threshold must be in (0, 1]")
        flags = _strlist(c.get("flags"), where + ".flags")
        xflags = _strlist(c.get("exclude_flags"), where + ".exclude_flags")
        bad = (set(flags) | set(xflags)) - KNOWN_FLAGS
        if bad:
            raise ConfigError(f"{where}: unknown flags {sorted(bad)} (known: {sorted(KNOWN_FLAGS)})")
        album = str(c.get("album") or name).strip()
        if "/" in album:
            raise ConfigError(f"{where}: album names cannot contain '/'")
        cats.append(
            Category(
                name=name, album=album, threshold=t, rule=rule, flags=flags, exclude_flags=xflags,
                labels=_strlist(c.get("labels"), where + ".labels"),
                weak_labels=_strlist(c.get("weak_labels"), where + ".weak_labels"),
                exclude_labels=_strlist(c.get("exclude_labels"), where + ".exclude_labels"),
                search=_strlist(c.get("search"), where + ".search"),
                keywords=_strlist(c.get("keywords"), where + ".keywords"),
                prompts=[str(p).strip() for p in (c.get("prompts") or []) if str(p).strip()],
                clip_weight=float(c.get("clip_weight", 1.0)),
                enabled=bool(c.get("enabled", True)),
            )
        )
    if not cats:
        raise ConfigError("no categories defined")
    folder = str(data["folder"]).strip()
    if not folder or "/" in folder:
        raise ConfigError("folder must be a non-empty name without '/'")
    md = int(data["duplicates"]["max_distance"])
    if not 0 <= md <= 7:
        raise ConfigError("duplicates.max_distance must be between 0 and 7")
    home = data["travel"].get("home", "auto")
    if home != "auto" and not (isinstance(home, (list, tuple)) and len(home) == 2):
        raise ConfigError("travel.home must be 'auto' or [lat, lon]")
    un = data.get("unsorted_album")
    return Config(
        folder=folder,
        unsorted_album=str(un).strip() if un else None,
        threshold=thr,
        label_strength=data["label_strength"],
        clip=data["clip"],
        travel=data["travel"],
        duplicates=data["duplicates"],
        review=data["review"],
        categories=cats,
        path=path,
    )


def load_config(path: str | Path | None = None) -> Config:
    p = Path(path) if path else DEFAULT_CONFIG
    if not p.exists():
        raise ConfigError(f"config not found: {p}")
    raw = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    local = p.with_name(p.stem + ".local" + p.suffix)
    if local.exists():
        raw = _merge(raw, yaml.safe_load(local.read_text(encoding="utf-8")) or {})
    return parse_config(raw, str(p))


def prompt_hash(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:16]
