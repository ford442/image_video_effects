# Image/Video Effects Project Evolution Plan

## Project Overview

This is a WebGPU-powered real-time image and video effects application built with React and TypeScript. The project features:

- **35+ shader effects** for images and videos (and growing)
- **AI-powered depth estimation** using DPT-Hybrid-MIDAS model
- **Real-time WebGPU compute shaders** for high-performance rendering
- **Interactive effects** with mouse/touch input for ripples and particles
- **Depth-aware effects** that respond to 3D scene geometry
- **Temporal persistence** for trail and motion blur effects

### Architecture Strengths

The project uses an elegant "Universal BindGroup" architecture where:
- All shaders share the same uniform interface
- New effects can be added by simply dropping in a `.wgsl` file
- No TypeScript recompilation needed for new shaders
- Hot-reload workflow supports rapid effect development

## Current Challenge: UI Scalability

With **35+ shaders** (and growing), the current dropdown selection interface has become:
- **Non-descriptive**: Users can't preview effects before selecting
- **Overwhelming**: Long list with no visual organization
- **Inefficient**: Trial-and-error to find desired effect
- **Not discoverable**: New users don't know what effects look like

## Proposed UI Improvements

### Phase 1: Grid Gallery View (Short-term)

Transform the shader selection from a dropdown to a **visual grid gallery**:

```
┌─────────────────────────────────────────────────────────┐
│  Effect Gallery                           [Image] [Video]│
├─────────────────────────────────────────────────────────┤
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐│
│  │ 🌊   │ │ 🌀   │ │ ⚡   │ │ 🎨   │ │ 🔮   │ │ 👁️   ││
│  │Liquid│ │Vortex│ │Plasma│ │Kaleid│ │Cosmic│ │LiDAR ││
│  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘│
│                                                          │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐│
│  │ 🎭   │ │ 📺   │ │ 🧊   │ │ 🌈   │ │ 🔥   │ │ ...  ││
│  │Holo  │ │CRT TV│ │Pixel │ │Spectr│ │Neon  │ │      ││
│  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘│
│                                                          │
│  Search: [____________]  Category: [All ▼]               │
└─────────────────────────────────────────────────────────┘
```

**Benefits:**
- Visual browsing with thumbnail previews
- Emoji/icon indicators for quick identification
- Searchable and filterable
- Shows 6-12 effects at once
- Hover for description tooltip

**Implementation:**
- Create new `ShaderGallery.tsx` component
- Use CSS Grid for responsive layout
- Generate thumbnail placeholders (Phase 2: real screenshots)
- Add search/filter functionality
- Maintain backward compatibility with existing controls

### Phase 2: Automatic Screenshot Generation (Mid-term)

Generate preview thumbnails automatically for each shader:

**Automatic Capture System:**
```typescript
// Pseudo-code approach
class ThumbnailGenerator {
  async generateAllThumbnails() {
    for (shader of shaderList) {
      1. Load shader
      2. Apply to test image (canonical scene)
      3. Wait for render stabilization (~2 seconds)
      4. Capture canvas as PNG
      5. Resize to 200x150px thumbnail
      6. Save to public/thumbnails/{shader-id}.png
      7. Update shader-list.json with thumbnail path
    }
  }
}
```

**Technical Implementation:**
- **Build-time generation**: Run as npm script before deployment
- **Test scene**: Use a canonical reference image (colorful, geometric shapes)
- **Canvas capture**: Use `canvas.toBlob()` or `canvas.toDataURL()`
- **Automation**: Puppeteer/Playwright for headless browser testing
- **CI/CD integration**: Auto-generate on new shader commits

**Alternative: Manual Curation**
- Developer captures representative screenshots
- Curated for best visual representation
- Consistent timing/composition across all effects

**Data Structure Update:**
```json
{
  "id": "liquid",
  "name": "Liquid (Interactive)",
  "url": "shaders/liquid.wgsl",
  "thumbnail": "thumbnails/liquid.png",
  "category": "image"
}
```

### Phase 3: Enhanced Organization (Mid-term)

**Categorization System:**
```
Categories:
├── Liquid & Flow (15 shaders)
├── Distortion & Warp (8 shaders)
├── Color & Light (7 shaders)
├── Geometric & Pattern (5 shaders)
├── Glitch & Digital (4 shaders)
└── Procedural Generation (3 shaders)
```

**Tagging System:**
```json
{
  "id": "cosmic-flow",
  "tags": ["animated", "depth-aware", "colorful", "abstract", "sci-fi"],
  "difficulty": "advanced",
  "performance": "medium"
}
```

**Advanced Filters:**
- Performance level (light/medium/heavy)
- Interactive vs. Passive
- Depth-aware vs. Flat
- Color-based vs. Geometric
- Beginner/Advanced complexity

### Phase 4: Interactive Preview (Long-term)

**Live Preview on Hover:**
- Small preview window shows effect in real-time
- 10-second looping animation
- No need to switch main view
- Reduces friction in effect discovery

**Quick Compare Mode:**
- Select 2-4 effects to compare side-by-side
- A/B testing different parameters
- Export comparisons as video/GIF

