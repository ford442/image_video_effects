# New Shader Plan: Procedural Cyber Terminal (ASCII)

## Overview
This shader transforms the input video feed or image into a high-tech, procedural ASCII terminal display. Unlike traditional ASCII filters that rely on font textures, this shader will generate character glyphs (e.g., `. : - = + * # @`) mathematically using Signed Distance Functions (SDFs) within the fragment shader. This allows for infinite resolution scaling and a unique "digital" aesthetic.

## Features
1.  **Grid Quantization**: The image is divided into a dynamic grid of cells (e.g., 80x25 to 160x50), adjustable via zoom parameters.
2.  **Procedural Glyphs**: A set of 8-10 distinct characters drawn procedurally based on pixel coordinates within each cell.
3.  **Luminance Mapping**: The brightness of the underlying image determines which character is drawn (darker = empty/dot, brighter = dense characters like `#` or `@`).
4.  **Interactive "Decoder"**:
    -   **Mouse Interaction**: The mouse cursor acts as a "decoder lens".
    -   **Effect**: Cells near the mouse cursor switch from standard ASCII to "Binary" (0/1) or "Hex" mode, and brighten significantly, simulating a hacking tool or data inspector.
5.  **Aesthetic Styles**:
    -   **Monochrome**: Classic Phosphor Green or Amber.
    -   **Full Color**: The characters take the color of the underlying image.
    -   **CRT Vignette**: Subtle scanlines and corner darkening for retro realism.

## Technical Implementation Details

### 1. Grid Logic
-   **Uniforms**: `u.zoom_params.x` controls grid density (font size).
-   **Cell Coordinates**: `floor(uv * grid_size)` determines the cell ID.
-   **Local Coordinates**: `fract(uv * grid_size)` gives the UV 0-1 within each character cell.

### 2. Glyph Generation (SDFs)
We will implement a function `get_character(id, uv)` that returns a float (coverage/alpha).
-   **ID 0 (Empty)**: Returns 0.0.
-   **ID 1 (.)**: `smoothstep(radius, radius-aa, length(uv - center))`.
-   **ID 2 (:)**: Two dots.
-   **ID 3 (-)**: Horizontal line SDF (box).
-   **ID 4 (+)**: Cross SDF (union of two boxes).
-   **ID 5 (*)**: Star SDF (rotated crosses).
-   **ID 6 (=)**: Double line.
-   **ID 7 (#)**: Hash/Grid SDF.
-   **ID 8 (@)**: Circle + spiral/inner details.

### 3. Sampling & Mapping
-   Sample the `readTexture` at the center of the current cell.
-   Compute luminance: `dot(color.rgb, vec3(0.299, 0.587, 0.114))`.
-   Map luminance (0.0 - 1.0) to a character ID range (e.g., 0 to 8).
-   Apply a "quantization" step to make the changes snappy (floor/step functions).

### 4. Interactive Layer
-   Calculate distance from current cell center to `u.zoom_config.yz` (mouse position).
-   If `distance < radius`, modify the mapping logic:
    -   Force character set to "Binary" (0 or 1 based on luminance threshold).
    -   Invert colors or boost brightness.
    -   Add a "glitch" offset to the cell sampling.

### 5. Post-Processing
-   Multiply the final character color by a scanline pattern: `sin(uv.y * resolution.y * 2.0)`.
-   Apply a vignette mask based on distance from screen center.

## File Structure
-   **Filename**: `public/shaders/cyber-terminal-ascii.wgsl`
-   **Category**: "digital" (in shader list JSON).

## Why This Shader?
-   **Uniqueness**: Fills a gap in the "Cyber/Digital" category for true text-mode effects.
-   **Technical Merit**: Demonstrates advanced procedural SDF drawing techniques.
-   **Interactivity**: Provides a fun, meaningful interaction (decoding/inspecting) rather than just distortion.
