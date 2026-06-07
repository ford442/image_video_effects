# Procedural Cyber Terminal (ASCII) Shader Plan

## Overview
This shader transforms the input video feed or image into a high-tech, procedural ASCII terminal display. Unlike traditional ASCII filters that rely on font textures, this shader generates character glyphs (e.g., `. : - = + * # @`) mathematically using Signed Distance Functions (SDFs) within the fragment shader. This allows for infinite resolution scaling and a unique "digital" aesthetic.

## Features
1. **Grid Quantization**: The image is divided into a dynamic grid of cells (e.g., 80x25 to 160x50), adjustable via zoom parameters.
2. **Procedural Glyphs**: A set of 8-10 distinct characters drawn procedurally based on pixel coordinates within each cell.
3. **Luminance Mapping**: The brightness of the underlying image determines which character is drawn (darker = empty/dot, brighter = dense characters like `#` or `@`).
4. **Interactive "Decoder"**:
   - **Mouse Interaction**: The mouse cursor acts as a "decoder lens".
   - **Effect**: Cells near the mouse cursor switch from standard ASCII to "Binary" (0/1) or "Hex" mode, and brighten significantly, simulating a hacking tool or data inspector.
5. **Aesthetic Styles**:
   - **Monochrome**: Classic Phosphor Green or Amber.
   - **Full Color**: The characters take the color of the underlying image.
   - **CRT Vignette**: Subtle scanlines and corner darkening for retro realism.

## Technical Implementation Details

### Grid Logic
- **Uniforms**: `u.zoom_params.x` controls grid density (font size).
- **Cell Coordinates**: `floor(uv * grid_size)` determines the cell ID.
- **Local Coordinates**: `fract(uv * grid_size)` gives the UV 0-1 within each character cell.

### Glyph Generation (SDFs)
Implement a function `get_character(id, uv)` that returns a float (coverage/alpha).
- **ID 0 (Empty)**: Returns 0.0.
- **ID 1 (.)**: `smoothstep(radius, radius-aa, length(uv - center))`.
- **ID 2 (:)**: Two dots.
- **ID 3 (-)**: Horizontal line SDF (box).

## Parameters
| Name | Default | Min | Max | Step |
|------|---------|-----|-----|------|
| Grid Density (zoom_params.x) | 1.0 | 0.1 | 5.0 | 0.1 |
| Glyph Sharpness (zoom_params.y) | 0.8 | 0.0 | 1.0 | 0.05 |
| Character Brightness (zoom_params.z) | 1.0 | 0.5 | 2.0 | 0.1 |
| Interactive Decoder Radius (zoom_params.w) | 0.5 | 0.0 | 1.0 | 0.05 |

## Integration Steps
1. Create shader file `public/shaders/gen-cyber-terminal.wgsl` with the proposed WGSL skeleton.
2. Create JSON definition `shader_definitions/generative/gen-cyber-terminal.json` mapping the UI parameters.
3. Run `node scripts/generate_shader_lists.js` to update the shader manifest.
4. Test with various input videos to ensure procedural glyph rendering works correctly.
