<<<<<<< HEAD
# App Structure — Foundation Epic #912 Wave 3

Module map after the Wave 3 strangler refactor (`chore/foundation-912-w3`). Behavior is preserved; this documents where logic lives and what remains in the monoliths.

## Line counts (Wave 3)

| Module | Before | After |
|--------|--------|-------|
| `src/App.tsx` | 2397 | 2076 |
| `src/components/Controls.tsx` | 1834 | 1663 |

Stretch targets (App &lt;1200, Controls &lt;400) are **future waves** — not safe in one pass without risking regressions.

---

## App.tsx — extracted hooks (Issue #913)
=======
# App Structure — Foundation Epic #912 (#913)

Module map after the App.tsx strangler refactor. Behavior is preserved; this documents where logic lives and what remains in the monolith.

## Line counts

| Module | Before | After |
|--------|--------|-------|
| `src/App.tsx` | ~2479 | ~2160 |
| `src/components/Controls.tsx` | ~2211 | 2 (re-export) |
| `src/components/controls/ControlsContainer.tsx` | — | ~1167 |

Stretch targets (App &lt;600, ControlsContainer &lt;400) require future waves — not safe in one pass without regressions.

---

## Controls — extracted panels (#914)

Directory: `src/components/controls/`

| File | Responsibility |
|------|----------------|
| `Controls.tsx` | Thin re-export of `ControlsContainer` |
| `ControlsContainer.tsx` | Props wiring, local state, panel composition |
| `types.ts` | `ControlsProps`, `ShaderCoordData` |
| `hooks/useLiveControl.ts` | MIDI/keyboard bindings, auto-transition side effects |

| Panel | File | Responsibility |
|-------|------|----------------|
| `RendererBackendPanel` | `panels/RendererBackendPanel.tsx` | Canonical `RendererSwitcher` wrapper |
| `SlotStackPanel` | `panels/SlotStackPanel.tsx` | Six shader slots, compile status, mega-menu |
| `ParamSlidersPanel` | `panels/ParamSlidersPanel.tsx` | Active-slot param sliders |
| `InputSourcePanel` | `panels/InputSourcePanel.tsx` | Input source radios |
| `RecordingSharePanel` | `panels/RecordingSharePanel.tsx` | Record clip + screenshot |
| `LiveControlPanel` | `panels/LiveControlPanel.tsx` | MIDI arm/learn UI |
| `RoulettePanel` | `panels/RoulettePanel.tsx` | Randomize, chaos, audio-reactive |
| `CoordinateBrowserOverlay` | `panels/CoordinateBrowserOverlay.tsx` | Number-jump + coordinate browser modals |
| `AdvancedDebugPanel` | `panels/AdvancedDebugPanel.tsx` | Dev tools, storage browser entry |

**Renderer switcher:** `RendererSwitcher` + `RendererBackendPanel` is canonical. `RendererToggle` (root + shaders/) and `WASMToggle` are `@deprecated`.

**Still inline in ControlsContainer:** AI VJ studio block, video/B3HD, generative picker, effect category filter.

---

## App.tsx — extracted hooks (#913)
>>>>>>> origin/main

| Hook | File | Responsibility |
|------|------|----------------|
| `useDepthEstimation` | `src/hooks/useDepthEstimation.ts` | Xenova/transformers depth pipeline, `loadDepthModel`, `runDepthAnalysis`, depth map upload to renderer |
| `useAudioReactiveParams` | `src/hooks/useAudioReactiveParams.ts` | Bass/mid/treble → `zoomParam1–4` smoothing for generative shaders; RAF loop; analyzer start/stop; `A` / `[` / `]` shortcuts |
| `useShareChain` | `src/hooks/useShareChain.ts` | `?chain=` encode/decode, hash-based clip share links, share modal state, VJ chain share, `applySharedChain`, `copyChainShareLink` |

### App.tsx — still inline (TODO future waves)

