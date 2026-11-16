"""Apply a reviewed plan to Photos. The ONLY changes this module can make are:

    1. create the top-level folder          (if it does not exist)
    2. create an album inside that folder   (if it does not exist)
    3. add existing photos to those albums

It never deletes, removes, moves, renames, edits or imports anything. Adding a photo that is
already in an album is a no-op in Photos, and every add is also remembered in the cache, so
re-running is safe (idempotent) and a photo you later take OUT of an album is not put back.
"""

from __future__ import annotations

import sys

from .cache import Cache
from .progress import Progress

AUTOMATION_HELP = """
Photos did not accept the request. If macOS showed "… wants access to control Photos", click
Allow. Otherwise: System Settings > Privacy & Security > Automation > (Terminal / Claude) >
turn ON "Photos", then run the command again.
"""


class ApplyError(RuntimeError):
    pass


class PhotoScriptWriter:
    """Thin add-only wrapper over PhotoScript (AppleScript bridge to Photos.app). macOS only."""

    def __init__(self):
        if sys.platform != "darwin":
            raise ApplyError("apply needs macOS with the Photos app (this machine is not a Mac).")
        try:
            import photoscript
            from photoscript.script_loader import run_script
        except ImportError as e:
            raise ApplyError("photoscript is not installed — run ./install.sh") from e
        self._ps = photoscript
        self._run = run_script
        try:
            self._lib = photoscript.PhotosLibrary()
        except Exception as e:
            raise ApplyError(f"Could not talk to Photos: {e}\n{AUTOMATION_HELP}") from e
        self._folder = None

    def ensure_folder(self, name: str) -> bool:
        folder = self._lib.folder(name=name, top_level=True)
        created = folder is None
        if created:
            folder = self._lib.create_folder(name)
        self._folder = folder
        return created

    def ensure_album(self, name: str):
        album = self._folder.album(name)
        if album is None:
            album = self._lib.create_album(name, folder=self._folder)
            return album, True
        return album, False

    def add(self, album, uuids: list[str]) -> None:
        ids = [self._ps.uuid_to_id(u, self._ps.UUID_SUFFIX_PHOTO)[1] for u in uuids]
        self._run("albumAdd", album.id, ids)


def apply_plan(plan: dict, writer, cache: Cache, only: list[str] | None = None, skip: list[str] | None = None,
               quiet: bool = False, chunk: int = 200, readd: bool = False) -> dict:
    """Create folder/albums and add photos. `writer` needs ensure_folder / ensure_album / add."""
    albums = {a: u for a, u in plan["albums"].items() if u}
    if only:
        missing = [a for a in only if a not in plan["albums"]]
        if missing:
            raise ApplyError(f"not in the plan: {missing}. Albums in plan: {sorted(plan['albums'])}")
        albums = {a: u for a, u in albums.items() if a in only}
    if skip:
        albums = {a: u for a, u in albums.items() if a not in skip}
    summary = {"folder": plan["folder"], "folder_created": False, "albums": {}, "failed": []}
    if not albums:
        return summary
    summary["folder_created"] = writer.ensure_folder(plan["folder"])
    todo = {}
    for a, uuids in albums.items():
        done = set() if readd else cache.applied_for(a)
        todo[a] = [u for u in dict.fromkeys(uuids) if u not in done]
    total = sum(len(v) for v in todo.values())
    with Progress(max(total, 1), "add to albums", quiet=quiet) as bar:
        for a, uuids in todo.items():
            handle, created = writer.ensure_album(a)
            added = 0
            for s in range(0, len(uuids), chunk):
                part = uuids[s:s + chunk]
                try:
                    writer.add(handle, part)
                    ok = part
                except KeyboardInterrupt:
                    print("\nInterrupted — what was added so far is recorded; run apply again to continue.",
                          file=sys.stderr)
                    raise
                except Exception:
                    ok = []          # one bad id fails a whole batch: retry one by one
                    for u in part:
                        try:
                            writer.add(handle, [u])
                            ok.append(u)
                        except Exception as e:
                            summary["failed"].append({"album": a, "uuid": u, "error": str(e)[:200]})
                cache.mark_applied(a, ok)
                added += len(ok)
                bar.update(len(part))
            summary["albums"][a] = {"created": created, "added": added,
                                    "already": len(dict.fromkeys(albums[a])) - len(uuids)}
    return summary
