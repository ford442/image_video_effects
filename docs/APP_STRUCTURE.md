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

| Hook | File | Responsibility |
|------|------|----------------|
| `useDepthEstimation` | `src/hooks/useDepthEstimation.ts` | Xenova/transformers depth pipeline, `loadDepthModel`, `runDepthAnalysis`, depth map upload to renderer |
| `useAudioReactiveParams` | `src/hooks/useAudioReactiveParams.ts` | Bass/mid/treble → `zoomParam1–4` smoothing for generative shaders; RAF loop; analyzer start/stop; `A` / `[` / `]` shortcuts |
| `useShareChain` | `src/hooks/useShareChain.ts` | `?chain=` encode/decode, hash-based clip share links, share modal state, VJ chain share, `applySharedChain`, `copyChainShareLink` |

### App.tsx — still inline (TODO future waves)

| Module (proposed) | Responsibility |
|-------------------|----------------|
| `useShaderCatalogLoad` | Shader manifest fetch, `availableModes` boot, deep-workgroup filter |
| `useInputSourceLifecycle` | Image/video/webcam/generative/live input switching, B3HD, auto image timer |
| `useRemoteSync` | BroadcastChannel remote control, `buildFullState`, heartbeat |
| `AppShell.tsx` | Layout composition only |

Also still inline: AI VJ (`Alucinate`), roulette/chaos/generative showcase, WASM+TS recording, renderer switch, `SHADER_DEFAULTS` table, boot gate.

**Preserved globals:** `window.__pixelocity__`, `window.__rendererManager`, URL params (`?renderer=`, `?chain=`, `?testMode=`, hash state).

---

## Hooks index

All custom hooks export from `src/hooks/index.ts`:

- `useStorage`, `useWASM`, `useAudioAnalyzer`, `usePerformanceMonitor`
- **#913:** `useDepthEstimation`, `useAudioReactiveParams`, `useShareChain`

---

## Testing

```bash
npx react-scripts test --watchAll=false --ci
```

Build in Cloud VM: `SKIP_WASM_BUILD=1 npm run build`
