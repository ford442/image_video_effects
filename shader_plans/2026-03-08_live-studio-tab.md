# Live Studio Tab – HLS + WASM Toggle + Bilibili + Danmaku + Performance Dashboard

## Overview
A polished "Live Studio" tab that unifies HLS live video streaming, C++ WASM WebGPU rendering, and real-time agent swarming into a beautiful, professional interface. Users can stream from Bilibili or any HLS source, toggle between JS and WASM renderers instantly, and control Physarum swarm parameters with live performance feedback.

## Features
- **Live Studio Tab**: Dedicated workspace for live streaming + GPU rendering
- **Bilibili Integration**: Auto-fetch HLS streams from room IDs
- **Public HLS Fallback**: Support any standard HLS URL
- **Instant Renderer Toggle**: JS WebGPU ↔ C++ WASM with <100ms switch time
- **Live Performance Dashboard**: FPS counter, agent count, latency metrics
- **Physarum Controls**: Real-time sliders for swarm behavior
- **Danmaku Overlay**: Bullet comments floating over live video (optional)
- **Status Bar**: "WASM Active • 60 FPS • 50,000 agents" style indicator
- **Seamless Switching**: No shader reload on renderer change

## Technical Implementation

### Core Pipeline
```
[User Input]
    ├── Bilibili Room ID → API → m3u8 URL
    └── Public HLS URL → direct
              ↓
    [HLSVideoSource] → Video Element
              ↓
    [LiveStudioTab] → Frame callback
              ↓
    ┌─────────────────────────────┐
    │   Renderer (JS or WASM)     │
    │   - Video texture sampling  │
    │   - Agent simulation        │
    │   - Trail deposition        │
    │   - Audio reactivity        │
    └─────────────────────────────┘
              ↓
    [Canvas Display] + [Danmaku Overlay]
              ↓
    [Performance Dashboard]
```

### Proposed Code Structure

```
src/
├── components/
│   ├── LiveStudioTab.tsx       # Main tab component
│   ├── BilibiliInput.tsx       # Room ID → HLS fetcher
│   ├── RendererToggle.tsx      # JS/WASM switch with animation
│   ├── PerformanceDashboard.tsx # FPS, agents, latency stats
│   ├── PhysarumControls.tsx    # Swarm parameter sliders
│   ├── DanmakuOverlay.tsx      # Bullet comments layer
│   └── StreamSelector.tsx      # Bilibili vs Public URL
├── hooks/
│   ├── usePerformanceMonitor.ts # FPS tracking
│   ├── useBilibiliStream.ts    # Bilibili API integration
│   └── useDanmaku.ts           # Danmaku websocket
├── renderer/
│   ├── RendererManager.ts      # Unified renderer management
│   ├── JSRenderer.ts           # Updated with metrics
│   └── WASMRenderer.ts         # Updated with metrics
└── utils/
    ├── bilibili.ts             # API helpers
    └── danmaku.ts              # Danmaku parser
```

### Parameters

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| sensorAngle | 0-90° | 45° | Agent sensor spread |
| sensorDist | 1-50px | 9px | How far agents can see |
| turnSpeed | 0-0.5 | 0.1 | How fast agents turn |
| decayRate | 0.8-0.99 | 0.95 | Trail fade speed |
| depositAmount | 0.1-10 | 0.5 | Trail brightness |
| agentCount | 1000-100000 | 50000 | Number of agents |
| videoFoodStrength | 0-1 | 0.3 | Video brightness as food |
| audioPulseStrength | 0-1 | 0.5 | Audio reactivity |
| mouseAttraction | -1-1 | 0.5 | Mouse influence |
| danmakuIntensity | 0-1 | 0.3 | Bullet comment density |

## Integration Steps

### 1. Create src/components/LiveStudioTab.tsx
- Full tab layout with grid/flex
- Video canvas area (80% height)
- Control sidebar (20% width)
- Status bar at bottom

### 2. Create src/components/BilibiliInput.tsx
- Room ID input field
- "Fetch Stream" button
- Loading spinner during API call
- Error handling for invalid rooms

### 3. Create src/components/RendererToggle.tsx
- Animated toggle switch
- JS (blue) ↔ WASM (green)
- Shows current FPS on each side
- Disables during switch (<100ms)

### 4. Create src/components/PerformanceDashboard.tsx
- FPS counter (instant + rolling average)
- Agent count display
- Frame time graph (sparkline)
- Memory usage (if available)
- Renderer type badge

### 5. Create src/components/PhysarumControls.tsx
- Sliders for all parameters
- Real-time updates to renderer
- Preset buttons ("Gentle", "Chaotic", "Audio-Reactive")
- Reset to defaults button

### 6. Create src/components/DanmakuOverlay.tsx
- Canvas overlay on video
- Bullet comments float left-to-right
- Opacity control
- Color coding by user level

### 7. Create src/hooks/usePerformanceMonitor.ts
- requestAnimationFrame timing
- FPS calculation (instant + 1s average)
- Frame time tracking
- Jank detection (frames > 33ms)

### 8. Create src/hooks/useBilibiliStream.ts
- Fetch room info from Bilibili API
- Extract HLS URL from playurl
- Handle errors (offline, geo-blocked)
- Auto-retry logic

### 9. Update src/renderer/RendererManager.ts
- Unified interface for both renderers
- Hot-swap without losing state
- Metrics export (FPS, agent count)
- Video texture sharing

### 10. Update src/renderer/JSRenderer.ts & WASMRenderer.ts
- Add getMetrics() method
- Expose current agent count
- Report frame times

### 11. Update App.tsx or Controls.tsx
- Add "Live Studio" tab
- Route to LiveStudioTab component
- Pass audio context for reactivity

### 12. Test Integration
```bash
# Test Bilibili stream
Room ID: 21495945 (test room)

# Test public HLS
URL: https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8
```

### 13. Update Queue
```bash
python scripts/manage_queue.py complete "2026-03-08_live-studio-tab.md"
```

## Success Criteria
- [ ] Bilibili room ID fetches HLS successfully
- [ ] Public HLS URL plays correctly
- [ ] Toggle JS↔WASM < 100ms
- [ ] FPS display accurate to ±1 frame
- [ ] Agent count updates in real-time
- [ ] All sliders affect swarm immediately
- [ ] Danmaku displays over video (optional)
- [ ] Status bar shows all metrics
- [ ] No memory leaks on renderer switch
- [ ] Mobile-responsive layout

## UI Mockup

```
┌─────────────────────────────────────────────────────┐
│  🎥 LIVE STUDIO                    [JS ▼|▲ WASM]   │
├──────────────────────────────────────────┬──────────┤
│                                          │ Controls │
│    ┌────────────────────────────────┐   │ ──────── │
│    │                                │   │ Sensor   │
│    │      VIDEO + AGENTS            │   │ ├────●──┤│
│    │      + DANMAKU OVERLAY         │   │          │
│    │                                │   │ Decay    │
│    └────────────────────────────────┘   │ ├────●──┤│
│                                          │          │
│  Status: WASM Active • 60 FPS • 50K agents │ Agents │
│  Latency: 16ms | Frame: 0.3ms           │ ├────●──┤│
└──────────────────────────────────────────┴──────────┘
```
