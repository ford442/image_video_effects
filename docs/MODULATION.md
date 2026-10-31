# Modulation bus (#1513 Part A)

Slot params used to change only when a person or AutoDJ moved them. The modulation bus lets
LFOs, envelopes, audio bands, a step sequencer, a random walk and external controllers drive
any slot param, including the compositor's per-slot `opacity` (#1512). It is evaluated in the
render worker every frame, with no main-thread round trip.

Code: `src/modulation/` (pure TS, no DOM), UI in `src/components/modulation/`.

## Sources

Every source outputs a value in `[0, 1]`.

| kind | fields | notes |
|---|---|---|
| `lfo` | `shape` (`sine` `tri` `saw` `square` `sh`), `unit` (`hz` \| `beats`), `rate`, `phase?`, `seed?` | `unit: 'hz'`: `rate` cycles per second. `unit: 'beats'`: `rate` is the period in beats (tempo-synced). `sh` = sample & hold, seeded. |
| `adsr` | `attack` `decay` `sustain` `release` (seconds, sustain 0..1), `gate` | `gate`: `{from:'onset'}` (a trigger: A→D→R), `{from:'external', key}` (held while > 0.5), `{from:'beat', every, length}` (open `length` beats every `every` beats). |
| `audio` | `band` (`bass` `mid` `high` `onset`) | From the renderer's existing audio analysis (`audioDepth`). `onset` is a bass-flux follower that jumps to 1 and decays (~120 ms). |
| `sequencer` | `steps` (16 numbers 0..1), `stepBeats` | Step `floor(beats / stepBeats) mod 16`; `0.25` = sixteenth notes. |
| `random` | `seed`, `rate` (steps/s), `step` (max move per step) | Seeded random walk, starts at 0.5. |
| `external` | `key` | Latest value from `controlBindings` (MIDI CC / note / keys; OSC adapters dispatch through the same registry), keyed `${source}:${id}`, e.g. `midi-cc:ch1/cc7`. Every dispatched event is seen, bound or not (`addControlEventTap`). |

## Routes

```ts
interface Route {
  id: string;
  source: ModSource;                 // inline spec (self-contained when saved)
  target: { slot: number; param: 'p1' | 'p2' | 'p3' | 'p4' | 'opacity' };
  depth: number;                     // in the target param's units
  offset: number;                    // in the target param's units
  curve: 'linear' | 'exp' | 'smooth';
}
```

```
modulated = clamp(base + depth * curve(src) + offset, min, max)
```

* `base` is what the UI (or AutoDJ) set. `min` / `max` are the param's range from the shader
  definition (opacity: 0..1). The page store resolves them into a `ResolvedRoute` before the
  routes go to the renderer; the sliders and the panel report ranges (`modulationStore.setRange`).
* Curves map `[0,1]` onto `[0,1]`: `linear` x, `exp` (e^(4x) − 1)/(e^4 − 1), `smooth` smoothstep.
* Several routes on one target sum their `depth * curve(src) + offset` before the single clamp.
* Opacity only changes the picture for slots whose layer output is `blend` (compositor rule).

## Where the overlay is applied

* Page: `modulationStore` (`src/modulation/store.ts`) holds routes, BPM and the panel target.
  Every change is mirrored into the page realm's `ModulationRuntime` and announced.
* `WorkerWebGPUBackend` sends the routes with the `setModulation` command (on init — so a
  recovered worker gets them again — and on every change) and controller values with
  `setModulationExternal`. `renderWorkerHost` feeds them to the worker realm's runtime.
* `WebGPUFrameRenderer.renderFrame` (`src/renderer/webgpu/frame.ts`) calls
  `getModulationRuntime().applyOverlay(state.slots, state.currentTime, state.audioDepth)` right
  after the input ring drain, encodes the frame, then restores. The overlay swaps each modulated
  slot's `params` / `layer` for modulated copies for that frame only, so base values are never
  written and nothing flows back to UI state.
* `?renderer=main` runs the same `frame.ts` against the page realm's runtime, which the store
  updates directly: one evaluator for both render threads. The WASM renderer is not modulated.

## Determinism contract

* Same `ModClock` samples + same seeds ⇒ bit-identical output (unit-tested with a fake clock,
  `src/modulation/modulation.test.ts`). Randomness is an integer hash (`Math.imul`), no
  `Math.random`.
* LFO, sequencer, S&H and random walk are functions of clock time only (the walk is
  tick-indexed), so their value at time t does not depend on the frame rate. ADSR and onset
  integrate per sample and are deterministic for a given sample sequence and input.
* If the clock goes backwards, the random walk restarts from tick 0.

## ModClock seam for #1401

```ts
interface ModClock { now(): number /* seconds */; bpm(): number; }
```

Today the runtime uses a frame clock (`now` = the renderer's `currentTime`, `bpm` = the store's
BPM). #1401's RenderClock plugs in with `getModulationRuntime().setClock(renderClock)` in each
realm (in the worker: from the host when #1401 adds its command); `setClock(null)` restores the
frame clock. Nothing else changes.

## Persistence

Project file schema v3 (`src/contracts/project_file.json`) adds a required `modulation: Route[]`
(at most 256, unique ids, slot 0..5). `migrateV2ToV3` adds `modulation: []`; v1 and the legacy
v0 formats step through it, so old files still import. On import, routes whose slot is empty
after the shader check are dropped with a warning; a project replaces the whole bus.

## UI

* "∿" (Modulate…) next to each slot param slider opens the panel pre-targeted at that param.
* The panel (`ModMatrixPanel`, lazy chunk `mod-matrix`) is a sources × targets grid: add a source
  from the presets, tick a cell to create a route, then set depth, offset and curve. BPM is set
  at the top. Esc or ✕ closes it.
