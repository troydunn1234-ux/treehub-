"""Progress bars: tqdm on a terminal, plain periodic lines when output is piped/logged."""

from __future__ import annotations

import sys
import time


def fmt_secs(s: float) -> str:
    s = int(max(0, s))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s // 3600}h{(s % 3600) // 60:02d}m"


class Progress:
    def __init__(self, total: int, desc: str, unit: str = "photo", quiet: bool = False):
        self.total, self.desc, self.unit, self.quiet = total, desc, unit, quiet
        self.n = 0
        self.t0 = time.time()
        self._last = 0.0
        self._bar = None
        if not quiet and sys.stderr.isatty():
            try:
                from tqdm import tqdm

                self._bar = tqdm(total=total, desc=desc, unit=unit, dynamic_ncols=True)
            except Exception:
                self._bar = None

    def update(self, k: int = 1):
        self.n += k
        if self._bar is not None:
            self._bar.update(k)
            return
        now = time.time()
        if not self.quiet and (now - self._last >= 5 or self.n >= self.total):
            self._last = now
            el = now - self.t0
            rate = self.n / el if el > 0 else 0
            eta = (self.total - self.n) / rate if rate > 0 else 0
            pct = 100 * self.n / self.total if self.total else 100
            print(f"[{self.desc}] {self.n}/{self.total} ({pct:.0f}%) {rate:.1f} {self.unit}/s ETA {fmt_secs(eta)}",
                  file=sys.stderr, flush=True)

    def close(self):
        if self._bar is not None:
            self._bar.close()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()
