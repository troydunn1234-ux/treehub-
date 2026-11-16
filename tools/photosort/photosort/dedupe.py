"""Duplicate / similar grouping from perceptual hashes.

Two passes, joined with union-find:
  1. library-wide "duplicates": pHash within max_distance (<= 7). Candidates come from
     8 one-byte bands — any two hashes within 7 bits must share at least one band exactly.
  2. "similar" shots: photos taken within a short time window, with a looser distance.
Both passes also require the independent dHash to roughly agree, which removes most
false matches. Flat frames (blank / black) are skipped: their hashes are meaningless.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime

import numpy as np


@dataclass
class DupItem:
    uuid: str
    phash: int
    dhash: int
    ts: float | None = None       # epoch seconds taken
    pixels: int = 0
    filesize: int = 0
    favorite: bool = False
    edited: bool = False
    std: float = 99.0


class _UF:
    def __init__(self, n: int):
        self.p = list(range(n))

    def find(self, x: int) -> int:
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x

    def union(self, a: int, b: int):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.p[max(ra, rb)] = min(ra, rb)


def _popcount(a: np.ndarray) -> np.ndarray:
    if hasattr(np, "bitwise_count"):
        return np.bitwise_count(a)
    b = a.view(np.uint8).reshape(a.shape + (8,))
    return _LUT[b].sum(axis=-1)


_LUT = np.array([bin(i).count("1") for i in range(256)], dtype=np.uint8)


def parse_ts(iso: str | None) -> float | None:
    if not iso:
        return None
    try:
        return datetime.fromisoformat(iso).timestamp()
    except ValueError:
        return None


def find_groups(items: list[DupItem], max_distance: int = 6, similar_distance: int = 12,
                window_seconds: float = 120, flat_std: float = 5.0) -> list[list[int]]:
    """Return groups (lists of indexes into items), each with 2+ members."""
    idx = [i for i, it in enumerate(items) if it.phash is not None and it.dhash is not None and it.std > flat_std]
    n = len(idx)
    if n < 2:
        return []
    ph = np.array([items[i].phash for i in idx], dtype=np.uint64)
    dh = np.array([items[i].dhash for i in idx], dtype=np.uint64)
    uf = _UF(n)
    d_slack = 6  # dHash may differ a little more than pHash

    # pass 1: banded exact-ish duplicates across the whole library
    for band in range(8):
        keys = ((ph >> np.uint64(8 * band)) & np.uint64(0xFF)).astype(np.int64)
        order = np.argsort(keys, kind="stable")
        bounds = np.flatnonzero(np.diff(keys[order])) + 1
        for bucket in np.split(order, bounds):
            m = len(bucket)
            if m < 2:
                continue
            bp, bd = ph[bucket], dh[bucket]
            for s in range(0, m, 2048):
                e = min(m, s + 2048)
                dp = _popcount(bp[s:e, None] ^ bp[None, :])
                dd = _popcount(bd[s:e, None] ^ bd[None, :])
                rr, cc = np.nonzero((dp <= max_distance) & (dd <= max_distance + d_slack))
                for r, c in zip(rr.tolist(), cc.tolist()):
                    if r + s < c:
                        uf.union(int(bucket[r + s]), int(bucket[c]))

    # pass 2: looser match for shots taken close together in time
    timed = sorted((items[idx[k]].ts, k) for k in range(n) if items[idx[k]].ts is not None)
    for a in range(len(timed)):
        ta, ka = timed[a]
        for b in range(a + 1, min(a + 40, len(timed))):
            tb, kb = timed[b]
            if tb - ta > window_seconds:
                break
            if (int(ph[ka]) ^ int(ph[kb])).bit_count() <= similar_distance and \
               (int(dh[ka]) ^ int(dh[kb])).bit_count() <= similar_distance + d_slack:
                uf.union(ka, kb)

    groups = defaultdict(list)
    for k in range(n):
        groups[uf.find(k)].append(idx[k])
    out = [sorted(g) for g in groups.values() if len(g) > 1]
    out.sort(key=lambda g: (-len(g), g[0]))
    return out


def pick_keeper(items: list[DupItem], group: list[int]) -> int:
    """Suggest which copy to keep: favorite > edited > most pixels > biggest file > earliest."""
    return max(group, key=lambda i: (items[i].favorite, items[i].edited, items[i].pixels,
                                     items[i].filesize, -(items[i].ts or 0), -i))
