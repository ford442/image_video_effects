# NOTES fork E — snow, luminance-wind (second pass)

HEAD = origin/main 8c537fe6. Measurements: SwiftShader mini-renderer (`agents/mr.mjs`, `agents/mr_box.mjs` = same with a hard-edged near box via `DEPTHBOX=1`), 192² unless stated. No real-GPU look.

## snow
SHADER: snow
IDENTITY: depth-aware blizzard — three parallax layers of tumbling hexagonal flakes over the photo, wind-skewed, snow bank in C that melts and that landing flakes fade into
KEEP VERBATIM: snow_layer / snowflake / hexagon_dist, Idea-1 tumble, Idea-2 land fade, 4 param roles (speed, density, wind, accumulation), melt_rate, mouse.x→wind, A packing, ACES on display, HEAD lighting normal (value-identical), audio (bass→speed, treble→density+sparkle)
ADD:
  3. **depth-occluded flake layers** (`layer_visible`) — far/mid/near planes 0.40/0.65/0.90 (library depth 1 = near); a scene pixel nearer than a layer's plane hides that layer's flakes (smoothstep(plane+0.04, plane+0.22), ≤85 % hidden). Measured: flake pixels inside the near disc 16.4 % → 6.2 % (only the near layer survives), background 16.1 % → 16.0 %. Flat/absent depth → HEAD.
  4. **wind-carried bank / saltation** — bank blends with its upwind neighbour (one exact C.r load, 1 px along sign(wind)) at `min(|wind|·0.045, 0.12)` per frame. At wind=0 it is exactly HEAD. Measured (wind slider 1.0, density 0, 200 frames): bank centroid +8.2 px downwind, bank area +13 %, plume spilling over the cone's lee lip.
FORBID: spring, click ripples, IQ palette, new params, new flake motif, extraBuffer state, dataTextureB — none added.
A PACKING: unchanged — A.r = raw bank, A.g = flake coverage; ACES on writeTexture only.
RESCUES (3, HEAD defects):
  R1 flakes rose — `uv.y*… + time*layer_speed` → `−` (measured dy −4 rows/0.01 s at HEAD, +4 now).
  R2 wind sign — `+ wind_drift` → `−`; HEAD blew flakes toward −x for positive wind although pointer-right feeds +wind. Now wind>0 → +x (measured dx +1 px). Same magnitude; **coordinator may veto** if the old direction was intentional (one-token revert).
  R3 Accumulation slider dead — acc 0 vs 1 on smooth depth: max |diff| 0.0 at HEAD. HEAD thresholded the per-texel normal.y (≈0 on any real depth map) with the wrong sign (depth 1 = near ⇒ floors have normal.y<0). Now: depth slope per uv unit, fixed relief gain 1.5, up-facing = −relief.y. Settles on the cone top / bowl floor of the synthetic scene (acc0 vs acc1 max diff 0.28, 6 % px). HEAD's lighting `normal` is unchanged (density 0, acc 0: 0.0 % px differ).
Diff vs HEAD @192 defaults (flakes+bank): 13.7 % px >12/255 (flake position changed by R1 + the new bank). Timing (load ≈14, min-of-drained, 5 interleaved rounds @256): ratios 0.87/0.98/0.79/1.08/0.87 → median ≈0.87× (noise; one extra C load only when accumulation>0.01).
JSON: `description` added (none before), `depth-aware` added to features (layers now really depth-aware); params / x-meta byte-exact.

## luminance-wind
SHADER: luminance-wind
IDENTITY: luminance-gated raw-HDR history advected downwind by layered curl gusts (held joystick, click fronts, depth parallax, chroma drift); bright regions streak, dark stay
KEEP VERBATIM: curl stack, 4 param roles, lumaGate, depthLayer speed parallax, held jet / click fronts, chroma split taps, raw HDR in A / ACES display, semantic alpha, Idea 1 lee-side shelter, Idea 2 cat's-paw bands
ADD:
  3. **wake-edge eddies** — across-wind swing of the history lookup on the wake's shear layer (`shear = max(4s(1−s), shelter·(1−shelterNear))`), travelling sine along the wind, amplitude on free-stream speed × Turbulence slider. Zero new taps (reuses depthA/depthB, now bound separately). Measured vs eddy-off: 0.61 % px >12/255 (7.0 % >4/255) hard-box scene; 3.8 % >12/255 soft scene. First attempt (rotating the shelter-damped direction) measured 0.00 % — see BRIEFS amendments.
  4. **depth-veered wind** — `rot2(wind, (depth−0.5)·0.55)` before the shelter look-ups (± 16°). Measured vs veer-off: 15.9 % px >12/255 (box), 13.8 % (soft). Zero new taps.
FORBID: IQ palette, springs, second curl stack, extra history taps, new params, extraBuffer state — none added.
A PACKING: unchanged — A/C = raw HDR RGB + semantic alpha; ACES on writeTexture only; B/extraBuffer unused.
RESCUE (1): **washed-out defaults** — injection (0.07…0.34) ignored trailDecay so a static scene settled at injection/(1−decay) = 1.25–3.9× (14× at max decay). Flat 0.3 source @defaults: HEAD 1.91× ACES(src) → 1.25×; @decay 1.0: 2.21× → 1.41×; dark 0.05 source: HEAD 0.086 → 0.047 (source ACES 0.044). Now `injection = clamp((1−decay)·(1 + 0.35·lumaGate + 0.12·mids + 0.30·localJet), 0.03, 0.34)`. Trade-off: new content takes ≈1/(1−decay) frames to build up (the trail-length slider's own meaning). **Coordinator may veto** — it changes the default look of every saved luminance-wind preset (less blown out).
Diff vs HEAD @192 defaults: 100 % px >12/255 (mostly the exposure rescue; max 0.68). Timing (load ≈14, 5 interleaved rounds @256): 1.60/0.59/1.04/0.99/1.16 → median ≈1.04×.
JSON: description extended; params / x-meta byte-exact; features unchanged (already depth-aware, audio-reactive).

## Gates
- `wgsl_precommit_gate.py --files` 2/2 pass; `verify-naga-wasm.mjs --files` 2/2 valid; `audit_dead_sliders.py --files snow luminance-wind`: 0 new dead (snow Accumulation now live); `audit_extrabuffer.py`: PASS; no NaN with p=1,1,1,1 + mouse held + audio 1.5.
- Not done: real-GPU look; ripple/click path of luminance-wind (harness passes 0 ripples) not exercised; upgrades:record, shader lists, ledger, JSON/search-index regeneration (coordinator). Not committed.
- Harness extras (gitignored): `agents/mr_box.mjs` (DEPTHBOX=1 hard-edged depth scene).
