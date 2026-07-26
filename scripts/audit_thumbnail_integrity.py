#!/usr/bin/env python3
"""
audit_thumbnail_integrity.py — flag committed thumbnail PNGs that are nearly black or magenta error frames.
"""
from __future__ import annotations

import json
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THUMB_DIR = ROOT / "public" / "thumbnails"
MANIFEST_PATH = THUMB_DIR / "manifest.json"
REPORT_PATH = ROOT / "reports" / "thumbnail_integrity_audit.json"

# Match scripts/lib/thumbnailFrameAnalysis.js thresholds
MIN_ACTIVE = 0.02
MIN_LUMINANCE = 0.01
MIN_MAGENTA_RATIO = 0.15


def read_png_rgba(path: Path) -> tuple[bytes, int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos = 8
    width = height = 0
    raw = b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        pos += 4
        chunk_type = data[pos:pos + 4]
        pos += 4
        chunk = data[pos:pos + length]
        pos += length + 4  # skip CRC
        if chunk_type == b"IHDR":
            width, height = struct.unpack(">II", chunk[:8])
        elif chunk_type == b"IDAT":
            raw += chunk
        elif chunk_type == b"IEND":
            break
    if not raw:
        raise ValueError("no IDAT")
    inflated = zlib.decompress(raw)
    # PNG filter byte per row — skip for simple audit (assume filter 0)
    rows = []
    stride = width * 4
    i = 0
    for _ in range(height):
        i += 1  # filter type
        rows.append(inflated[i:i + stride])
        i += stride
    flat = b"".join(rows)
    return flat, width, height


def analyze_rgba(data: bytes, width: int, height: int) -> dict:
    pixels = width * height
    lum_sum = 0.0
    active = 0
    magenta = 0
    r_sum = g_sum = b_sum = 0.0
    for i in range(0, len(data), 4):
        r = data[i] / 255.0
        g = data[i + 1] / 255.0
        b = data[i + 2] / 255.0
        r_sum += r
        g_sum += g
        b_sum += b
        lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        lum_sum += lum
        if lum > 0.05:
            active += 1
        if r > 0.8 and g < 0.2 and b > 0.8:
            magenta += 1
    return {
        "meanLuminance": lum_sum / pixels,
        "activePixelRatio": active / pixels,
        "magentaPixelRatio": magenta / pixels,
        "meanR": r_sum / pixels,
        "meanG": g_sum / pixels,
        "meanB": b_sum / pixels,
    }


def classify(stats: dict) -> str | None:
    black = stats["activePixelRatio"] < MIN_ACTIVE or stats["meanLuminance"] < MIN_LUMINANCE
    magenta = stats["magentaPixelRatio"] >= MIN_MAGENTA_RATIO
    if black and magenta:
        return "error_frame"
    if black:
        return "black_frame"
    if magenta:
        return "magenta_frame"
    return None


def main() -> int:
    manifest: dict = {}
    if MANIFEST_PATH.exists():
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    flagged: list[dict] = []
    scanned = 0

    for png in sorted(THUMB_DIR.glob("*.png")):
        scanned += 1
        try:
            rgba, w, h = read_png_rgba(png)
            stats = analyze_rgba(rgba, w, h)
            reason = classify(stats)
            if reason:
                flagged.append({
                    "id": png.stem,
                    "in_manifest": png.stem in manifest,
                    "reason": reason,
                    "stats": stats,
                })
        except Exception as exc:  # noqa: BLE001
            flagged.append({
                "id": png.stem,
                "in_manifest": png.stem in manifest,
                "reason": "read_failed",
                "detail": str(exc),
            })

    report = {
        "scanned": scanned,
        "flagged": len(flagged),
        "entries": flagged,
    }
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(f"Thumbnail integrity: scanned {scanned}, flagged {len(flagged)}")
    if flagged:
        for entry in flagged[:20]:
            print(f"  - {entry['id']}: {entry['reason']}")
        if len(flagged) > 20:
            print(f"  ... and {len(flagged) - 20} more")
        print(f"Report: {REPORT_PATH}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
