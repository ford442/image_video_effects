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
| **Transitions** | Auto-transition timer or audio beat (requires AI VJ mode for some paths) |
| **MIDI & keyboard** | Map hardware CCs, notes, or keys to params and actions |
| **Audio-reactive** | Drive parameter motion from microphone / audio analysis |
| **Share & export** | Chain URL, VJ set link, JSON export/import |
| **My VJ sets** | Locally saved stacks (browser storage) |
| **VJ history** | Restore recent AI-generated stacks |

## MIDI learn (no console required)

1. Expand **VJ Studio → MIDI & keyboard** and enable MIDI.
2. On any parameter slider, click the **🎛** button next to the param name.
3. Move a knob or press a pad on your controller (or press a key for keyboard mapping).
4. Click **Confirm** when the capture appears.

Bindings persist in `localStorage` (`vj_control_bindings`).

## Share links

- **Copy chain URL** — encodes up to 6 slots with compact params (`?chain=…`). Safe to bookmark or send in chat.
- **Share VJ set link** — includes vibe metadata when available.
- **Export JSON** — full portable file including optional MIDI bindings; use **Import JSON** to restore on another machine.

## Mobile

On phones and tablets, MIDI controls are hidden. Use touch sliders and chain URLs. Keyboard learn may still work with external keyboards on some tablets.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| MIDI devices empty | Grant browser MIDI permission; use Chrome/Edge on desktop |
| Chain link doesn't restore | Ensure shader ids exist in catalog; check URL wasn't truncated |
| Import JSON fails | File must be `.vjset.json` from Export JSON or compatible schema v1 |

## Related

- [`WASM_SMOKE_TEST.md`](../WASM_SMOKE_TEST.md) — renderer smoke (separate from Studio)
- Live Studio tab (canvas overlay) — recording / stream bridge via `LiveStudioTab`
