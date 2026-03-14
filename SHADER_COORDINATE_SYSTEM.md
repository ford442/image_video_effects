# Shader Coordinate System

A persistent numbering scheme for 593+ shaders that enables multiple menu views while keeping each shader at a fixed "address."

---

## Core Concept

Every shader has a **coordinate (0-1000)** that never changes. 

- Adding new shaders extends the range (1001, 1002...) or fills gaps
- Shaders keep their coordinate forever
- Multiple menus provide different "lenses" on the same coordinate space

---

## Coordinate Zones

| Range | Zone | Characteristics | Examples |
|-------|------|-----------------|----------|
| 0-100 | 🌊 Ambient | Slow, smooth, generative | cosmic-jellyfish (70), bioluminescent-abyss (92) |
| 100-250 | 🌿 Organic | Living, natural motion | bubble-chamber (141), alien-flora (142) |
| 250-400 | 👆 Interactive | Mouse-driven, responsive | neon-ripple, bio-touch |
| 400-550 | 🎨 Artistic | Filters, paint, stylization | charcoal-rub, oil-paint |
| 550-700 | ✨ Visual FX | Glitch, chromatic, noise | chromatic-focus, datamosh |
| 700-850 | 📺 Retro/Digital | CRT, VHS, pixel, dither | ascii-glyph, crt-tv |
| 850-1000 | 🌀 Extreme | Heavy distortion, warping | black-hole, vortex-distortion |

---

## Files Generated

| File | Purpose |
|------|---------|
| `shader_coordinates.json` | Complete mapping of all 593 shaders with coordinates, features, tags |
| `assign_coordinates.py` | Script to (re)generate coordinates based on category + keywords |
| `ShaderCoordinateMenu.tsx` | React component with 4 menu lenses |
| `ShaderCoordinateMenu.css` | Dark theme styling |
| `ShaderCoordinateMenu.example.tsx` | Integration examples |

---

## Menu Lenses

### 1. By Visual Tempo (Spectrum View)
Shows the full 0-1000 spectrum as colored zones. Shaders appear in their zone.

```
[Ambient 0-100] [Organic 100-250] [Interactive 250-400] ...
```

### 2. By Input Type (Grouped View)
Filters shaders by how they're controlled:
- Standalone (Generative)
- Mouse Driven
- Depth Aware
- Audio Reactive
- Time Based

### 3. By Category (Grouped View)
Traditional categories but sorted by coordinate within each:
- Liquid & Fluid
- Lighting & Glow
- Distortion & Warp
- etc.

### 4. By Number (List View)
Direct numeric access 0-1000 with searchable/filterable list.

---

## Key Features

### Coordinate Persistence
Shader #917 is always at ~917. New shaders at 920 don't push it around.

### "More Like This"
Hover any shader to see neighbors (±50 coordinate units).

### Cross-Menu Consistency
Switch between menus — the same shader maintains its context.

### URL Navigation
```
#shader=coord:917  → navigates to black-hole
```

---

## Integration

### 1. Import the component
```tsx
import { ShaderCoordinateMenu } from './components/ShaderCoordinateMenu';
import shaderCoordinates from './shader_coordinates.json';
```

### 2. Prepare data
```tsx
const shaders = Object.entries(shaderCoordinates).map(([id, data]) => ({
  id,
  name: data.name,
  coordinate: data.coordinate,
  category: data.category,
  features: data.features,
  tags: data.tags,
}));
```

### 3. Use in your app
```tsx
<ShaderCoordinateMenu
  shaders={shaders}
  selectedId={currentShaderId}
  onSelect={handleShaderSelect}
  recentIds={recentIds}
  favoriteIds={favoriteIds}
/>
```

---

## Regenerating Coordinates

If you add/modify shaders, regenerate the coordinates:

```bash
python3 assign_coordinates.py
```

This will:
1. Read all JSON files from `shader_definitions/`
2. Assign coordinates based on category + keywords
3. Write to `shader_coordinates.json`
4. Show sample assignments

**Note:** Existing coordinates are deterministic (same ID = same coordinate), so regenerating won't reshuffle your library.

---

## Adding New Shaders

### Option A: Automatic (Recommended)
Add your shader JSON to `shader_definitions/{category}/`, then run:
```bash
python3 assign_coordinates.py
```

The script assigns a coordinate based on category and keywords.

### Option B: Manual Placement
Add to `shader_coordinates.json` manually:
```json
{
  "my-new-shader": {
    "coordinate": 423,
    "name": "My New Shader",
    "category": "artistic",
    "features": ["mouse-driven"],
    "tags": ["paint", "stylized"]
  }
}
```

---

## Coordinate Assignment Logic

```python
base = CATEGORY_BASE[category]  # e.g., artistic = 450

# Keyword adjustments
if "fast" in keywords:       base += 50
if "glitch" in keywords:     base += 40
if "slow" in keywords:       base -= 30
if "ambient" in keywords:    base -= 40
if "black-hole" in keywords: base += 80

# Hash-based spread (deterministic)
base += hash(shader_id) % 20 - 10

# Clamp
coordinate = clamp(base, 0, 1000)
```

---

## Stats

- **593 shaders** assigned coordinates
- **11 categories** mapped to zones
- **4 menu lenses** provided
- **0-1000 range** with room for 2x growth

---

## Future Extensions

### Audio-Reactive Zone
Reserve 1100-1200 for audio-reactive shaders.

### Touch/Mobile Zone
Reserve 1300-1400 for touch-optimized shaders.

### Depth-Aware Sub-Zones
Within existing zones:
- 5000-5999: Depth-aware variants

### AI-Generated Coordinates
Use LLM to analyze shader code and assign coordinates based on visual complexity.
