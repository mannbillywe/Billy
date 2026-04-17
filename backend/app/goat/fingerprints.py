"""Fingerprint helpers for deterministic idempotency.

- data_fingerprint identifies the *input snapshot* so repeated computes over
  the same data upsert into the same goat_mode_snapshots row.
- rec_fingerprint keeps a single open row per (user, kind, key) so repeated
  runs don't flood the user with duplicate open recommendations.
"""
from __future__ import annotations

import hashlib
from typing import Any


def _sha1(*parts: Any, length: int = 40) -> str:
    payload = "|".join("" if p is None else str(p) for p in parts)
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()[:length]


def data_fingerprint(
    *,
    user_id: str,
    scope: str,
    range_start: str | None,
    range_end: str | None,
    counts: dict[str, int],
    stamps: dict[str, str | None],
) -> str:
    """Deterministic over (user, scope, window, dataset shape + freshness)."""
    parts: list[Any] = [user_id, scope, range_start, range_end]
    for k in sorted(counts):
        parts.append(f"{k}:{counts[k]}")
    for k in sorted(stamps):
        parts.append(f"{k}@{stamps[k] or '0'}")
    return _sha1(*parts, length=40)


def rec_fingerprint(kind: str, *keys: Any) -> str:
    """Stable across runs; identifies "the same recommendation about the same thing"."""
    return _sha1(kind, *[k if k is not None else "_" for k in keys], length=32)
