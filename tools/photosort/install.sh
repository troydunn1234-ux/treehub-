#!/usr/bin/env bash
# photosort installer: virtualenv + dependencies + (optional) CLIP model download.
#   ./install.sh              full install (with the CLIP image model, ~1.5 GB download in total)
#   ./install.sh --no-clip    smaller/faster: sort from Photos' own labels only
#   ./install.sh --install-uv if no Python 3.10+ is found, fetch one with uv (astral.sh) — no admin needed
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

WITH_CLIP=1; INSTALL_UV=0
for a in "$@"; do
  case "$a" in
    --no-clip) WITH_CLIP=0 ;;
    --install-uv) INSTALL_UV=1 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say() { printf '\n==> %s\n' "$*"; }
OS="$(uname -s)"; ARCH="$(uname -m)"
[ "$OS" = "Darwin" ] || echo "Note: this is $OS, not macOS. You can run the demo and tests here, but not read or change Photos."

py_ok() { "$1" -c 'import sys; raise SystemExit(0 if (3,10) <= sys.version_info[:2] <= (3,14) else 1)' >/dev/null 2>&1; }
ORDER="python3.12 python3.13 python3.11 python3.10 python3.14 python3"
# Intel Macs: the last PyTorch build for them needs Python <= 3.12
[ "$OS" = "Darwin" ] && [ "$ARCH" = "x86_64" ] && ORDER="python3.12 python3.11 python3.10 python3"
PY=""
for c in $ORDER; do
  for d in "" /opt/homebrew/bin/ /usr/local/bin/ "$HOME/.local/bin/"; do
    if command -v "$d$c" >/dev/null 2>&1 && py_ok "$d$c"; then PY="$d$c"; break 2; fi
  done
done

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
USE_UV=0
if [ -z "$PY" ]; then
  if ! command -v uv >/dev/null 2>&1; then
    if [ "$INSTALL_UV" = 1 ]; then
      say "Installing uv (standalone Python manager) into ~/.local/bin"
      curl -LsSf https://astral.sh/uv/install.sh | sh
    else
      cat >&2 <<'MSG'

No Python 3.10+ found on this Mac (the built-in one is too old for osxphotos).
Easiest fix — let this script fetch a private Python with uv (no admin password needed):

    ./install.sh --install-uv

(or install Python 3.12 from https://www.python.org/downloads/ or `brew install python@3.12`,
 then run ./install.sh again)
MSG
      exit 1
    fi
  fi
  USE_UV=1
fi

if [ ! -x .venv/bin/python ] || ! py_ok .venv/bin/python; then
  say "Creating virtualenv in $(pwd)/.venv"
  if [ "$USE_UV" = 1 ]; then uv venv --python 3.12 --seed .venv; else "$PY" -m venv .venv; fi
fi
VPY=".venv/bin/python"
"$VPY" -m pip --version >/dev/null 2>&1 || "$VPY" -m ensurepip --upgrade
say "Python: $("$VPY" --version)  ($ARCH)"

say "Installing photosort dependencies (osxphotos, Pillow, ...) — a few minutes the first time"
"$VPY" -m pip install --quiet --upgrade pip
"$VPY" -m pip install --quiet -r requirements.txt

if [ "$WITH_CLIP" = 1 ]; then
  say "Installing the local CLIP image model runtime (PyTorch + open_clip)"
  if [ "$OS" = "Darwin" ] && [ "$ARCH" = "x86_64" ]; then
    CLIP_PKGS=("numpy<2" "torch==2.2.2" "open_clip_torch>=2.24")
  else
    CLIP_PKGS=(-r requirements-clip.txt)
  fi
  if "$VPY" -m pip install --quiet "${CLIP_PKGS[@]}"; then
    say "Downloading the CLIP model weights (~600 MB, once)"
    ./sortphotos download-model || echo "WARNING: model download failed — scans will fall back to Photos metadata only. Retry later with: ./sortphotos download-model"
  else
    echo "WARNING: could not install PyTorch/open_clip — photosort will still work from Photos metadata only."
  fi
fi

say "Checking setup"
./sortphotos doctor || true

cat <<'MSG'

Installed. Next:
  ./sortphotos demo        # optional: try it on a generated fake library (touches nothing)
  ./sortphotos estimate    # how long the first scan will take on this Mac
  ./sortphotos scan        # DRY RUN on your Photos library -> opens an HTML report; changes nothing
  ./sortphotos apply       # after you like the report: adds photos to albums in "Sorted by Claude"
MSG