<<<<<<< HEAD
- **`useShaderCatalogLoad`** — shader manifest fetch, `availableModes` boot, deep-workgroup filter (not extracted this wave)
- **`useInputSourceLifecycle`** — image/video/webcam/generative/live input switching, B3HD, auto image timer
- **`useRemoteSync`** — BroadcastChannel remote control, `buildFullState`, heartbeat
- **AI VJ** — `Alucinate` lifecycle, presets, auto-transition
- **Roulette / chaos / generative showcase** — slot randomization, keyboard shortcuts (`G`, `R`, space)
- **Recording** — MediaRecorder, countdown overlay (share modal opened via `useShareChain.openRecordingShareModal`)
- **Renderer switch** — `handleSwitchRenderer`, FPS buckets, canvas HUD `RendererToggle` (overlay only; not Controls)
- **`SHADER_DEFAULTS` / `getShaderDefaults`** — large static table (~120 lines); candidate for `src/utils/shaderDefaults.ts`
- **Boot gate** — `rendererReady` + `shadersReady` coordinated init

Preserved globals: `window.__pixelocity__`, `window.__rendererManager`, URL params (`?renderer=`, `?chain=`, `?testMode=`, hash state).

---

## Controls.tsx — extracted panels (Issue #914)

Directory: `src/components/controls/panels/`

| Panel | File | Responsibility |
|-------|------|----------------|
| `RendererBackendPanel` | `RendererBackendPanel.tsx` | Thin wrapper around **`RendererSwitcher`** (canonical production renderer UI) |
| `ParamSlidersPanel` | `ParamSlidersPanel.tsx` | Active-slot shader param sliders (catalog params + generic fallback) |
| `SlotStackPanel` | `SlotStackPanel.tsx` | Six shader slots, compile status, mega-menu, per-slot gallery |

### Controls.tsx — still inline (TODO)

- Input source radios, effect category filter, image auto-switch
- Roulette section, AI VJ controls, VJ history/presets/My Sets
- Video/B3HD, webcam, generative picker, live stream panel
- Coordinate browser / number jump overlay
- Lighting & post sliders (lightStrength, ambient, etc.)
- Chain share UI (paste link) — uses props from `useShareChain`
- Dev tools (shader scanner, storage browser triggers)

### Renderer switcher consolidation (#914)

| Component | Status |
|-----------|--------|
| `RendererSwitcher.tsx` | **Canonical** — used by `RendererBackendPanel` → `Controls` |
| `RendererBackendPanel.tsx` | Production Controls path |
| `RendererToggle.tsx` (root) | `@deprecated` — App canvas FPS HUD + `LiveStudioTab` |
| `components/shaders/RendererToggle.tsx` | `@deprecated` — `ShaderDemo` only |
| `WASMToggle.tsx` | `@deprecated` — legacy floating button; no parallel switch logic in Controls |
=======
| Module (proposed) | Responsibility |
|-------------------|----------------|
| `useShaderCatalogLoad` | Shader manifest fetch, `availableModes` boot, deep-workgroup filter |
| `useInputSourceLifecycle` | Image/video/webcam/generative/live input switching, B3HD, auto image timer |
| `useRemoteSync` | BroadcastChannel remote control, `buildFullState`, heartbeat |
| `AppShell.tsx` | Layout composition only |

Also still inline: AI VJ (`Alucinate`), roulette/chaos/generative showcase, WASM+TS recording, renderer switch, `SHADER_DEFAULTS` table, boot gate.

**Preserved globals:** `window.__pixelocity__`, `window.__rendererManager`, URL params (`?renderer=`, `?chain=`, `?testMode=`, hash state).
>>>>>>> origin/main

---

## Hooks index

All custom hooks export from `src/hooks/index.ts`:

- `useStorage`, `useWASM`, `useAudioAnalyzer`, `usePerformanceMonitor`
<<<<<<< HEAD
- **Wave 3:** `useDepthEstimation`, `useAudioReactiveParams`, `useShareChain`

---

## TypeScript (#920 slice)

- `tsconfig.json` `target` raised **es5 → ES2020** (stretch). No mass `@ts-ignore` hunt this wave.
=======
- **#913:** `useDepthEstimation`, `useAudioReactiveParams`, `useShareChain`
>>>>>>> origin/main

---

## Testing

<<<<<<< HEAD
After each extraction: `npx react-scripts test --watchAll=false --ci` (180 tests, all green at Wave 3 landing).
=======
```bash
npx react-scripts test --watchAll=false --ci
```
>>>>>>> origin/main

Build in Cloud VM: `SKIP_WASM_BUILD=1 npm run build`
