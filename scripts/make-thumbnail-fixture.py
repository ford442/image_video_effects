#!/usr/bin/env python3
"""Build public/fixtures/thumbnail-scene.png, the input image for thumbnail capture.

Image-sampling effects (distortion, edge, glitch, halftone, ...) need a picture with
structure: hard edges, smooth gradients, saturated hues, fine texture and a bright
highlight. External image hosts are blocked on the capture VM, so the scene is
procedural and reproducible (fixed seed). Re-run after editing; commit the PNG.

    python3 scripts/make-thumbnail-fixture.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
OUT = os.path.join(os.path.dirname(__file__), '..', 'public', 'fixtures', 'thumbnail-scene.png')


def value_noise(rng, size, cells):
    grid = rng.random((cells + 1, cells + 1))
    xs = np.linspace(0, cells, size, endpoint=False)
    i = xs.astype(int)
    f = xs - i
    f = f * f * (3 - 2 * f)
    a = grid[i][:, i]
    b = grid[i][:, i + 1]
    c = grid[i + 1][:, i]
    d = grid[i + 1][:, i + 1]
    fx = f[None, :]
    fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(rng, size, octaves=5):
    total = np.zeros((size, size))
    amp = 0.5
    for o in range(octaves):
        total += amp * value_noise(rng, size, 4 * 2 ** o)
        amp *= 0.5
    return total


def main():
    rng = np.random.default_rng(1337)
    y = np.linspace(0, 1, SIZE)[:, None]
    x = np.linspace(0, 1, SIZE)[None, :]
    img = np.zeros((SIZE, SIZE, 3))

    # Sky: dusk gradient with soft clouds.
    sky_top = np.array([0.10, 0.18, 0.45])
    sky_low = np.array([0.98, 0.62, 0.38])
    t = np.clip(y / 0.55, 0, 1)[..., None]
    img[:] = sky_top * (1 - t) + sky_low * t
    clouds = np.clip(fbm(rng, SIZE) * 1.6 - 0.75, 0, 1)[..., None] * (y < 0.5)[..., None]
    img = img * (1 - 0.6 * clouds) + 0.6 * clouds * np.array([1.0, 0.9, 0.85])

    # Sun with a halo.
    d = np.sqrt((x - 0.68) ** 2 + (y - 0.36) ** 2)
    img += np.clip(1 - d / 0.07, 0, 1)[..., None] * np.array([1.0, 0.95, 0.75])
    img += (np.exp(-d * 9) * 0.35)[..., None] * np.array([1.0, 0.7, 0.4])

    # Two mountain ridges from 1D fbm.
    ridge_noise = fbm(rng, SIZE)
    for base, amp, col in ((0.50, 0.16, (0.30, 0.22, 0.42)), (0.60, 0.10, (0.12, 0.20, 0.18))):
        h = base - amp * ridge_noise[SIZE // 3 + int(base * 100)]
        mask = (y > h[None, :]).astype(float)[..., None]
        shade = 0.75 + 0.25 * fbm(rng, SIZE, 4)[..., None]
        img = img * (1 - mask) + mask * np.array(col) * shade

    # Lake: mirrored sky with ripples.
    lake = (y > 0.72).astype(float)[..., None]
    ripple = np.sin(y * 260 + 6 * fbm(rng, SIZE, 3)) * 0.5 + 0.5
    mirror = img[np.clip((2 * 0.72 * SIZE - np.arange(SIZE)).astype(int), 0, SIZE - 1)]
    water = mirror * (0.55 + 0.25 * ripple[..., None]) + np.array([0.02, 0.06, 0.10])
    img = img * (1 - lake) + lake * water

    img = np.clip(img, 0, 1)
    pil = Image.fromarray((img * 255).astype(np.uint8), 'RGB')

    # Hard-edged foreground: colour checker, spheres, stripes, text-like bars.
    draw = ImageDraw.Draw(pil)
    hues = [(220, 40, 40), (240, 160, 30), (240, 230, 60), (60, 190, 80),
            (40, 120, 230), (140, 60, 200), (250, 250, 250), (20, 20, 20)]
    for i, col in enumerate(hues):
        cx, cy = 24 + (i % 4) * 34, 404 + (i // 4) * 34
        draw.rectangle([cx, cy, cx + 30, cy + 30], fill=col, outline=(0, 0, 0))
    for k in range(14):
        draw.line([(330 + k * 12, 400), (300 + k * 12, 500)], fill=(250, 240, 220) if k % 2 else (30, 30, 40), width=5)
    for (cx, cy, r, col) in ((210, 450, 36, (230, 70, 120)), (262, 470, 22, (70, 200, 230))):
        for s in range(r, 0, -1):
            f = 0.45 + 0.55 * (1 - s / r)
            draw.ellipse([cx - s - (r - s) * 0.4, cy - s - (r - s) * 0.4, cx + s - (r - s) * 0.4, cy + s - (r - s) * 0.4],
                         fill=tuple(min(255, int(c * f + 255 * (1 - s / r) ** 4 * 0.6)) for c in col))
    for row in range(3):
        for j in range(rng.integers(5, 9)):
            w = int(rng.integers(12, 40))
            x0 = 30 + j * 46
            draw.rectangle([x0, 30 + row * 14, x0 + w, 36 + row * 14], fill=(245, 245, 250))

    pil = pil.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    pil.save(OUT, optimize=True)
    print(f'wrote {os.path.relpath(OUT)} ({os.path.getsize(OUT)} bytes)')


if __name__ == '__main__':
    main()
