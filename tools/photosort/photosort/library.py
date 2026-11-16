"""Read the Photos library (via osxphotos) into PhotoRecord objects. READ-ONLY.

osxphotos works on a temporary copy of the Photos database, so nothing here can change
the library. No originals are downloaded: for iCloud-only photos we use whatever preview
Photos already keeps on this Mac, or fall back to metadata only.

`fake:<dir>` libraries (a library.json + images, see demo.py) let the whole pipeline run
without Photos, for the demo and the tests.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from .features import IMAGE_EXTS
from .model import PhotoRecord
from .progress import Progress

FDA_HELP = """
Could not read the Photos library — macOS is blocking access.
Fix: System Settings > Privacy & Security > Full Disk Access > turn ON the app that runs
this command (Terminal, iTerm, or Claude), then quit and reopen that app and try again.
"""


class LibraryError(RuntimeError):
    pass


def _get(obj, name, default=None):
    try:
        v = getattr(obj, name)
        return default if v is None else v
    except Exception:
        return default


def _iso(dt) -> str | None:
    try:
        return dt.isoformat() if dt else None
    except Exception:
        return None


def _lower_list(v) -> list[str]:
    out = []
    for x in v or []:
        s = str(x).strip().lower()
        if s and s not in out:
            out.append(s)
    return out


def pick_thumb(derivatives: list[str], original: str | None, is_movie: bool) -> str | None:
    """Smallest preview that is still big enough to analyse; original only if it is local."""
    cands = []
    for p in derivatives or []:
        if Path(p).suffix.lower() in IMAGE_EXTS:
            try:
                cands.append((os.path.getsize(p), p))
            except OSError:
                continue
    if cands:
        cands.sort()
        good = [c for c in cands if c[0] >= 60_000]
        return (good[0] if good else cands[-1])[1]
    if original and not is_movie and Path(original).suffix.lower() in IMAGE_EXTS and os.path.exists(original):
        return original
    return None


def record_from_photo(p, ai_captions: bool = False) -> PhotoRecord:
    persons_all = list(_get(p, "persons", []) or [])
    named = [n for n in persons_all if n and not str(n).startswith("_UNKNOWN")]
    si = _get(p, "search_info_normalized")
    terms: list[str] = []
    if si is not None:
        for attr in ("venue_types", "activities", "media_types", "document_types", "human_actions", "event_types"):
            terms += _lower_list(_get(si, attr, []))
    exif = _get(p, "exif_info")
    score = _get(p, "score")
    place = _get(p, "place")
    imported = _get(p, "imported_by", (None, None)) or (None, None)
    original = _get(p, "path")
    is_movie = bool(_get(p, "ismovie", False))
    return PhotoRecord(
        uuid=p.uuid,
        filename=_get(p, "original_filename", "") or _get(p, "filename", "") or "",
        date=_iso(_get(p, "date")),
        date_added=_iso(_get(p, "date_added")),
        width=int(_get(p, "width", 0) or 0),
        height=int(_get(p, "height", 0) or 0),
        filesize=int(_get(p, "original_filesize", 0) or 0),
        uti=_get(p, "uti", "") or "",
        is_movie=is_movie,
        is_screenshot=bool(_get(p, "screenshot", False)),
        is_screen_recording=bool(_get(p, "screen_recording", False)),
        is_selfie=bool(_get(p, "selfie", False)),
        is_live=bool(_get(p, "live_photo", False)),
        is_portrait=bool(_get(p, "portrait", False)),
        is_panorama=bool(_get(p, "panorama", False)),
        is_burst=bool(_get(p, "burst", False)),
        is_slow_mo=bool(_get(p, "slow_mo", False)),
        is_time_lapse=bool(_get(p, "time_lapse", False)),
        is_hdr=bool(_get(p, "hdr", False)),
        is_favorite=bool(_get(p, "favorite", False)),
        is_hidden=bool(_get(p, "hidden", False)),
        is_missing=bool(_get(p, "ismissing", False)),
        has_adjustments=bool(_get(p, "hasadjustments", False)),
        labels=_lower_list(_get(p, "labels_normalized", [])),
        search_terms=_lower_list(terms),
        persons=named,
        face_count=len(persons_all),
        title=_get(p, "title", "") or "",
        caption=_get(p, "description", "") or "",
        ai_caption=(_get(p, "ai_caption", "") or "") if ai_captions else "",
        keywords=_lower_list(_get(p, "keywords", [])),
        albums=[str(a) for a in (_get(p, "albums", []) or [])],
        latitude=_get(p, "latitude"),
        longitude=_get(p, "longitude"),
        place=(_get(place, "name", "") or "") if place is not None else "",
        has_exif=exif is not None,
        camera_make=(_get(exif, "camera_make", "") or "") if exif is not None else "",
        camera_model=(_get(exif, "camera_model", "") or "") if exif is not None else "",
        lens_model=(_get(exif, "lens_model", "") or "") if exif is not None else "",
        imported_by=str(imported[1] or imported[0] or ""),
        score_overall=_get(score, "overall") if score is not None else None,
        score_failure=_get(score, "failure") if score is not None else None,
        thumb_path=pick_thumb(_get(p, "path_derivatives", []) or [], original, is_movie),
        original_path=original,
    )


def default_library_path() -> str | None:
    try:
        from osxphotos.utils import get_last_library_path, get_system_library_path

        return get_system_library_path() or get_last_library_path()
    except Exception:
        return None


def load_osxphotos(library: str | None, quiet: bool = False, ai_captions: bool = False,
                   include_hidden: bool = False):
    try:
        import osxphotos
    except ImportError as e:  # pragma: no cover
        raise LibraryError("osxphotos is not installed — run ./install.sh first") from e
    if library is None:
        library = default_library_path()
        if library is None and sys.platform != "darwin":
            raise LibraryError("No Photos library found. On macOS this is automatic; elsewhere pass --library PATH.")
    if library is not None:
        library = os.path.expanduser(library)
        if not os.path.exists(library):
            raise LibraryError(f"Photos library not found: {library}")
    if not quiet:
        print(f"Opening Photos library (read-only): {library or 'default'} ...", file=sys.stderr, flush=True)
    try:
        db = osxphotos.PhotosDB(dbfile=library) if library else osxphotos.PhotosDB()
    except PermissionError as e:
        raise LibraryError(FDA_HELP) from e
    except Exception as e:
        msg = str(e)
        if "not permitted" in msg or "Permission denied" in msg or "authorization denied" in msg:
            raise LibraryError(FDA_HELP) from e
        raise LibraryError(f"Could not open the Photos library: {msg}") from e
    photos = db.photos()  # excludes Recently Deleted
    # shared-album items cannot be added to your own albums; hidden photos stay private unless asked for
    photos = [p for p in photos if not _get(p, "shared", False) and (include_hidden or not _get(p, "hidden", False))]
    records = []
    with Progress(len(photos), "read metadata", quiet=quiet) as bar:
        for p in photos:
            try:
                records.append(record_from_photo(p, ai_captions=ai_captions))
            except Exception as e:  # one odd asset must not stop the run
                print(f"  skipped {getattr(p, 'uuid', '?')}: {e}", file=sys.stderr)
            bar.update()
    info = {"library": str(_get(db, "library_path", library) or ""), "photos_version": _get(db, "photos_version", None)}
    return records, info


def load_fake(directory: str):
    d = Path(directory)
    data = json.loads((d / "library.json").read_text(encoding="utf-8"))
    records = []
    for item in data["photos"]:
        r = PhotoRecord.from_dict(item)
        if r.thumb_path and not os.path.isabs(r.thumb_path):
            r.thumb_path = str(d / r.thumb_path)
        records.append(r)
    return records, {"library": f"fake:{d}", "photos_version": "fake"}


def load_library(library: str | None, quiet: bool = False, ai_captions: bool = False,
                 include_hidden: bool = False):
    if library and library.startswith("fake:"):
        return load_fake(library[5:])
    return load_osxphotos(library, quiet=quiet, ai_captions=ai_captions, include_hidden=include_hidden)
