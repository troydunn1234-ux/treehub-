"""Normalized per-photo record. Everything downstream works on this, not on osxphotos objects."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field, fields


@dataclass
class PhotoRecord:
    uuid: str
    filename: str = ""
    date: str | None = None          # ISO date taken
    date_added: str | None = None    # ISO date added to library
    width: int = 0
    height: int = 0
    filesize: int = 0
    uti: str = ""
    # flags from Photos
    is_movie: bool = False
    is_screenshot: bool = False
    is_screen_recording: bool = False
    is_selfie: bool = False
    is_live: bool = False
    is_portrait: bool = False
    is_panorama: bool = False
    is_burst: bool = False
    is_slow_mo: bool = False
    is_time_lapse: bool = False
    is_hdr: bool = False
    is_favorite: bool = False
    is_hidden: bool = False
    is_missing: bool = False         # original is iCloud-only (not on this Mac)
    has_adjustments: bool = False
    # content metadata
    labels: list[str] = field(default_factory=list)        # Apple ML labels, lowercase
    search_terms: list[str] = field(default_factory=list)  # venue types, activities, ... lowercase
    persons: list[str] = field(default_factory=list)       # named people only
    face_count: int = 0
    title: str = ""
    caption: str = ""
    ai_caption: str = ""
    keywords: list[str] = field(default_factory=list)
    albums: list[str] = field(default_factory=list)
    # where / how
    latitude: float | None = None
    longitude: float | None = None
    place: str = ""
    has_exif: bool = False
    camera_make: str = ""
    camera_model: str = ""
    lens_model: str = ""
    imported_by: str = ""            # bundle id of the app that saved it, if known
    score_overall: float | None = None
    score_failure: float | None = None
    # files (never committed anywhere; local paths only)
    thumb_path: str | None = None    # best local preview to analyse
    original_path: str | None = None

    def flags(self) -> set[str]:
        out = set()
        for name, attr in _FLAG_ATTRS.items():
            if getattr(self, attr):
                out.add(name)
        if "front" in (self.lens_model or "").lower() and not self.is_movie:
            out.add("front_camera")
        if self.uti == "com.compuserve.gif":
            out.add("gif")
        return out

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "PhotoRecord":
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in d.items() if k in known})


_FLAG_ATTRS = {
    "video": "is_movie",
    "screenshot": "is_screenshot",
    "screen_recording": "is_screen_recording",
    "selfie": "is_selfie",
    "live": "is_live",
    "portrait": "is_portrait",
    "panorama": "is_panorama",
    "burst": "is_burst",
    "slow_mo": "is_slow_mo",
    "time_lapse": "is_time_lapse",
    "hdr": "is_hdr",
    "favorite": "is_favorite",
    "hidden": "is_hidden",
    "icloud_only": "is_missing",
    "edited": "has_adjustments",
}

KNOWN_FLAGS = set(_FLAG_ATTRS) | {"front_camera", "gif"}


@dataclass
class Features:
    """Things measured from the thumbnail."""

    phash: int | None = None
    dhash: int | None = None
    sharp: float | None = None
    mean: float | None = None
    std: float | None = None
    status: str = "ok"   # ok | nothumb | error
