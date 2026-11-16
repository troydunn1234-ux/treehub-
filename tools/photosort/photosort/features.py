"""Image features from a thumbnail: perceptual hashes, sharpness, brightness. numpy + Pillow only."""

from __future__ import annotations

import os
from functools import lru_cache

import numpy as np
from PIL import Image, ImageOps

from .model import Features

try:  # HEIC originals (only used when a photo has no JPEG preview but the original is local)
    import pillow_heif

    pillow_heif.register_heif_opener()
except Exception:  # pragma: no cover - optional
    pass

Image.MAX_IMAGE_PIXELS = None
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".tif", ".tiff", ".bmp", ".webp"}


def file_sig(path: str) -> str:
    try:
        st = os.stat(path)
        return f"{os.path.basename(path)}:{st.st_size}:{int(st.st_mtime)}"
    except OSError:
        return "missing"


def load_image(path: str, max_side: int = 512) -> Image.Image:
    """Open an image small and fast (JPEG draft mode), upright, RGB."""
    im = Image.open(path)
    try:
        im.draft("RGB", (max_side, max_side))
    except Exception:
        pass
    im = ImageOps.exif_transpose(im)
    if im.mode != "RGB":
        im = im.convert("RGB")
    im.thumbnail((max_side, max_side), Image.BILINEAR)
    return im


@lru_cache(maxsize=4)
def _dct_matrix(n: int) -> np.ndarray:
    k = np.arange(n)[:, None]
    x = np.arange(n)[None, :]
    m = np.cos(np.pi * (2 * x + 1) * k / (2 * n)) * np.sqrt(2.0 / n)
    m[0, :] = np.sqrt(1.0 / n)
    return m


def _bits_to_int(bits: np.ndarray) -> int:
    v = 0
    for b in bits.flatten():
        v = (v << 1) | int(bool(b))
    return v


def phash(im: Image.Image) -> int:
    g = np.asarray(im.convert("L").resize((32, 32), Image.LANCZOS), dtype=np.float64)
    d = _dct_matrix(32)
    low = (d @ g @ d.T)[:8, :8]
    med = np.median(low.flatten()[1:])
    return _bits_to_int(low > med)


def dhash(im: Image.Image) -> int:
    g = np.asarray(im.convert("L").resize((9, 8), Image.LANCZOS), dtype=np.int16)
    return _bits_to_int(g[:, 1:] > g[:, :-1])


def sharpness(im: Image.Image) -> tuple[float, float, float]:
    """Return (sharpness, mean brightness, contrast).

    sharpness = 99th percentile of |Laplacian| on a 256px grey copy. Using a high
    percentile (not the variance) means one crisp edge anywhere keeps the score up,
    so smooth-but-sharp scenes (sky, walls) are not mistaken for blur.
    """
    g = im.convert("L")
    g.thumbnail((256, 256), Image.BILINEAR)
    a = np.asarray(g, dtype=np.float32)
    if a.shape[0] < 3 or a.shape[1] < 3:
        return 0.0, float(a.mean()), float(a.std())
    lap = a[1:-1, :-2] + a[1:-1, 2:] + a[:-2, 1:-1] + a[2:, 1:-1] - 4 * a[1:-1, 1:-1]
    return float(np.percentile(np.abs(lap), 99)), float(a.mean()), float(a.std())


def compute_features(im: Image.Image) -> Features:
    s, m, sd = sharpness(im)
    return Features(phash=phash(im), dhash=dhash(im), sharp=s, mean=m, std=sd, status="ok")


def hamming(a: int, b: int) -> int:
    return (a ^ b).bit_count()
