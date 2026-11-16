"""Dry-run outputs: report.html (+ thumbs/ and contact sheets), photos.csv, albums.csv, plan.json.

Everything is written locally into the run folder. Nothing here talks to Photos.
"""

from __future__ import annotations

import csv
import html
import json
import random
import re
import time
from pathlib import Path

from PIL import Image, ImageDraw

from . import __version__
from .config import Config
from .features import load_image
from .pipeline import ScanResult

THUMB = 180
SHEET_CELL, SHEET_COLS = 150, 8


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "album"


def build_plan(result: ScanResult, cfg: Config, info: dict) -> dict:
    albums: dict[str, list[str]] = {a: [] for a in cfg.album_names()}
    for r in result.records:
        for a in result.decisions[r.uuid].albums:
            albums.setdefault(a, []).append(r.uuid)
    return {
        "photosort": __version__,
        "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "library": info.get("library", ""),
        "folder": cfg.folder,
        "photos_scanned": len(result.records),
        "albums": albums,
    }


def write_csvs(run_dir: Path, result: ScanResult, cfg: Config, plan: dict):
    cats = [c.name for c in cfg.active]
    with open(run_dir / "photos.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["uuid", "filename", "date", "kind", "albums", "top_category", "top_score", "why",
                    "flags", "labels", "people_count", "place", "km_from_home", "dup_group", "dup_role",
                    "sharpness", "brightness", "preview", "icloud_only"] + [f"score:{c}" for c in cats])
        for r in result.records:
            d = result.decisions[r.uuid]
            f = result.features.get(r.uuid)
            top = max(d.scores.items(), key=lambda kv: kv[1], default=("", 0.0))
            why = " || ".join(f"{c}: {d.reasons.get(c, '')}" for c in d.categories)
            w.writerow([
                r.uuid, r.filename, (r.date or "")[:19], "video" if r.is_movie else "photo",
                " | ".join(d.albums), top[0] if top[1] > 0 else "", f"{top[1]:.2f}", why,
                " ".join(sorted(r.flags())), " | ".join(r.labels[:12]), r.face_count, r.place,
                "" if d.km_from_home is None else d.km_from_home,
                "" if d.dup_group is None else d.dup_group, d.dup_role,
                "" if not f or f.sharp is None else f"{f.sharp:.1f}",
                "" if not f or f.mean is None else f"{f.mean:.0f}",
                "yes" if r.thumb_path else "no", "yes" if r.is_missing else "no",
            ] + [f"{d.scores.get(c, 0):.2f}" for c in cats])
    with open(run_dir / "albums.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["album", "photos"])
        for a, u in plan["albums"].items():
            w.writerow([a, len(u)])


class _Thumbs:
    def __init__(self, run_dir: Path, by_uuid: dict):
        self.dir = run_dir / "thumbs"
        self.dir.mkdir(exist_ok=True)
        self.by_uuid = by_uuid
        self.done: dict[str, str | None] = {}

    def get(self, uuid: str) -> str | None:
        if uuid in self.done:
            return self.done[uuid]
        rel = None
        r = self.by_uuid.get(uuid)
        if r is not None and r.thumb_path:
            try:
                im = load_image(r.thumb_path, THUMB * 2)
                im.thumbnail((THUMB, THUMB))
                rel = f"thumbs/{len(self.done):05d}.jpg"
                im.save(self.dir.parent / rel, "JPEG", quality=72)
            except Exception:
                rel = None
        self.done[uuid] = rel
        return rel


def _sheet(run_dir: Path, name: str, rels: list[str]):
    rels = [r for r in rels if r][:SHEET_COLS * 6]
    if not rels:
        return None
    rows = (len(rels) + SHEET_COLS - 1) // SHEET_COLS
    sheet = Image.new("RGB", (SHEET_COLS * SHEET_CELL, rows * SHEET_CELL + 24), (24, 24, 27))
    ImageDraw.Draw(sheet).text((6, 6), name, fill=(235, 235, 235))
    for i, rel in enumerate(rels):
        try:
            im = Image.open(run_dir / rel)
            im.thumbnail((SHEET_CELL - 6, SHEET_CELL - 6))
            x = (i % SHEET_COLS) * SHEET_CELL + (SHEET_CELL - im.width) // 2
            y = 24 + (i // SHEET_COLS) * SHEET_CELL + (SHEET_CELL - im.height) // 2
            sheet.paste(im, (x, y))
        except Exception:
            continue
    (run_dir / "sheets").mkdir(exist_ok=True)
    out = f"sheets/{slug(name)}.jpg"
    sheet.save(run_dir / out, "JPEG", quality=80)
    return out


CSS = """
:root{--bg:#f6f5f2;--card:#fff;--ink:#1c1b19;--mute:#6b6862;--line:#e4e1da;--acc:#2f6f4f;--warn:#a3541b}
@media(prefers-color-scheme:dark){:root{--bg:#161614;--card:#201f1d;--ink:#eceae5;--mute:#a09c94;--line:#34322e;--acc:#6fbf95;--warn:#e0915a}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:1180px;margin:0 auto;padding:28px 20px 80px}h1{font-size:26px;margin:0 0 4px}h2{font-size:19px;margin:0}
.sub{color:var(--mute);margin:0 0 20px}.banner{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--acc);padding:12px 16px;border-radius:8px;margin:0 0 20px}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-bottom:22px}
.tile{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px 14px}.tile b{display:block;font-size:22px;font-variant-numeric:tabular-nums}.tile span{color:var(--mute);font-size:13px}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:8px;overflow:hidden}
td,th{padding:7px 12px;text-align:left;border-bottom:1px solid var(--line);font-variant-numeric:tabular-nums}th{font-size:12px;color:var(--mute);text-transform:uppercase;letter-spacing:.04em}
td.n{text-align:right;width:90px}td.bar{width:45%}.b{height:10px;background:var(--acc);border-radius:2px;min-width:1px}
a{color:var(--acc)}section{margin-top:34px}.meta{color:var(--mute);font-size:13px;margin:2px 0 10px}
h3{font-size:12px;color:var(--mute);text-transform:uppercase;letter-spacing:.05em;margin:14px 0 6px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(120px,1fr));gap:6px}
figure{margin:0;background:var(--card);border:1px solid var(--line);border-radius:6px;overflow:hidden}
figure img,figure .ph{display:block;width:100%;aspect-ratio:1;object-fit:cover}.ph{display:grid;place-items:center;color:var(--mute);font-size:11px;text-align:center;padding:6px}
figcaption{font-size:11px;color:var(--mute);padding:3px 6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.keep{outline:3px solid var(--acc);outline-offset:-3px}.grp{display:flex;gap:6px;flex-wrap:wrap;padding:8px;background:var(--card);border:1px solid var(--line);border-radius:8px;margin-bottom:8px}.grp figure{width:120px}
code{background:var(--card);border:1px solid var(--line);padding:1px 6px;border-radius:4px}.warn{color:var(--warn)}
"""


def _fig(th: _Thumbs, r, caption: str, title: str, cls: str = "") -> str:
    rel = th.get(r.uuid)
    t = html.escape(title, quote=True)
    if rel:
        body = f'<img loading="lazy" src="{rel}" alt="">'
    else:
        body = '<div class="ph">no local preview<br>(iCloud only)</div>'
    return f'<figure class="{cls}" title="{t}">{body}<figcaption>{html.escape(caption)}</figcaption></figure>'


def write_report(out_dir: Path, result: ScanResult, cfg: Config, info: dict, samples: int = 24,
                 run_args: str = "") -> dict:
    run_dir = Path(out_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    plan = build_plan(result, cfg, info)
    (run_dir / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
    write_csvs(run_dir, result, cfg, plan)

    recs = result.records
    by_uuid = {r.uuid: r for r in recs}
    dec = result.decisions
    th = _Thumbs(run_dir, by_uuid)
    n = len(recs)
    n_video = sum(r.is_movie for r in recs)
    n_nothumb = sum(1 for r in recs if not r.thumb_path)
    n_unsorted = sum(d.unsorted for d in dec.values())
    n_multi = sum(len(d.categories) > 1 for d in dec.values())
    max_count = max([len(v) for v in plan["albums"].values()] + [1])
    e = html.escape

    def tip(r, cat=None):
        d = dec[r.uuid]
        bits = [r.filename, (r.date or "")[:10]]
        if cat:
            bits.append(f"{cat} {d.scores.get(cat, 0):.2f} — {d.reasons.get(cat, '')}")
        else:
            best = sorted(d.scores.items(), key=lambda kv: -kv[1])[:3]
            bits.append("closest: " + ", ".join(f"{k} {v:.2f}" for k, v in best if v > 0))
        return " · ".join(b for b in bits if b)

    parts = [f"<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
             f"<title>photosort dry run</title><style>{CSS}</style></head><body><main>",
             "<h1>Photo library sort — dry run</h1>",
             f"<p class='sub'>{e(plan['created'].replace('T', ' '))} · photosort {__version__}{' · ' + e(run_args) if run_args else ''}</p>",
             "<div class='banner'><b>Nothing has been changed in Photos.</b> This is a preview of the albums that "
             f"would be filled inside the folder “{e(cfg.folder)}”. To do it, run <code>./sortphotos apply</code>. "
             "Applying only adds photos to albums — it never deletes, moves or edits a photo.</div>",
             "<div class='tiles'>"]
    for val, lab in [(n, "items scanned"), (n - n_video, "photos"), (n_video, "videos"),
                     (n - n_unsorted, "sorted into an album"), (n_multi, "in 2+ albums"),
                     (n_unsorted, "unsorted"), (len(result.groups), "duplicate/similar groups"),
                     (n_nothumb, "no local preview")]:
        parts.append(f"<div class='tile'><b>{val:,}</b><span>{e(lab)}</span></div>")
    parts.append("</div>")
    notes = []
    notes.append("CLIP image model: <b>on</b>" if result.clip_used else
                 "CLIP image model: <b class='warn'>off</b> — sorted from Photos' own labels and flags only")
    if cfg.by_rule("travel"):
        notes.append("home area found from your geotagged photos" if result.home_found else
                     "<span class='warn'>Travel skipped: not enough geotagged photos to find home</span>")
    if n_nothumb:
        notes.append(f"{n_nothumb:,} items have no preview on this Mac (iCloud only): sorted from metadata, "
                     "not checked for blur/duplicates; nothing was downloaded")
    parts.append("<p class='meta'>" + " · ".join(notes) + "</p>")

    parts.append("<table><tr><th>Album</th><th></th><th style='text-align:right'>Items</th><th style='text-align:right'>Share</th></tr>")
    for a, u in plan["albums"].items():
        w = 100 * len(u) / max_count
        pct = 100 * len(u) / n if n else 0
        parts.append(f"<tr><td><a href='#{slug(a)}'>{e(a)}</a></td><td class='bar'><div class='b' style='width:{w:.1f}%'></div></td>"
                     f"<td class='n'>{len(u):,}</td><td class='n'>{pct:.1f}%</td></tr>")
    parts.append("</table>")

    sheets = {}
    for c in cfg.active:
        members = [r for r in recs if c.name in dec[r.uuid].categories]
        parts.append(f"<section id='{slug(c.album)}'><h2>{e(c.album)}</h2>")
        desc = f"{len(members):,} items · threshold {c.threshold:.2f}"
        if c.album != c.name:
            desc += f" · category “{e(c.name)}”"
        parts.append(f"<p class='meta'>{desc}</p>")
        if not members:
            parts.append("<p class='meta'>Nothing matched.</p></section>")
            continue
        if c.rule == "duplicates":
            shown = []
            for gi, g in enumerate(result.groups[:15], 1):
                parts.append("<div class='grp'>")
                for k, u in enumerate(g[:8]):
                    r = by_uuid.get(u)
                    if r is None:
                        continue
                    parts.append(_fig(th, r, "suggested keeper" if k == 0 else r.filename, tip(r, c.name),
                                      "keep" if k == 0 else ""))
                    shown.append(th.get(u))
                parts.append("</div>")
            if len(result.groups) > 15:
                parts.append(f"<p class='meta'>… and {len(result.groups) - 15:,} more groups (see photos.csv, column dup_group).</p>")
            sheets[c.album] = _sheet(run_dir, c.album, shown)
            parts.append("</section>")
            continue
        ranked = sorted(members, key=lambda r: -dec[r.uuid].scores.get(c.name, 0))
        top = ranked[:samples]
        rest = ranked[samples:]
        border = rest[-(samples // 2):] if rest else []
        parts.append("<h3>Most confident</h3><div class='grid'>")
        parts += [_fig(th, r, f"{dec[r.uuid].scores.get(c.name, 0):.2f} · {r.filename}", tip(r, c.name)) for r in top]
        parts.append("</div>")
        if border:
            parts.append("<h3>Borderline (just over the threshold — check these)</h3><div class='grid'>")
            parts += [_fig(th, r, f"{dec[r.uuid].scores.get(c.name, 0):.2f} · {r.filename}", tip(r, c.name)) for r in border]
            parts.append("</div>")
        sheets[c.album] = _sheet(run_dir, c.album, [th.get(r.uuid) for r in top + border])
        parts.append("</section>")

    uns = [r for r in recs if dec[r.uuid].unsorted]
    if uns:
        random.Random(7).shuffle(uns)
        show = uns[:samples * 2]
        parts.append(f"<section id='{slug(cfg.unsorted_album or 'unsorted')}'><h2>{e(cfg.unsorted_album or 'Unsorted')}</h2>"
                     f"<p class='meta'>{len(uns):,} items did not reach any threshold. Random sample; hover for the closest categories.</p><div class='grid'>")
        parts += [_fig(th, r, r.filename, tip(r)) for r in show]
        parts.append("</div></section>")
        sheets["Unsorted"] = _sheet(run_dir, "Unsorted", [th.get(r.uuid) for r in show])

    parts.append("<section><h2>Next steps</h2><p>Happy with it? <code>./sortphotos apply</code> fills the albums. "
                 "Not quite? Edit <code>categories.yaml</code> (labels, prompts, thresholds) and run "
                 "<code>./sortphotos scan</code> again — it re-uses the cache, so it only takes a moment. "
                 "Full per-photo detail is in <code>photos.csv</code> next to this report.</p></section>")
    parts.append("</main></body></html>")
    (run_dir / "report.html").write_text("\n".join(parts), encoding="utf-8")
    return {"plan": plan, "run_dir": str(run_dir), "report": str(run_dir / "report.html"),
            "unsorted": n_unsorted, "sheets": [s for s in sheets.values() if s]}
