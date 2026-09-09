# Workgroup size audit

Generated: 2026-09-08T08:48:29.763778+00:00

Prefer explicit @workgroup_size(x, y, 1) with x*y*z <= 256. 8×8=64 aligns with warp/wavefront width; 16×16=256 is the portable upper bound.

- Files scanned: 1410
- Convention warnings (2-arg / non-3-arg): 0
- Dispatch parse fallback risk (8×8 default): 0
- Hard limit errors: **0**

## Convention warnings (first 50)

_None._

## Dispatch fallback sites (first 50)

_None._

## Limit violations

_None._
