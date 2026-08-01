# App Structure — Foundation Wave 2 + frame split (#965, #1043)

Module map after the App.tsx strangler and WebGPU frame-seam extraction.

## Line counts (2026-08-01)

| Module | LOC | Epic target |
|--------|-----|-------------|
| [`src/App.tsx`](src/App.tsx) | ~692 | < 800 |
| [`src/components/controls/ControlsContainer.tsx`](src/components/controls/ControlsContainer.tsx) | ~400 | < 500 |
| [`src/components/app/AppShell.tsx`](src/components/app/AppShell.tsx) | ~442 | layout shell |
| [`src/components/app/AppOverlays.tsx`](src/components/app/AppOverlays.tsx) | ~294 | modals + overlays |
| [`src/renderer/WebGPURenderer.ts`](src/renderer/WebGPURenderer.ts) | ~470 | thin facade (IRenderer) |

**WebGPU modules** (`src/renderer/webgpu/`, see [`src/renderer/README.md`](../src/renderer/README.md)):

| Module | LOC | Mirrors |
|--------|-----|---------|
| `device.ts` | ~274 | `device.cpp` |
| `resources.ts` | ~332 | `resources.cpp` |
| `pipeline.ts` | ~470 | `pipeline.cpp` |
| `frame.ts` | **~194** | thin `frame.cpp` facade |
| `frameState.ts` | ~380 | renderer-owned state adapter |
| `present.ts` | ~167 | scale copy + present portion of `frame.cpp` |
| `slotDispatch.ts` | ~316 | slot/graph dispatch portion of `frame.cpp` |
| `audioDepth.ts` | ~104 | `audio_depth.cpp` |
| `WebGPUTiming.ts` | ~388 | `timing.cpp` |
| `WebGPUMediaInput.ts` | ~326 | (image/video in `audio_depth.cpp`) |

`frame.ts` owns RAF/media refresh, uniforms, the history-ring head, FPS, and top-level timing.
`slotDispatch.ts` owns parallel/chained ordering, the GraphRunner gate, quality pass caps,
compute timestamp phases, and feedback copies. The feedback contract is `dataB → dataC`
first and `dataA → dataC` last so primary simulation state wins. `present.ts` owns source
scale/copy, canvas texture acquisition, final pipeline selection, present timestamps, and submit.
The C++ side keeps `frame.cpp` as its facade until its presentation/dispatch sections grow again.

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

Directory: `src/components/controls/panels/` — see prior doc; `ControlsContainer` at ~400 LOC meets stretch target.

---

## Binding + device policy SoT

- [`docs/BINDING_CONTRACT.md`](BINDING_CONTRACT.md)
- [`src/renderer/webgpuDevicePolicy.ts`](../src/renderer/webgpuDevicePolicy.ts) ↔ [`wasm_renderer/device.cpp`](../wasm_renderer/device.cpp)
- CI: `npm run verify:device-policy`

---

## Multipass graph (Tier C)

- [`docs/MULTIPASS_GRAPH.md`](MULTIPASS_GRAPH.md)
- [`src/renderer/multipassGraph.ts`](../src/renderer/multipassGraph.ts)
- [`src/renderer/GraphRunner.ts`](../src/renderer/GraphRunner.ts) — invoked by `webgpu/slotDispatch.ts` for registered graph roots (same-frame handoff)

---

## Testing

```bash
npx react-scripts test --watchAll=false --ci
npm run verify:device-policy
SKIP_WASM_BUILD=1 npm run build
```

Thumbnails (requires GPU): see [`docs/THUMBNAIL_PIPELINE.md`](THUMBNAIL_PIPELINE.md) · `npm run thumbs:generate -- --missing` · status: `npm run thumbs:status`
