# App Structure — Foundation Wave 2 (#965)

Module map after App.tsx strangler completion and WebGPU modularization.

## Line counts (2026-07-19)

| Module | LOC | Epic target |
|--------|-----|-------------|
| [`src/App.tsx`](src/App.tsx) | ~560 | < 800 |
| [`src/components/controls/ControlsContainer.tsx`](src/components/controls/ControlsContainer.tsx) | ~400 | < 500 |
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

Directory: `src/components/controls/panels/` — see prior doc; `ControlsContainer` at ~400 LOC meets stretch target.

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
