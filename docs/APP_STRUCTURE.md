# App Structure — Foundation Wave 2 (#965)

Module map after App.tsx strangler completion and WebGPU modularization.

## Line counts (2026-07-19)

| Module | LOC | Epic target |
|--------|-----|-------------|
| [`src/App.tsx`](src/App.tsx) | ~560 | < 800 |
| [`src/components/controls/ControlsContainer.tsx`](src/components/controls/ControlsContainer.tsx) | ~340 | < 500 |
| [`src/components/app/AppShell.tsx`](src/components/app/AppShell.tsx) | ~399 | layout shell |
| [`src/components/app/AppOverlays.tsx`](src/components/app/AppOverlays.tsx) | ~280 | modals + overlays |
| [`src/renderer/WebGPURenderer.ts`](src/renderer/WebGPURenderer.ts) | ~1,390 | facade + delegates to `webgpu/*`; `GraphRunner` for Tier C multipass |

**WebGPU modules** (`src/renderer/webgpu/`): `WebGPUDeviceInit`, `WebGPUResourceManager`, `WebGPUShaderManager`, `WebGPUTiming` — wired from `WebGPURenderer.init()` and `setupGpuResources()`. `WebGPURenderLoop` exists for future full render-loop extraction (blit scale path still inline).

---

## App.tsx — hooks (all wired)

| Hook | File |
|------|------|
| `useDepthEstimation` | `src/hooks/useDepthEstimation.ts` |
| `useAudioReactiveParams` | `src/hooks/useAudioReactiveParams.ts` |
| `useShareChain` | `src/hooks/useShareChain.ts` |
| `useContentManifest` | `src/hooks/useContentManifest.ts` |
| `useShaderCatalogLoad` | `src/hooks/useShaderCatalogLoad.ts` |
| `useShaderBoot` | `src/hooks/useShaderBoot.ts` |
| `useImageLoading` | `src/hooks/useImageLoading.ts` |
| `useAiVjHandlers` | `src/hooks/useAiVjHandlers.ts` |
| `useWebcam` | `src/hooks/useWebcam.ts` |
| `useB3hdMode` | `src/hooks/useB3hdMode.ts` |
| `useRoulette` | `src/hooks/useRoulette.ts` |
| `useGenerativeShowcase` | `src/hooks/useGenerativeShowcase.ts` |
| `useRecording` | `src/hooks/useRecording.ts` |
| `useRemoteSync` | `src/hooks/useRemoteSync.ts` |
| `useTestHarness` | `src/hooks/useTestHarness.ts` |
| `useRendererBackend` | `src/hooks/useRendererBackend.ts` |
| `useShaderMode` | `src/hooks/useShaderMode.ts` |

Constants: [`src/app/constants/`](src/app/constants/) (`shaderDefaults`, `shaderCatalogUtils`, `defaultSlotParams`, `fallbackContent`).

**Intentional split (no monolithic facades):**

| Original proposal | Actual modules |
|-------------------|----------------|
| `useInputSourceLifecycle` | `useImageLoading`, `useWebcam`, `useB3hdMode`, `useShaderBoot`, `useShaderMode` |
| `useRendererLifecycle` | `useRendererBackend`, `useRecording`, `useTestHarness` |

**Render quality prop path:** `App.tsx` → `AppShell` → `Controls` (`renderQualityMode`, `onRenderQualityChange`, `performanceHud`, `maxActiveSlots`).

**Pure helpers + tests:** `shaderDefaults.ts` (`getShaderDefaults`), `shaderCatalogUtils.ts` (`determineCategory`).

---

## Controls — panels (#914)

Directory: [`src/components/controls/panels/`](../src/components/controls/panels/). [`ControlsContainer.tsx`](../src/components/controls/ControlsContainer.tsx) is a pure composition root (~340 LOC after hook extraction) that wires props into panels and hooks.

### Hooks (`src/components/controls/hooks/`)

