"""Command line: doctor · estimate · scan (dry run) · apply · demo · download-model."""

from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

from . import __version__
from .cache import Cache
from .config import ConfigError, load_config
from .progress import fmt_secs

TOOL_DIR = Path(__file__).resolve().parent.parent


def out_root(args) -> Path:
    root = Path(args.out or os.environ.get("PHOTOSORT_OUT") or TOOL_DIR / "output").expanduser()
    root.mkdir(parents=True, exist_ok=True)
    gi = root / ".gitignore"       # outputs hold personal data: make the folder ignore itself
    if not gi.exists():
        gi.write_text("*\n", encoding="utf-8")
    return root


def open_cache(args) -> Cache:
    return Cache(Path(args.cache).expanduser() if args.cache else out_root(args) / "cache.sqlite")


def parse_since(value: str | None, cache: Cache) -> datetime | None:
    if not value:
        return None
    v = value.strip().lower()
    if v == "last":
        ts = cache.get_kv("last_scan_started")
        if ts is None:
            print("--since last: no earlier scan recorded, scanning everything.", file=sys.stderr)
            return None
        return datetime.fromtimestamp(float(ts)).astimezone()
    if v.endswith("d") and v[:-1].isdigit():
        return (datetime.now() - timedelta(days=int(v[:-1]))).astimezone()
    try:
        return datetime.fromisoformat(value).astimezone()
    except ValueError:
        raise SystemExit(f"--since: could not understand '{value}' (use 2026-11-01, 7d, or last)")


def _after(iso: str | None, since: datetime) -> bool:
    if not iso:
        return False
    try:
        return datetime.fromisoformat(iso).astimezone() >= since
    except ValueError:
        return False


def select_records(records, since: datetime | None, limit: int | None):
    sel = records
    if since is not None:
        sel = [r for r in sel if _after(r.date_added or r.date, since)]
    if limit:
        sel = sorted(sel, key=lambda r: r.date or "", reverse=True)[:limit]
    return sel


def _open_file(path: str):
    try:
        if sys.platform == "darwin":
            subprocess.run(["open", path], check=False)
    except Exception:
        pass


def _latest(root: Path) -> Path | None:
    p = root / "latest.txt"
    if p.exists():
        run = Path(p.read_text(encoding="utf-8").strip())
        if run.exists():
            return run
    return None


def _make_backend(cfg, args):
    from .clipper import make_backend

    if getattr(args, "no_clip", False):
        return None
    return make_backend(cfg.clip, quiet=args.quiet)


# ---------------------------------------------------------------- commands
def cmd_scan(args) -> int:
    from .library import LibraryError, load_library
    from .pipeline import run_scan
    from .report import write_report

    cfg = load_config(args.config)
    root = out_root(args)
    cache = open_cache(args)
    started = time.time()
    since = parse_since(args.since, cache)
    try:
        records, info = load_library(args.library, quiet=args.quiet, ai_captions=args.ai_captions,
                                     include_hidden=getattr(args, "include_hidden", False))
    except LibraryError as e:
        print(str(e), file=sys.stderr)
        return 2
    cache.put_records(records)
    selected = select_records(records, since, args.limit)
    print(f"Library: {len(records):,} items; sorting {len(selected):,}"
          + (f" added since {since:%Y-%m-%d %H:%M}" if since else "")
          + (f" (limit {args.limit})" if args.limit else ""), file=sys.stderr)
    if not selected:
        print("Nothing to sort.", file=sys.stderr)
        return 0
    backend = _make_backend(cfg, args)
    try:
        result = run_scan(records, selected, cfg, cache, backend=backend, quiet=args.quiet)
    except KeyboardInterrupt:
        return 130
    run_dir = root / "runs" / time.strftime("%Y%m%d-%H%M%S")
    bits = []
    if args.since:
        bits.append(f"since {args.since}")
    if args.limit:
        bits.append(f"limit {args.limit}")
    rep = write_report(run_dir, result, cfg, info, samples=args.samples, run_args=", ".join(bits))
    (root / "latest.txt").write_text(str(run_dir), encoding="utf-8")
    if not args.limit:
        cache.set_kv("last_scan_started", started)
    cache.close()
    print("\nDRY RUN — nothing was changed in Photos.\n")
    width = max(len(a) for a in rep["plan"]["albums"])
    for a, u in rep["plan"]["albums"].items():
        print(f"  {a:<{width}}  {len(u):>7,}")
    st = result.stats
    print(f"\n  analysed {st.get('analysed', 0):,} thumbnails ({st.get('cached', 0):,} from cache, "
          f"{st.get('nothumb', 0):,} without a local preview, {st.get('errors', 0):,} unreadable); "
          f"CLIP {'on' if result.clip_used else 'off'}; took {fmt_secs(time.time() - started)}")
    print(f"\nReport: {rep['report']}\nCSV:    {run_dir / 'photos.csv'}\nSheets: {run_dir / 'sheets'}")
    print("\nNext:   ./sortphotos apply      (adds photos to albums; never deletes/moves/edits)")
    if not args.no_open:
        _open_file(rep["report"])
    return 0


