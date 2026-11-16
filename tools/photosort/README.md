# photosort

Sorts an Apple Photos library into albums on your Mac. Everything runs locally.

- **Dry run by default.** `scan` only reads. It writes an HTML report (counts + contact-sheet
  samples) and a CSV, and changes nothing in Photos.
- **Apply is add-only.** `apply` creates albums inside one top-level folder, **“Sorted by Claude”**,
  and adds photos to them. It never deletes, moves, renames or edits a photo, and never touches
  your existing albums. A test (`test_package_never_calls_destructive_photos_apis`) fails if the
  code ever gains a destructive call.
- **iCloud-friendly.** Works with “Optimize Mac Storage”. It analyses the small previews Photos
  already keeps on the Mac and never downloads originals. Items with no local preview are sorted
  from Photos metadata only.
- **A photo can be in several albums** (a gym video is in *Gym & Fitness* and *Videos*).
  Anything below every threshold goes to *Unsorted*.

Albums: Gym & Fitness, Food & Drinks, Screenshots, Receipts & Documents, Cars & Rides,
Nature & Outdoors, Trees, Sunsets & Sky, Pets & Animals, Friends & Family, Selfies, Travel,
Memes & Saved Images, Work, Shopping, Videos, Duplicates & Similar, Review to delete
(blurry / accidental shots — an album to look through, nothing is deleted), Unsorted.
All of it is configurable in [`categories.yaml`](categories.yaml).

## Run it (step by step)

Run these **on the Mac itself**, in Terminal (Applications > Utilities > Terminal), from this folder.
If an assistant runs them for you, its shell must be a real macOS shell: `uname` must print
`Darwin`. A sandbox that prints `Linux` cannot see Photos — use Terminal instead.

```bash
cd tools/photosort

# 1. Install (about 5-10 min; ~1.5 GB with the CLIP model, ~200 MB with --no-clip)
./install.sh
#    "No Python 3.10+ found"?  ->  ./install.sh --install-uv

# 2. Give permission (once) — see "Permissions" below, then check:
./sortphotos doctor

# 3. Optional: how long will the first scan take on this Mac?
./sortphotos estimate

# 4. Dry run. Changes nothing. Opens the report in your browser when done.
./sortphotos scan
#    Quick trial first if you like:  ./sortphotos scan --limit 500

# 5. Read the report. Not happy? Edit categories.yaml and run step 4 again (fast: cached).

# 6. Fill the albums. Asks for confirmation; add --yes to skip the question.
./sortphotos apply
```

Then open Photos > sidebar > Albums > **Sorted by Claude**.

Start small if you want: `./sortphotos apply --only "Screenshots,Videos"`, look in Photos, then
run `./sortphotos apply` for the rest. `apply` always uses the plan from the most recent `scan`,
i.e. exactly what the report showed.

## Permissions (macOS will block it without these)

1. **Full Disk Access** — needed to *read* the Photos library.
   System Settings > Privacy & Security > Full Disk Access > turn on the app that runs the
   commands (**Terminal**, or **Claude** if the Claude app runs them). Quit and reopen that app.
   You have to do this yourself; macOS asks for your password or Touch ID.
2. **Automation > Photos** — needed only for `apply`. The first time, macOS shows
   “Terminal wants access to control Photos”: click **Allow**. If you missed it:
   System Settings > Privacy & Security > Automation > Terminal > turn on **Photos**.
   `./sortphotos doctor --automation` triggers and checks this before you apply.

`./sortphotos doctor` tells you which of these is missing.

## Commands

| Command | What it does |
| --- | --- |
| `./sortphotos doctor [--automation]` | checks macOS, Python, library access, CLIP, Photos automation |
| `./sortphotos estimate` | times a sample on this Mac and estimates the first scan |
| `./sortphotos scan` | **dry run**: analyse, classify, write report + CSV + plan |
| `./sortphotos apply` | add photos to albums from the latest plan (add-only) |
| `./sortphotos demo` | dry run on a generated fake library — no Photos access at all |
| `./sortphotos download-model` | (re)download / verify the CLIP model |

Useful options:

- `scan --since 2026-11-01` / `--since 7d` / `--since last` — only sort items **added** since
  then (`last` = since your last full scan). Duplicates are still checked against the whole
  library. Follow with `apply` as usual.
- `scan --limit 500` — only the 500 most recent items (trial run).
- `scan --no-clip` — skip the image model, use Photos’ own labels only.
- `scan --include-hidden` — also sort the Hidden album (left out by default, as are items in
  shared albums and Recently Deleted).
- `scan --library "/path/to/Other.photoslibrary"` — a library other than the system one.
- `apply --only "A,B"` / `--skip "Unsorted"` / `--dry-run` / `--yes`.
- `--out DIR` (any command) — where reports and the cache go (default `./output`).

## How it decides

Signals are combined per category into a 0–1 score; a photo joins every album whose score
reaches that category’s `threshold` (default 0.5).