| Hook | File | Responsibility |
|------|------|----------------|
| `useLiveControl` | `useLiveControl.ts` | MIDI/keyboard bindings, live action dispatch, auto-transition side effects |
| `useCoordinateNavigation` | `useCoordinateNavigation.ts` | Coordinate map, number-overlay jump, zone browser state |
| `useShaderMenuOptions` | `useShaderMenuOptions.ts` | Rating map, category-filtered modes, slot + generative mega-menu options |
| `useAiVjAutoTransition` | `useAiVjAutoTransition.ts` | Auto-transition UI state shared by Live Control + AI VJ studio |

### Panel inventory

| Panel | File | Mount condition |
|-------|------|-----------------|
| CoordinateBrowserOverlay | `panels/CoordinateBrowserOverlay.tsx` | always |
| InputSourcePanel | `panels/InputSourcePanel.tsx` | always |
| LiveControlPanel | `panels/LiveControlPanel.tsx` | always |
| RenderQualityPanel | `panels/RenderQualityPanel.tsx` | `onRenderQualityChange && performanceHud` |
| RendererBackendPanel | `panels/RendererBackendPanel.tsx` | `onSwitchRenderer` |
| ImageAutoSwitchPanel | `panels/ImageAutoSwitchPanel.tsx` | `inputSource === 'image'` |
| EffectCategoryPanel | `panels/EffectCategoryPanel.tsx` | always |
| RoulettePanel | `panels/RoulettePanel.tsx` | always |
| SlotStackPanel | `panels/SlotStackPanel.tsx` | always |
| ParamSlidersPanel | `panels/ParamSlidersPanel.tsx` | always |
| CoordinateDisplayPanel | `panels/CoordinateDisplayPanel.tsx` | `currentCoordinate !== null` |
| RecordingSharePanel | `panels/RecordingSharePanel.tsx` | always |
| AiVjStudioPanel | `panels/AiVjStudioPanel.tsx` | `inputSource === 'image'` |
| VideoSourcePanel | `panels/VideoSourcePanel.tsx` | `inputSource === 'video'` |
| WebcamSuggestionsPanel | `panels/WebcamSuggestionsPanel.tsx` | `showWebcamShaderSuggestions && isWebcamActive` |
| GenerativeSourcePanel | `panels/GenerativeSourcePanel.tsx` | `inputSource === 'generative'` |
| LiveStreamPanel | `../LiveStreamPanel.tsx` | `inputSource === 'live'` |
| AdvancedDebugPanel | `panels/AdvancedDebugPanel.tsx` | always |

**Deprecated (demo-only):** `RendererToggle` lives under `src/components/shaders/` for `ShaderDemo` only. Production renderer switching uses `RendererBackendPanel` → `RendererSwitcher`. Storage UI canonical path: `src/components/storage/StoragePanel.tsx` (`StorageBrowser` alias).

---

## Binding + device policy SoT

- [`docs/BINDING_CONTRACT.md`](BINDING_CONTRACT.md)
- [`src/renderer/webgpuDevicePolicy.ts`](../src/renderer/webgpuDevicePolicy.ts) ↔ [`wasm_renderer/device.cpp`](../wasm_renderer/device.cpp)
- CI: `npm run verify:device-policy`

---

## Multipass graph (Tier C)

- [`docs/MULTIPASS_GRAPH_SPEC.md`](MULTIPASS_GRAPH_SPEC.md)
- [`src/renderer/multipassGraph.ts`](../src/renderer/multipassGraph.ts)
- [`src/renderer/GraphRunner.ts`](../src/renderer/GraphRunner.ts) — wired in `WebGPURenderer.dispatchSlot()` for `quantum-foam-pass1` (same-frame handoff demo)

---

## Testing

```bash
npx react-scripts test --watchAll=false --ci   # 289 tests (incl. shaderDefaults, shaderCatalogUtils)
npm run verify:device-policy
SKIP_WASM_BUILD=1 npm run build
```

Thumbnails (requires GPU): `npm run thumbnails:generate` · status: `npm run thumbnails:status`
