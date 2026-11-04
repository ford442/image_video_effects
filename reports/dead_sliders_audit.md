# Dead Slider Audit

- Definitions scanned: 1338
- **New dead sliders: 1**
- Known (triaged baseline) dead sliders: 2
- Def errors (missing WGSL / parse): 0

## New dead sliders

- `gen-abyssal-geode-matrix` (generative): param `fractalDetail` "Fractal Detail" → zoom_params.w never read

