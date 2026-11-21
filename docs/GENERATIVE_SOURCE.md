# Generative source (generator stage)

In **Generative** input mode the picture the effect slots process comes from a generative shader (`gen-*`), not from an image or a video. That shader is *not* one of the effect slots. It is a dedicated stage that runs once per frame ahead of the slot chain, so the user's effect stack (Liquid, …) keeps its slots and processes the generator's picture.

Before this stage, choosing Generative only cleared the source texture. Slot 0 kept its image effect (Liquid), which rendered over black, and the shader picked in the Generative panel was never applied to anything.

## Frame order

```
video ingest → input copy (sourceTex → readTex) → GENERATOR → slot chain → present
```

`webgpu/generator.ts` (`GeneratorStage`) encodes into the frame's single encoder:

1. patch the generator's four sliders into `uniformBuf` zoom_params (bytes 32–47);
2. one compute pass of the generator shader, writing `writeTex`;
3. patch the global zoom_params back (a slot without its own params sees what it always saw);
4. copy `writeTex → readTex`. Slot 0 now reads the generator exactly as it reads an image;
5. feedback copies on the generator's **private** state (see below).

With every slot empty the generator alone fills the frame. Compositor layers, the history ring, direct present, stage outputs and cue crossfades all see an ordinary source.

## Private feedback state

462 of the 465 `gen-*` shaders write `dataTextureA/B` and 390 read `dataTextureC`. Those textures are shared by the effect slots, so a generator on them would corrupt (and be corrupted by) a feedback effect. The stage owns its own A/B/C triple and its own bind group (`createBindGroupForRoles`). Only `readTex`, `writeTex`, history, depth and the uniform / audio buffers are shared with the slot chain.

- Allocated lazily, at the working size and colour format of `readTex`; rebuilt on a size / format / device change; dropped when the shader changes (a new generator never inherits the last one's feedback).
- The bind group is rebuilt whenever any shared texture or buffer it holds changes (resolution scale, device loss).

## Limits

- Single-pass shaders only (no `gen-*` is a graph or multipass chain).
- A shader that needs the group-1 sim ring is refused with one warning (`getGeneratorStatus().skipped === 'sim-ring'`).
- The stage runs only while the input source is `generative`; anywhere else it is inert.
- TS WebGPU backend only (main thread and render worker). WASM and Canvas2D have no stage: `RendererManager.setGenerator` returns `false` and the app falls back to the old behaviour (the shader in slot 0).

## API

| Layer | Call |
| --- | --- |
| `WebGPURenderer` | `setGenerator(id \| null)`, `getGenerator()`, `setGeneratorParams(p1..p4)`, `getGeneratorStatus()` |
| `RendererManager` | `setGenerator(id \| null, { url, meta }?)` loads the shader first; `supportsGenerator()`; replays after a backend switch or device loss |
| Render worker | commands `setGenerator`, `setGeneratorParams` (`worker/protocol.ts`) |
| React | `useGeneratorSource` (`hooks/useGeneratorSource.ts`) |

`useGeneratorSource` follows the Input Source and the Generative panel's pick: leaving Generative turns the stage off; a pick that the device cannot run (the catalog hides rgba32float / deep-workgroup shaders on weak GPUs) is swapped for the first available generative shader instead of leaving a black source. A preview import is armed directly through the manager.

The Generative panel shows the generator's own four sliders; they are separate from slot 0's.

## Attract mode, projects, recordings

- Attract Mode arms a generative pick as the source and leaves the slots alone. A simulation pick is an image effect and still goes in slot 0 over the still; slot 0 is cleared before the next generative pick only if the showcase put that simulation there.
- Project files, share links and the set recorder already stored the generative shader id separately from the slot modes, so they work unchanged.
- Offline render (`recording/offlineRenderJob.ts`) applies a recorded generative source through `host.setGenerator` and turns it off for image / video sources; `restoreLive` re-arms the live generator.

## Tests

- `src/renderer/webgpu/generator.test.ts`: op order, private state, rebuild rules, inactive cases.
- `tests/generator-source.swiftshader.spec.ts`: the real UI on a software WebGPU device, both render threads. Needs `npm run build`.
