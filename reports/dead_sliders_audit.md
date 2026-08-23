# Dead Slider Audit

- Definitions scanned: 1032
- **New dead sliders: 9**
- Known (triaged baseline) dead sliders: 180
- Def errors (missing WGSL / parse): 1

## New dead sliders

- `gen-astro-orrery-blackbody` (advanced-hybrid): param `complexity` "Ring Complexity" → zoom_params.x never read
- `gen-astro-orrery-blackbody` (advanced-hybrid): param `speed` "Orbital Speed" → zoom_params.y never read
- `gen-astro-orrery-blackbody` (advanced-hybrid): param `glow` "Glow Intensity" → zoom_params.z never read
- `gen-astro-orrery-blackbody` (advanced-hybrid): param `audio` "Audio Reactivity" → zoom_params.w never read
- `gen-string-theory-structure` (advanced-hybrid): param `param1` "Param 1" → zoom_params.x never read
- `gen-string-theory-structure` (advanced-hybrid): param `param2` "Param 2" → zoom_params.y never read
- `gen-string-theory-structure` (advanced-hybrid): param `param3` "Param 3" → zoom_params.z never read
- `gen-string-theory-structure` (advanced-hybrid): param `param4` "Param 4" → zoom_params.w never read
- `glitch-pixel-sort` (visual-effects): param `param4` "Detail" → zoom_params.w never read