def cmd_apply(args) -> int:
    from .apply import ApplyError, PhotoScriptWriter, apply_plan

    root = out_root(args)
    plan_path = Path(args.plan).expanduser() if args.plan else None
    if plan_path is None:
        run = _latest(root)
        if run is None:
            print("No scan found. Run ./sortphotos scan first and look at the report.", file=sys.stderr)
            return 2
        plan_path = run / "plan.json"
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    if str(plan.get("library", "")).startswith("fake:"):
        print("That plan is from the demo library — there is nothing real to apply. Run ./sortphotos scan first.",
              file=sys.stderr)
        return 2
    only = [s.strip() for s in args.only.split(",")] if args.only else None
    skip = [s.strip() for s in args.skip.split(",")] if args.skip else None
    cache = open_cache(args)
    print(f"Plan: {plan_path}  (scan of {plan['created']}, {plan['photos_scanned']:,} items)")
    print(f"Folder in Photos: “{plan['folder']}”")
    total = 0
    for a, u in plan["albums"].items():
        if not u or (only and a not in only) or (skip and a in skip):
            continue
        new = len(set(u) - (set() if args.readd else cache.applied_for(a)))
        total += new
        print(f"  {a:<28} {len(u):>7,} in plan, {new:>7,} to add")
    if args.dry_run:
        print("\n--dry-run: nothing done.")
        return 0
    if total == 0:
        print("\nEverything in this plan is already applied. Nothing to do.")
        return 0
    if not args.yes:
        print(f"\nThis adds {total:,} album entries in Photos. It only ADDS to albums — no photo is deleted, "
              "moved or edited.")
        try:
            if input("Type yes to continue: ").strip().lower() not in ("y", "yes"):
                print("Cancelled.")
                return 1
        except EOFError:
            print("\nNo terminal to confirm on — re-run with --yes.", file=sys.stderr)
            return 1
    try:
        writer = PhotoScriptWriter()
        summary = apply_plan(plan, writer, cache, only=only, skip=skip, quiet=args.quiet,
                             chunk=args.chunk, readd=args.readd)
    except ApplyError as e:
        print(str(e), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130
    print("\nDone.")
    for a, s in summary["albums"].items():
        print(f"  {a:<28} +{s['added']:,}" + (" (new album)" if s["created"] else "")
              + (f", {s['already']:,} already there" if s["already"] else ""))
    if summary["failed"]:
        log = plan_path.parent / "apply-failed.json"
        log.write_text(json.dumps(summary["failed"], indent=1), encoding="utf-8")
        print(f"  {len(summary['failed'])} could not be added (deleted since the scan?) — see {log}")
    print(f"\nOpen Photos > sidebar > Albums > “{summary['folder']}”.")
    return 0


def cmd_doctor(args) -> int:
    ok = True

    def line(good, text, hint=""):
        nonlocal ok
        mark = "OK  " if good else ("WARN" if good is None else "FAIL")
        if good is False:
            ok = False
        print(f"[{mark}] {text}" + (f"\n       -> {hint}" if hint and not good else ""))

    print(f"photosort {__version__}")
    mac = sys.platform == "darwin"
    line(mac, f"macOS ({platform.platform()})",
         "This is not a Mac. Photos can only be read/changed from macOS itself — if Claude's shell says Linux, "
         "it is in a sandbox: run these commands in Terminal.app on the Mac instead.")
    line(sys.version_info >= (3, 10), f"Python {platform.python_version()}", "need Python 3.10+")
    try:
        import osxphotos

        line(True, f"osxphotos {osxphotos.__version__}")
    except Exception as e:
        line(False, f"osxphotos import failed: {e}", "run ./install.sh")
    try:
        load_config(args.config)
        line(True, "categories.yaml is valid")
    except ConfigError as e:
        line(False, f"config: {e}")
    lib = args.library
    if lib is None:
        from .library import default_library_path

        lib = default_library_path()
    if lib:
        db = Path(lib).expanduser() / "database" / "Photos.sqlite"
        try:
            with open(db, "rb") as fh:
                fh.read(16)
            line(True, f"Photos library is readable: {lib}")
        except PermissionError:
            line(False, f"Photos library is blocked: {lib}",
                 "System Settings > Privacy & Security > Full Disk Access > enable the app running this "
                 "(Terminal or Claude), then quit and reopen that app.")
        except OSError as e:
            line(False, f"Photos library not readable ({e})", "pass --library /path/to/Photos Library.photoslibrary")
    else:
        line(False if mac else None, "no Photos library found", "pass --library /path/to/Photos Library.photoslibrary")
    from .clipper import clip_installed

    if clip_installed():
        import torch

        dev = "mps (Apple GPU)" if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available() \
            else ("cuda" if torch.cuda.is_available() else "cpu")
        line(True, f"CLIP available (torch {torch.__version__}, device {dev})")
    else:
        line(None, "CLIP not installed — scans will use Photos metadata only", "./install.sh (without --no-clip)")
    if mac:
        try:
            import photoscript  # noqa: F401

            line(True, "photoscript available (needed for apply)")
            if args.automation:
                v = photoscript.PhotosLibrary().version
                line(True, f"Photos answers to automation (Photos {v})")
        except Exception as e:
            line(False, f"photoscript / Photos automation: {e}",
                 "System Settings > Privacy & Security > Automation > allow Photos for this app")
    print("\nAll good." if ok else "\nFix the FAIL lines above, then run ./sortphotos doctor again.")
    return 0 if ok else 1


def cmd_estimate(args) -> int:
    from .features import compute_features, file_sig, load_image
    from .library import LibraryError, load_library

    cfg = load_config(args.config)
    cache = open_cache(args)
    try:
        records, _ = load_library(args.library, quiet=args.quiet)
    except LibraryError as e:
        print(str(e), file=sys.stderr)
        return 2
    feats = cache.get_features()
    with_thumb = [r for r in records if r.thumb_path]
    todo = [r for r in with_thumb if feats.get(r.uuid, ("", None))[0] != file_sig(r.thumb_path)]
    sample = todo[:: max(1, len(todo) // 48)][:48] or with_thumb[:48]
    t0 = time.time()
    images = []
    for r in sample:
        try:
            im = load_image(r.thumb_path)
            compute_features(im)
            images.append(im)
        except Exception:
            pass
    per_feat = (time.time() - t0) / max(1, len(sample))
    per_clip, device = 0.0, "off"
    backend = _make_backend(cfg, args)
    if backend is not None and images:
        backend.embed_images(images[:8])            # warm-up
        t0 = time.time()
        backend.embed_images(images[:32])
        per_clip, device = (time.time() - t0) / len(images[:32]), backend.device
    n = len(todo)
    print(f"\nLibrary: {len(records):,} items · {len(with_thumb):,} with a local preview · "
          f"{len(records) - len(with_thumb):,} iCloud-only without one · {len(with_thumb) - n:,} already cached")
    print(f"Measured on this machine: {per_feat * 1000:.0f} ms/photo hashing+blur, "
          f"{per_clip * 1000:.0f} ms/photo CLIP ({device})")
    print(f"Estimated first scan: about {fmt_secs(n * (per_feat / 3 + per_clip) + 30 + len(records) * 0.002)} "
          f"for {n:,} photos to analyse" + ("" if backend else f" (metadata + hashes only; no CLIP)"))
    print("Re-runs and --since runs only analyse new photos. Apply: roughly 1-3 min per 1,000 album adds.")
    return 0


def cmd_demo(args) -> int:
    from .demo import make_demo_library

    args.out = str(out_root(args) / "demo")      # kept apart so it can never become the plan `apply` uses
    root = out_root(args)
    lib = make_demo_library(root / "demo-library")
    print(f"Demo library (generated shapes, made-up metadata): {lib}")
    args.library, args.since, args.limit, args.ai_captions = f"fake:{lib}", None, None, False
    args.cache = str(root / "demo-cache.sqlite")
    args.no_clip = True
    return cmd_scan(args)


def cmd_download_model(args) -> int:
    from .clipper import ClipUnavailable, OpenClipBackend

    cfg = load_config(args.config)
    try:
        b = OpenClipBackend(cfg.clip.get("model"), cfg.clip.get("pretrained"), quiet=False)
        b.embed_texts(["a photo"])
    except ClipUnavailable as e:
        print(f"CLIP model not ready: {e}", file=sys.stderr)
        return 1
    print(f"CLIP model ready on {b.device}.")
    return 0


def main(argv=None) -> int:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--config", help="categories YAML (default: categories.yaml next to the tool)")
    common.add_argument("--out", help="output folder (default: ./output, gitignored)")
    common.add_argument("--cache", help="sqlite cache path (default: <out>/cache.sqlite)")
    common.add_argument("--library", help="Photos library path (default: the system library)")
    common.add_argument("--quiet", action="store_true")
    ap = argparse.ArgumentParser(prog="photosort", description="Sort an Apple Photos library into albums. "
                                 "Dry run by default; apply only ever adds photos to albums.")
    ap.add_argument("--version", action="version", version=__version__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def scan_opts(p):
        p.add_argument("--no-clip", action="store_true", help="skip the CLIP model (metadata only)")
        p.add_argument("--samples", type=int, default=24, help="thumbnails per album in the report")
        p.add_argument("--no-open", action="store_true", help="do not open the report when done")

    p = sub.add_parser("scan", parents=[common], help="DRY RUN: analyse and write report + CSV (changes nothing)")
    scan_opts(p)
    p.add_argument("--since", help="only sort items added since: YYYY-MM-DD, 7d, or 'last' (last full scan)")
    p.add_argument("--limit", type=int, help="only the N most recent items (quick trial)")
    p.add_argument("--ai-captions", action="store_true", help="also read Photos' AI captions (slower)")
    p.add_argument("--include-hidden", action="store_true", help="also sort photos in the Hidden album")
    p.set_defaults(fn=cmd_scan)

    p = sub.add_parser("apply", parents=[common], help="add photos to albums from the last scan's plan")
    p.add_argument("--plan", help="plan.json to apply (default: latest scan)")
    p.add_argument("--only", help="comma-separated album names to apply")
    p.add_argument("--skip", help="comma-separated album names to leave out")
    p.add_argument("--yes", action="store_true", help="do not ask for confirmation")
    p.add_argument("--dry-run", action="store_true", help="show what would be added, do nothing")
    p.add_argument("--readd", action="store_true", help="also re-add photos added by an earlier apply")
    p.add_argument("--chunk", type=int, default=200, help=argparse.SUPPRESS)
    p.set_defaults(fn=cmd_apply)

    p = sub.add_parser("doctor", parents=[common], help="check permissions and setup")
    p.add_argument("--automation", action="store_true", help="also check that Photos can be controlled")
    p.set_defaults(fn=cmd_doctor)

    p = sub.add_parser("estimate", parents=[common], help="measure speed on this Mac and estimate the scan time")
    p.add_argument("--no-clip", action="store_true")
    p.set_defaults(fn=cmd_estimate)

    p = sub.add_parser("demo", parents=[common], help="dry run on a generated fake library (no Photos access)")
    scan_opts(p)
    p.set_defaults(fn=cmd_demo)

    p = sub.add_parser("download-model", parents=[common], help="download/verify the CLIP model")
    p.set_defaults(fn=cmd_download_model)

    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except ConfigError as e:
        print(f"Config error: {e}", file=sys.stderr)
        return 2
