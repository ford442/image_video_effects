# Shader Coordinate System + Star Ratings Integration

This document describes the integration of the coordinate-based shader navigation system with the Storage Manager star ratings API.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           React Frontend                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  ShaderBrowserWithRatings.tsx                                       │   │
│  │  - 4 view modes: Zone | Rating | Popularity | Coordinate            │   │
│  │  - Integrated star ratings                                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                               │                                              │
│                               ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  ShaderRatingService.ts                                             │   │
│  │  - Fetches ratings from Storage Manager                             │   │
│  │  - Enriches coordinate data with stars/play counts                  │   │
│  │  - Handles rating submissions                                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Hugging Face Spaces                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Storage Manager (FastAPI)                                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│  │  │ /shaders    │  │ /shaders/id │  │ /shaders/id │                 │   │
│  │  │ ?sort_by=   │  │ /rate       │  │ (metadata)  │                 │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│  │                               │                                     │   │
│  │                               ▼                                     │   │
│  │                    Google Cloud Storage                             │   │
│  │                    - shaders/_shaders.json (index)                  │   │
│  │                    - shaders/{id}.wgsl (files)                      │   │
│  │                    - shaders/{id}/metadata.json                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Coordinate System (0-1000)

Every shader has a persistent coordinate based on its visual characteristics:

| Zone | Range | Description | Example Shaders |
|------|-------|-------------|-----------------|
| 🌊 Ambient | 0-100 | Slow, smooth, generative | Liquid v1 (#15), Cosmic Jellyfish (#70) |
| 🌿 Organic | 100-250 | Natural, living motion | Neuro-Cosmos (#102), Galaxy (#147) |
| 👆 Interactive | 250-400 | Mouse-driven, responsive | Laser Burn (#260), Neon Light (#294) |
| 🎨 Artistic | 400-550 | Filters, paint, stylization | Charcoal Rub (#445), Oil Slick (#417) |
| ✨ Visual FX | 550-700 | Glitch, chromatic, noise | Data Moshing (#563), Digital Lens (#557) |
| 📺 Retro | 700-850 | CRT, VHS, pixel sorting | ASCII Glyphs (#780), Datamosh (#743) |
| 🌀 Extreme | 850-1000 | Heavy distortion, warping | Black Hole (#996), Vortex Warp (#993) |

**Key Feature:** Coordinates never change. Adding new shaders fills gaps or extends beyond 1000.

---

## Menu Views

### 1. By Zone (Default)
Shaders grouped by their coordinate zone. Within each zone, sorted by star rating.

```
🌊 Ambient (0-100) [28 shaders]
  ⭐⭐⭐⭐⭐ Liquid v1 (#15)        4.8 ★ (42 ratings)
  ⭐⭐⭐⭐☆ Liquid Rainbow (#40)    4.2 ★ (18 ratings)
  ...

🌿 Organic (100-250) [72 shaders]
  ⭐⭐⭐⭐⭐ Bubble Chamber (#141)  4.9 ★ (67 ratings)
  ...
```

### 2. By Rating
Shaders grouped by star rating tiers:
- ⭐⭐⭐⭐⭐ Top Rated (4.5+)
- ⭐⭐⭐⭐ Highly Rated (4.0+)
- ⭐⭐⭐ Good (3.0+)
- 🆕 Unrated

### 3. By Popularity
Shaders grouped by play count:
- 🔥 Hot (1000+ plays)
- 💎 Popular (500+ plays)
- 📈 Rising (100+ plays)
- 🌱 New

### 4. By Number
Flat list sorted by coordinate (0-1000). Type any number to jump to that coordinate.

---

## Star Rating System

### API Endpoints (Storage Manager)

```bash
# Get all shaders with ratings
GET https://ford442-storage-manager.hf.space/api/shaders?sort_by=rating

# Get specific shader metadata
GET /api/shaders/{shader_id}

# Submit rating (1-5 stars)
POST /api/shaders/{shader_id}/rate
  FormData: stars=4.5

# List by category
GET /api/shaders?category=generative&min_stars=4.0
```

### Rating Storage

Each shader has metadata stored in GCS:

```json
{
  "id": "liquid-v1",
  "name": "Liquid (Ambient)",
  "stars": 4.8,
  "rating_count": 42,
  "play_count": 1250,
  "date": "2024-01-15",
  "author": "ford442",
  "tags": ["liquid", "ambient"],
  "description": "Smooth liquid distortion effect"
}
```

---

## File Structure

```
src/
├── components/
│   ├── ShaderBrowserWithRatings.tsx    # Main browser component
│   ├── ShaderBrowserWithRatings.css    # Styles
│   ├── ShaderStarRating.tsx            # Star rating component
│   └── ShaderStarRating.css            # Star styles
├── services/
│   └── ShaderRatingIntegration.ts      # API integration service
└── types/
    └── shader.ts                       # TypeScript definitions

shader_coordinates.json                 # 593 shader coordinates
assign_coordinates.py                   # Regeneration script
```

---

## Usage Example

```tsx
import { ShaderBrowserWithRatings } from './components/ShaderBrowserWithRatings';

function App() {
  const [currentShader, setCurrentShader] = useState<string | null>(null);

  return (
    <ShaderBrowserWithRatings
      currentShaderId={currentShader}
      onSelectShader={setCurrentShader}
    />
  );
}
```

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `0-9` | Type coordinate number to jump |
| `B` | Open shader browser |
| `Esc` | Close browser / cancel number entry |
| `R` | Roulette (random shader) |

---

## C++ WASM Renderer Status

### Current State
| Component | Status |
|-----------|--------|
| C++ Source | ✅ Complete (`wasm_renderer/`) |
| Build System | ✅ CMake + Emscripten |
| **Compiled Output** | ❌ **Not built** (`.wasm` is 0 bytes) |
| JS Bridge | ✅ Ready |

### To Build
```bash
cd wasm_renderer
./build.sh
# Requires: Emscripten SDK installed
```

### Integration Points
The WASM renderer provides the same interface as the JS renderer:
- Same bind group layout (bindings 0-12)
- Same uniform structure
- Same ping-pong texture system

---

## Future Enhancements

1. **Personalized Recommendations**
   - Track user history
   - Suggest shaders near used coordinates
   - "More like this" based on visual similarity

2. **Trending Shaders**
   - Time-decay algorithm for ratings
   - Daily/weekly trending lists

3. **Shader Collections**
   - User-created playlists
   - Official curated collections

4. **A/B Testing**
   - Test new shader versions
   - Compare ratings between variants

---

## Storage Manager Schema

```python
# Shader metadata stored in GCS
{
  "id": "unique-id",
  "name": "Display Name",
  "author": "ford442",
  "date": "2024-01-15",
  "type": "shader",
  "category": "liquid-effects",
  "description": "...",
  "filename": "liquid-v1.wgsl",
  "stars": 4.5,
  "rating_count": 42,
  "play_count": 1250,
  "tags": ["liquid", "ambient"],
  "coordinate": 15  # From coordinate system
}
```
