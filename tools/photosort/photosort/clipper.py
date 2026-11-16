"""Optional local CLIP model (open_clip) for zero-shot categories.

Runs entirely on this machine: Apple-silicon GPU (MPS) when available, else CUDA, else CPU.
Embeddings are cached, so prompts/thresholds can be changed without re-embedding.
"""

from __future__ import annotations

import sys

import numpy as np


class ClipUnavailable(RuntimeError):
    pass


def clip_installed() -> bool:
    try:
        import open_clip  # noqa: F401
        import torch  # noqa: F401

        return True
    except Exception:
        return False


class OpenClipBackend:
    name = "open_clip"

    def __init__(self, model: str, pretrained: str | None, device: str | None = None, quiet: bool = False):
        try:
            import open_clip
            import torch
        except Exception as e:
            raise ClipUnavailable(f"open_clip/torch not installed ({e})") from e
        self.torch = torch
        if device is None:
            if getattr(torch.backends, "mps", None) is not None and torch.backends.mps.is_available():
                device = "mps"
            elif torch.cuda.is_available():
                device = "cuda"
            else:
                device = "cpu"
        self.device = device
        if not quiet:
            print(f"Loading CLIP {model} ({pretrained}) on {device} ...", file=sys.stderr, flush=True)
        try:
            self.model, _, self.preprocess = open_clip.create_model_and_transforms(model, pretrained=pretrained)
            self.tokenizer = open_clip.get_tokenizer(model)
        except Exception as e:
            raise ClipUnavailable(f"could not load CLIP model {model}/{pretrained}: {e}") from e
        self.model.eval()
        try:
            self.model.to(device)
        except Exception:
            self.device = "cpu"
            self.model.to("cpu")

    def _norm(self, t) -> np.ndarray:
        t = t / t.norm(dim=-1, keepdim=True).clamp(min=1e-8)
        return t.float().cpu().numpy()

    def embed_images(self, images) -> np.ndarray:
        torch = self.torch
        batch = torch.stack([self.preprocess(im) for im in images]).to(self.device)
        with torch.no_grad():
            return self._norm(self.model.encode_image(batch))

    def embed_texts(self, texts: list[str]) -> np.ndarray:
        torch = self.torch
        with torch.no_grad():
            return self._norm(self.model.encode_text(self.tokenizer(texts).to(self.device)))


def make_backend(clip_cfg: dict, quiet: bool = False):
    backend = str(clip_cfg.get("backend", "auto")).lower()
    if backend in ("off", "none", "false"):
        return None
    try:
        return OpenClipBackend(clip_cfg.get("model", "ViT-B-32"), clip_cfg.get("pretrained"), quiet=quiet)
    except ClipUnavailable as e:
        if backend == "auto":
            if not quiet:
                print(f"CLIP not available ({e}); continuing with Photos metadata only.", file=sys.stderr)
            return None
        raise


def zero_shot(image_vecs: np.ndarray, class_text_vecs: list[np.ndarray], temperature: float = 100.0) -> np.ndarray:
    """Softmax over classes; a class's logit is its best-matching prompt.

    image_vecs: (N, D) unit vectors. class_text_vecs: one (P_i, D) array per class.
    Returns (N, C) probabilities.
    """
    if len(image_vecs) == 0:
        return np.zeros((0, len(class_text_vecs)), dtype=np.float32)
    logits = np.stack([(image_vecs @ t.T).max(axis=1) for t in class_text_vecs], axis=1) * temperature
    logits -= logits.max(axis=1, keepdims=True)
    e = np.exp(logits)
    return (e / e.sum(axis=1, keepdims=True)).astype(np.float32)