| Signal | Source |
| --- | --- |
| flags | Photos: screenshot, selfie / front camera, video, live, portrait, panorama, … |
| labels | Apple’s own ML labels from Photos search (“food”, “dog”, “tree”, “receipt”, …) |
| search info | venue types and activities Photos inferred (“fitness center”, “restaurant”) |
| captions | your titles, captions and keywords (`--ai-captions` adds Photos’ AI captions) |
| people | named people and face counts → Friends & Family |
| place | GPS distance from your *home cluster* (densest area of your geotagged photos) → Travel |
| saved images | no camera info / saved by another app / GIF → Memes & Saved Images |
| CLIP (optional) | local zero-shot model scored against the `prompts` of each category |
| perceptual hash | pHash + dHash of the preview → Duplicates & Similar, with a suggested keeper |
| sharpness / brightness | blurry, black or blank previews → Review to delete |

The report shows, per album, the most confident matches and the borderline ones (just over the
threshold) — the borderline row is what to look at when tuning. Hover a thumbnail to see why it
matched. `photos.csv` has one row per photo with every score and the reason.

### Tuning

Edit `categories.yaml`: raise a `threshold` to make an album stricter, add `labels`,
`keywords` or CLIP `prompts`, rename an `album`, or set `enabled: false`. Re-running `scan`
re-uses cached hashes and embeddings, so it only re-scores.

Personal settings (a fixed home location, your own keywords) go in `categories.local.yaml`
next to it. That file is gitignored and is merged over the defaults.

## iCloud-only photos

With “Optimize Mac Storage”, most originals are in iCloud. photosort uses the JPEG previews
Photos keeps locally and **never triggers a download**. If an item has no local preview at all,
it is still sorted from flags, labels, people and place, but is not checked for blur or
duplicates and gets no CLIP score. The report says how many items that was.

## Speed

| Step | Speed |
| --- | --- |
| Reading metadata | about 1–2 min for 20k+ items |
| Hashing + blur | ~10 ms per photo (measured on a slow 2-core Linux VM) |
| CLIP ViT-B/32 on CPU | ~45 ms per photo (same VM) → ~15 min per 20k |
| CLIP on Apple silicon GPU | not measured here; expect several times faster than CPU |
| Apply | AppleScript-bound; rough guess 1–3 min per 1,000 album adds |

So a first scan of a 20k library should land somewhere between 5 and 25 minutes. Use
`./sortphotos estimate` for a number measured on your Mac. Everything is cached in
`output/cache.sqlite`: stop with Ctrl-C and re-run to resume, and later runs only analyse new
photos. `apply` is resumable the same way.

## Outputs and privacy

Everything is written under `output/` (reports in `output/runs/<time>/`):
`report.html`, `thumbs/`, `sheets/` (one contact-sheet JPEG per album), `photos.csv`,
`albums.csv`, `plan.json`, and `cache.sqlite`.

These contain personal data (file names, thumbnails, place names). `output/` is in
`.gitignore`, and the folder also writes its own `.gitignore` containing `*`, so it cannot be
committed even if you point `--out` somewhere else inside a repo. The CSV has no coordinates,
only kilometres from home. Nothing is uploaded anywhere; the only network use is the one-time
download of Python packages and the CLIP model.

## Re-running and undoing

- Re-running `apply` is safe: adds are remembered, and Photos ignores a photo that is already
  in an album.
- If you take a photo **out** of one of these albums, later runs will not put it back
  (`apply --readd` overrides that).
- To undo everything, delete the “Sorted by Claude” folder in Photos. Deleting albums does not
  delete photos.

## What has and has not been tested

Tested on Linux (`pip install -r requirements-dev.txt && python -m pytest tests`, 33 tests):
config validation, every category rule on synthetic metadata, hashing, blur, duplicate
grouping (20k synthetic hashes), home detection, cache resume, `--since`, report generation
with fake images, add-only/idempotent apply against a fake Photos writer, and the installer.
The reader was also run against a real sample Photos library (macOS 13 format) on Linux.

**Not tested — Mac only:**

- `apply` against the real Photos app (PhotoScript / AppleScript). It is written against
  PhotoScript 0.6 and only calls folder lookup/create, album lookup/create and `albumAdd`.
  Try `apply --only "Screenshots"` first.
- The Full Disk Access / Automation prompts, and `open`-ing the report.
- CLIP with the real weights and on the Apple GPU (the code path was exercised with an
  untrained model; the weights could not be downloaded in the build environment). Category
  accuracy with CLIP is therefore unverified — judge it from the report’s borderline rows.
- Libraries where Photos keeps no JPEG previews for most items.

There is no MLX backend: `open_clip` already uses the Apple-silicon GPU through PyTorch MPS.

## Troubleshooting

- **“Could not read the Photos library”** → Full Disk Access (above), then reopen the app.
- **`apply` hangs or says Photos did not accept the request** → Automation permission (above);
  make sure Photos is open and not showing a dialog.
- **CLIP is “off” in the report** → `./sortphotos download-model` shows why. Scans still work
  without it.
- **Too many / too few in an album** → adjust that category’s `threshold` in `categories.yaml`.
- **Travel is empty** → fewer than 25 geotagged photos, or set `travel.home: [lat, lon]` in
  `categories.local.yaml`.
- **Some photos “could not be added”** → they were deleted after the scan; see
  `apply-failed.json` in the run folder.