## Path to More Complex Effects

### Current Effect Complexity Levels

**Level 1: Basic Effects** (Examples: liquid-fast, vortex)
- Single-pass compute shader
- Simple UV distortion or color manipulation
- ~100-200 lines of WGSL

**Level 2: Intermediate Effects** (Examples: rain, kaleidoscope, plasma)
- Multi-pass rendering or temporal persistence
- Noise functions and procedural generation
- Depth-aware parallax
- ~200-400 lines of WGSL

**Level 3: Advanced Effects** (Examples: lidar, bioluminescent, cosmic-flow)
- Complex state management across frames
- Multiple textures for persistence/trails
- Interactive particle systems
- Advanced depth integration
- ~400-600 lines of WGSL

### Future Complexity Pathways

#### Path A: Multi-Pass Effect Chains

Allow combining multiple shaders in sequence:
```
Image → Liquid → Chromatic Aberration → Vortex → Output
```

**Implementation:**
- Effect pipeline builder UI
- Each shader outputs to next shader's input
- Save/load effect chains as presets

#### Path B: Shader Parameters UI

Currently most shaders have hardcoded parameters. Next steps:
1. ✅ **Done**: Generic `zoom_params` vec4 for 4 float sliders
2. **In Progress**: Some shaders expose params via Controls.tsx
3. **Future**: Auto-generate UI from shader metadata

**Enhanced Metadata System:**
```json
{
  "id": "lidar",
  "params": [
    {
      "id": "speed",
      "name": "Scan Speed",
      "type": "float",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "description": "Controls how fast the scanner moves"
    }
  ],
  "advanced_params": [
    {
      "id": "mode",
      "name": "Scan Pattern",
      "type": "enum",
      "values": ["linear", "radial", "spiral"],
      "default": "linear"
    }
  ]
}
```

#### Path C: Compute Shader Enhancements

Leverage more advanced WebGPU features:
- **Indirect dispatch**: Dynamic workgroup sizes based on scene complexity
- **Atomic operations**: Better particle systems and collision detection
- **Shared memory**: Faster neighborhood sampling for convolution effects
- **Multi-draw indirect**: Render thousands of interactive particles

#### Path D: AI/ML Integration

Beyond depth estimation:
- **Semantic segmentation**: Apply effects only to people, objects, or backgrounds
- **Pose estimation**: Effects that follow body movements
- **Style transfer**: Real-time artistic style application
- **Object tracking**: Effects locked to moving objects in video

#### Path E: 3D Effects & Camera

- **Real 3D meshes**: Displace vertices based on depth map
- **Camera controls**: Orbit, pan, zoom through 3D scene
- **Lighting systems**: Dynamic shadows and reflections
- **Particle emitters**: 3D particle systems that respect depth

## Implementation Roadmap

### Immediate (Week 1-2)
- [x] Add 2 new shader effects
- [x] Create this plan.md document
- [ ] Prototype grid gallery layout (CSS only)
- [ ] Add emoji/icon indicators to shader-list.json

### Short-term (Month 1)
- [ ] Implement ShaderGallery.tsx component
- [ ] Add search and category filtering
- [ ] Manual screenshot capture for top 10 shaders
- [ ] Deploy gallery view as default UI

### Mid-term (Month 2-3)
- [ ] Build automatic screenshot generator script
- [ ] Generate thumbnails for all 39+ shaders
- [ ] Implement tagging and metadata system
- [ ] Add performance indicators
- [ ] Create "Featured" and "New" badges

### Long-term (Month 4-6)
- [ ] Live preview on hover
- [ ] Effect comparison mode
- [ ] Effect chain builder (combine multiple shaders)
- [ ] Advanced parameter UI generation
- [ ] Mobile-optimized gallery
- [ ] Share/export gallery snapshots

## Technical Considerations

### Performance
- **Thumbnail loading**: Lazy load thumbnails as user scrolls
- **Preview generation**: Debounce hover previews
- **Caching**: Cache rendered previews in IndexedDB
- **Optimization**: Use WebP format for smaller thumbnail sizes

### Accessibility
- **Keyboard navigation**: Grid navigation with arrow keys
- **Screen readers**: Proper ARIA labels for all effects
- **Reduced motion**: Respect prefers-reduced-motion for animations
- **Color contrast**: Ensure text readable on all thumbnails

### Backward Compatibility
- Keep dropdown as fallback option
- Settings to switch between gallery/list view
- URL parameters to deep-link to specific shaders

### Scalability
- Support for 100+ shaders without performance degradation
- Pagination or infinite scroll for large galleries
- Cloud storage for thumbnails (CDN)

## Conclusion

This project has excellent foundations with its Universal BindGroup architecture. The path forward focuses on:

1. **Improving discoverability** through visual gallery UI
2. **Reducing friction** with automatic thumbnail generation
3. **Enabling complexity** through better organization and tooling
4. **Future-proofing** with extensible metadata and parameter systems

The modular shader system allows for rapid experimentation, and with proper UI/UX improvements, this can become a powerful creative tool for artists and developers exploring real-time GPU-accelerated effects.
