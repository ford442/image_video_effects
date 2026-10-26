# VJ Studio — Performer Guide

VJ Studio is the unified control surface for live visual performance in Pixelocity. Open **Controls** and expand **🎬 VJ Studio** at the top.

## Quick start

1. Load shaders into slots 1–6 via the slot stack below Studio.
2. Adjust parameters with on-screen sliders (touch-friendly on mobile).
3. Copy a **chain URL** to share your full stack + params with another machine.
4. Optional: map MIDI knobs to parameters (desktop + MIDI hardware).

## Studio sections

| Section | What it does |
|---------|----------------|
| **Active slots** | Jump between slots; shows shader id per slot |
| **Transitions** | Auto-transition timer or audio beat (requires AI VJ mode for some paths); a duration above 0 dissolves a shader change ([Cue crossfade](#cue-crossfade)) |
| **MIDI & keyboard** | Map hardware CCs, notes, or keys to params and actions |
| **OSC** | Opt-in bridge for live desks (TouchOSC, Max, Resolume…) via a local relay |
| **Audio-reactive** | Drive parameter motion from microphone / audio analysis on every active slot |
| **Share & export** | Chain URL, VJ set link, JSON export/import, set recorder |
| **My VJ sets** | Locally saved stacks (browser storage) |
| **VJ history** | Restore recent AI-generated stacks |

## MIDI learn (no console required)

1. Expand **VJ Studio → MIDI & keyboard** and enable MIDI.
2. On any parameter slider, click the **🎛** button next to the param name.
3. Move a knob or press a pad on your controller (or press a key for keyboard mapping).
4. Click **Confirm** when the capture appears.

Bindings persist in `localStorage` (`vj_control_bindings`). Bindings can target slots 1–6 (the physical slot cap in `src/contracts/slot_limits.json`).

**Layer opacity (#1512):** a binding can target **Slot Opacity (layer)** (`setSlotOpacity`) instead of a slider. A knob or fader then sets that slot's compositor opacity from 0 to 1. It only shows in a parallel group where the slot blends ([PARALLEL_SLOTS.md](PARALLEL_SLOTS.md#layer-compositor-1512)).

**Channels:** every binding id includes the MIDI channel (`ch1/cc7` ≠ `ch2/cc7`), so two controllers on different channels never collide.

**14-bit faders:** enable **14-bit CC (MSB/LSB pairs)** under MIDI & keyboard to pair CC 0–31 with CC 32–63 (16 384 steps instead of 128). The coarse MSB still fires on its own, so 7-bit gear keeps working; leave the toggle off if your controller uses CC 32–63 as independent knobs.

## Audio-reactive parameters

Toggle **Audio-reactive parameters** (or press `A`; `[` / `]` change the amount).

- Drives sliders on **every active slot** up to the quality-tier slot cap (1–3), not only slot 1.
- **Generative** shaders map their four params to bass / mid / treble / overall (from `params[].audio`, else by position).
- **Simulation, interactive-mouse and graph** shaders are driven only for params that declare `audio` in their JSON (`"audio": "bass"` or `{ "fft": 12 }`) — graphs without metadata are left alone.
- **Hands win:** grabbing a slider, arming 🎛 MIDI learn on it, or moving a mapped MIDI CC / OSC fader freezes audio on that param. On release, audio resumes *around the value you left it at* instead of snapping back to the shader default.
- **Layer opacity** can follow a band too: pick ♪ bass / mid / treble / overall in a slot's layer strip. While audio reactivity is on, the band gates the opacity fader, renderer side only, so the fader keeps its value.
- The analyser spectrum still reaches WGSL as `plasmaBuffer[0].xyz` and FFT bins in `extraBuffer[5..132]` (engine-owned; shaders must not store state there).

## OSC

Browsers cannot receive UDP, so OSC goes through a tiny relay in `storage_manager` that forwards raw datagrams over a WebSocket. OSC is **off by default**.

1. Run a local storage manager with the relay enabled:
   ```bash
   OSC_RELAY_ENABLED=1 uvicorn storage_manager.app:app --host 127.0.0.1 --port 7860
   ```
   Optional env: `OSC_UDP_HOST` (default `127.0.0.1`), `OSC_UDP_PORT` (default `9000`), `OSC_ALLOWED_ORIGINS` (extra comma-separated page origins; localhost is always allowed).
2. Open Pixelocity with `?osc=1`, or tick **VJ Studio → OSC → Enable OSC bridge**. The default relay URL is `ws://127.0.0.1:7860/osc/ws`; override with `?osc_ws=ws://host:port/osc/ws` or the URL field.
3. Point your controller at UDP `127.0.0.1:9000`.

### Address space

| Address | Args | Effect |
|---------|------|--------|
| `/pixelocity/slot/{0-5}/param/{x\|y\|z\|w}` | `f` (0–1; `i` / `T` / `F` accepted) | Set slider 1–4 of that slot (clamped). Freezes host audio on it briefly. |
| `/pixelocity/slot/{0-5}/shader` | `s` | Load a shader id into the slot (`none` clears; unknown ids are ignored) |
| `/pixelocity/slot/{0-5}/opacity` | `f` (0–1) | The slot's layer-compositor opacity (#1512) |
| `/pixelocity/transition` | optional `s` / `f` | Fire the next transition (a `0` — button release — is ignored). Bare, it cuts exactly as a MIDI binding does; with the string `crossfade` a shader change dissolves ([Cue crossfade](#cue-crossfade)) |
| `/pixelocity/audio/amount` | `f` (0–1) | Host audio-reactive amount |

Slots are 0-based on the wire (slot `0` = "Slot 1" in the UI). Slots beyond the current stack are ignored. Bundles are supported (applied immediately; timetags ignored).

Quick test from a terminal (needs `pip install python-osc`):

```bash
python3 -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 9000).send_message('/pixelocity/slot/0/param/x', 0.42)"
```

The OSC decoder ships as a lazy `osc` chunk — it is never in the main bundle (`npm run verify:bundle-size` enforces this).

## Share links

- **Copy chain URL** — encodes up to 6 slots with compact params (`?chain=…`). Safe to bookmark or send in chat.
- **Share VJ set link** — includes vibe metadata when available.
- **Export JSON** — full portable file including optional MIDI bindings; use **Import JSON** to restore on another machine.

## Project files

Use **Export project (.pixelocity.json)** to download a user-owned session file; no account or server is involved. **Import project…** validates the complete file before applying any part of it and lists anything that needs attention.

Project schema v2 is an envelope around the existing formats, not another shader-stack model:

- `chain` embeds `SharedChain` unchanged, including its own `v`, ordered slots, compact params, enabled flags, and chain/parallel modes. Since v2 (#1512) a chain slot can also carry its layer-compositor output, in the same compact keys as chain URLs (`b=`, `o=`, `m=`, `f=`, `k=` below).
- The envelope adds the active slot, safe image/video/stream references or generative shader id, render quality, MIDI/keyboard mappings, and an optional embedded `VjSetExportPayload` recording.
- Unknown shader ids become empty slots with a warning. A source that is not in the current media catalog becomes `none` with a relink warning.
- Media bytes, `data:`/`blob:` URLs, camera or microphone permission state, device/track handles, transient GPU objects, and adaptive render-scale telemetry are never saved. Webcam projects save only the source choice and ask the browser for permission again when applied.

The contract is [`src/contracts/project_file.json`](../src/contracts/project_file.json) (JSON Schema draft 2020-12). Project migrations are explicit one-version steps (`src/services/project/migrate.ts`):

- Version 0 compatibility accepts a bare `SharedChain` or an existing v1 `.vjset.json` and lifts it into project v1.
- v1 → v2 (`migrateV1ToV2`) drops any compositor keys a v1 file could not have meant, so a v1 project opens exactly as before, every layer on *Replace*.
- Unknown future versions are rejected with a reason.

Chain URLs, preset packs, and the older VJ-set export remain separate and backward-compatible.

**Layer outputs in chain URLs and projects.** A slot whose output is not the default adds compact fields, which round-trip through chain URLs and project files:

| Field | Meaning |
|---|---|
| `b` | Blend mode, or `mask` for a mask slot |
| `o` | Opacity, 0–1 |
| `m` | Mask: `luma`, `depth` or `slot<n>`, with a `~` prefix for inverted |
| `f` | Feather |
| `k` | Key threshold |

A malformed field is dropped on its own; the slot is kept. Older builds ignore the fields.

## Cue crossfade

Recalling a saved set used to cut the picture whenever the shader stack changed: sliders eased, shader ids did not. With a duration above 0 the **TypeScript WebGPU renderer** dissolves instead.

- **One frozen image, one mix.** On cue start the renderer copies the last presented color into a single `rgba8unorm` texture at the canvas size (the *hold*). The present pass then mixes it over the live frame: mix 1 shows the hold, mix 0 the new stack, and the ramp is the transition orchestrator's eased progress (`crossfadeMix` in `src/utils/transitionMath.ts`). The mix is a 16-byte uniform on the blit pipeline only, never in the compute `Uniforms` struct, `zoom_params` or `extraBuffer`. Recording grabs the presented frame, so a recording captures the dissolve.
- **One copy per cue.** A cue during a cue replaces the hold with what is on screen at that moment and restarts the ramp; there is no queue of holds. The texture exists only while the fade runs.
- **Only a change of shader identity holds.** The first change to a slot's shader id, its enabled state or its chained/parallel mode after a cue is armed sends the single `startCrossfade` command; the rest of that recall lands inside the same fade. Slider moves — randomize transitions, audio, MIDI — keep lerping and never allocate a hold.
- **Who fires it.** Recalling a chain from the Studio panels (**My VJ sets**, an imported `.vjset.json`, preset packs, the community gallery), the **Next transition ▸** button under *Auto Transition* (a *Cycle Presets* swap), and OSC `/pixelocity/transition crossfade`. A bare `/pixelocity/transition`, MIDI and key *Trigger Transition* bindings, and the timer / beat auto transitions keep cutting. Project files and chain URLs are unchanged: the fade is runtime only.
- **Duration** is the *Auto Transition → Duration* slider (default 2 s). **0 is a hard cut**, today's behavior.
- **Where it does not run.** `?renderer=wasm` and `?renderer=js` have no hold and cut (the C++ present path stays frozen). If the hold texture cannot be allocated, that cue cuts: no retry, no drop of the working resolution, and the frame loop keeps running. In the render worker the hold and the mix live on the worker's device; the page sends only the duration (see [`RENDER_WORKER.md`](RENDER_WORKER.md)).

Out of scope: a second live stack rendered in parallel, wipe / luma / shader-authored transitions, and the offline stepped clock and export of #1401 (which will feed the same mix factor).

## Set recorder

Under **Share & export**: **● Record set** samples every slot's shader and its four sliders at 20 Hz, storing only changes. **▶ Play** replays the recording through the same path as MIDI/OSC.

- What's recorded is what was on screen. That includes audio-reactive motion and the effect of transitions, so playback is deterministic and does not re-roll randomize.
- During playback, grab any slider to ride it by hand. Playback skips that param until you let go.
- **Export JSON** includes the recording (the optional `timeline` field in the v1 `.vjset.json`) when *Include recording* is ticked. **Import JSON** restores it. Older builds ignore the field.
- Recordings are capped at 200 000 events, roughly 7 minutes with audio driving 6 slots and far longer for hand-driven sets. **My VJ sets** (browser storage) keeps the chain only, not the recording.

## Mobile

On phones and tablets, MIDI controls are hidden. Use touch sliders and chain URLs. Keyboard learn may still work with external keyboards on some tablets. OSC stays available (it is a WebSocket, not WebMIDI) — handy for driving a tablet from a desk on the same network via `?osc_ws=`.

## Tier C physics demos (Physics Lab)

Simulation category — look for the **graph · N passes** badge. Full guide: [`PHYSICS_LAB.md`](PHYSICS_LAB.md).

### Ripple Tank (`ripple-tank`, 7 passes)

- **Click** to drop expanding ring ripples
- **Hold** to drive a local oscillator
- **Audio** bass boosts sources; treble densifies ambient rain
- **4 wave steps/frame** under the pass budget — target **60 fps** on discrete GPU at **balanced**

Params: Wave Speed, Damping, Source Strength, Boundary Reflect.

### Fabric of Reality (`fabric-of-reality`, 7 passes)

- **Hold** near the cloth for a tear force; hover for a gentle push
- **Self Heal** slider reconnects torn springs when elevated
- Soft gravity + velocity clamp — drapes instead of exploding
- Bass breathes wind; mouse spotlight rides the weave

Params: Stiffness, Tear Threshold, Gravity, Self Heal.

### Photonic Caustics (`photonic-caustics-graph`, 4 passes)

- Move the mouse to steer the area light; hold raises light height
- Temporal **accumulator** leaves chromatic ribbons (visible, not a faint wash)
- `emit → trace×2 → accumulate` fits **battery** (4) and balanced alike — extra traces truncate first if over budget

Params: IOR, Light Size, Dispersion, Intensity.

### Chromatographic Fluid (`chromatographic-fluid`, 7 passes)

- **Hold** paints dye + local swirl; **move** steers the wind vane
- **Click** solvent splashes; bass gusts, mids heat, treble sparkle
- Shared velocity — R/G/B dyes separate by viscosity, not three NS solvers

Params: Viscosity Split, Wind, Temperature, Dye Inject.

### Gray-Scott Tank (`gray-scott-tank`, 6 passes)

- **Hold** paints V; **click** seeds spots; four Jacobi steps per frame at balanced
- Feed/Kill sliders map to classic Gray–Scott ranges (clamped U/V)

Params: Feed, Kill, Diffusion, Seed Strength.

### Optical Flow Dream (`optical-flow-dream`, 1 pass)

- Exact `dataTextureC` history estimates flow in the canonical 13-binding path;
  **hold** creates a dream vortex and **click** tears the field
- Battery-friendly single pass; decay + chroma smear follow the inferred flow

Params: Flow Scale, Decay, Chroma Smear, Dream Mix.

### Pass budget in the HUD

**Controls → Render Quality** shows `≤N passes/frame`. That is `performancePolicy.maxPassesPerFrame` (battery 4 / balanced 8 / ultra 16). Over budget, Jacobi/diffuse repeats shrink first so the color pass still runs. Prefer **balanced+** for the 6–7-pass stacks.

### Preset pack

Open **Preset Packs** in VJ Studio for **Physics Lab** solos (Ripple / Fabric / Photonic / Chroma / Gray-Scott / Dream) and the original Triptych, or load [`public/presets/physics-lab.json`](../public/presets/physics-lab.json).

## Troubleshooting

| Issue | Fix |
|-------|-----|
| MIDI devices empty | Grant browser MIDI permission; use Chrome/Edge on desktop |
| Chain link doesn't restore | Ensure shader ids exist in catalog; check URL wasn't truncated |
| OSC status "Relay unreachable" | Start storage_manager with `OSC_RELAY_ENABLED=1`; check the URL/port; a page served over `https` needs a `wss://` relay |
| OSC connects but nothing moves | Check the address prefix `/pixelocity/…`, 0-based slot numbers, and that the slot exists in the current stack; **last:** in the OSC section shows what arrived |
| Audio "fights" my fader | Should not happen — file a bug with the slot / shader id; holds last ~0.6 s after the last MIDI/OSC message |
| Import JSON fails | File must be `.vjset.json` from Export JSON or compatible schema v1 |
| Ripple/fabric look “stuck” on battery | Raise quality to balanced — 7-pass graphs exceed the battery pass cap |
| Fabric explodes | Lower Gravity / raise Stiffness; Self Heal mid-high after tearing |

## Related

- [`PHYSICS_LAB.md`](PHYSICS_LAB.md) — flagship QA, attract dwell, thumbnails
- [`MULTIPASS_GRAPH.md`](MULTIPASS_GRAPH.md) — Tier C graph schema
- [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md) — renderer smoke (separate from Studio)
- Live Studio tab (canvas overlay) — recording / stream bridge via `LiveStudioTab`
